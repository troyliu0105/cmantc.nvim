--- Tests for SourceDocument:get_symbol_at_position line-based matching
--- This function uses LINE-based matching (not character-based):
--- cursor_line >= range.start.line and cursor_line <= range['end'].line

local helpers = require('tests.helpers')
local SourceDocument = require('cmantic.source_document')
local SourceSymbol = require('cmantic.source_symbol')
local SK = SourceSymbol.SymbolKind

local eq = assert.are.same

--- Create a mock LSP DocumentSymbol
--- @param opts table { name, kind, range, selectionRange, children, detail }
local function mock_sym(opts)
  return {
    name = opts.name or 'test',
    kind = opts.kind or SK.Function,
    range = opts.range or {
      start = opts.range_start or { line = opts.start_line or 0, character = opts.start_char or 0 },
      ['end'] = opts.range_end or { line = opts.end_line or 0, character = opts.end_char or 10 },
    },
    selectionRange = opts.selectionRange or {
      start = opts.sel_start or { line = opts.start_line or 0, character = opts.start_char or 0 },
      ['end'] = opts.sel_end or { line = opts.end_line or 0, character = opts.end_char or 10 },
    },
    detail = opts.detail or '',
    children = opts.children or {},
  }
end

--- Create a SourceDocument with manually injected symbols
--- @param lines string[] Buffer content
--- @param symbols table[] Array of SourceSymbol instances to inject
--- @return table SourceDocument with symbols set
local function create_doc_with_symbols(lines, symbols)
  local bufnr = helpers.create_buffer(lines, 'cpp')
  local doc = SourceDocument.new(bufnr)
  doc.symbols = symbols
  return doc
end

describe('get_symbol_at_position', function()
  describe('line-based matching', function()
    it('cursor at line start (char 0) finds symbol on that line', function()
      local lines = {
        'class A {',
        '  void foo();',
        '};',
      }

      -- Method on line 1
      local method_sym = SourceSymbol.new(mock_sym({
        name = 'foo',
        kind = SK.Method,
        start_line = 1, start_char = 2,
        end_line = 1, end_char = 14,
        sel_start = { line = 1, character = 7 },
        sel_end = { line = 1, character = 10 },
      }), 'file:///test.hpp', nil)

      local doc = create_doc_with_symbols(lines, { method_sym })

      -- Cursor at line 1, character 0 (line start)
      local result = doc:get_symbol_at_position({ line = 1, character = 0 })
      assert.truthy(result, 'should find symbol at line start')
      eq('foo', result.name)
    end)

    it('cursor at line end still finds same symbol', function()
      local lines = {
        'class A {',
        '  void foo();',
        '};',
      }

      local method_sym = SourceSymbol.new(mock_sym({
        name = 'foo',
        kind = SK.Method,
        start_line = 1, start_char = 2,
        end_line = 1, end_char = 14,
        sel_start = { line = 1, character = 7 },
        sel_end = { line = 1, character = 10 },
      }), 'file:///test.hpp', nil)

      local doc = create_doc_with_symbols(lines, { method_sym })

      -- Cursor at line 1, character 100 (way past line end)
      local result = doc:get_symbol_at_position({ line = 1, character = 100 })
      assert.truthy(result, 'should find symbol even with high character')
      eq('foo', result.name)
    end)

    it('cursor at line middle still finds same symbol', function()
      local lines = {
        'class A {',
        '  void foo();',
        '};',
      }

      local method_sym = SourceSymbol.new(mock_sym({
        name = 'foo',
        kind = SK.Method,
        start_line = 1, start_char = 2,
        end_line = 1, end_char = 14,
        sel_start = { line = 1, character = 7 },
        sel_end = { line = 1, character = 10 },
      }), 'file:///test.hpp', nil)

      local doc = create_doc_with_symbols(lines, { method_sym })

      -- Cursor at line 1, character 5 (middle of line)
      local result = doc:get_symbol_at_position({ line = 1, character = 5 })
      assert.truthy(result, 'should find symbol at line middle')
      eq('foo', result.name)
    end)
  end)

  describe('nested symbols', function()
    it('cursor on method line inside class returns method (deepest match)', function()
      local lines = {
        'class A {',
        'public:',
        '  void foo();',
        '  int bar();',
        '};',
      }

      -- Class spans lines 0-4
      local class_raw = mock_sym({
        name = 'A',
        kind = SK.Class,
        start_line = 0, start_char = 0,
        end_line = 4, end_char = 2,
        sel_start = { line = 0, character = 6 },
        sel_end = { line = 0, character = 7 },
        children = {
          -- Method foo on line 2
          mock_sym({
            name = 'foo',
            kind = SK.Method,
            start_line = 2, start_char = 2,
            end_line = 2, end_char = 14,
            sel_start = { line = 2, character = 7 },
            sel_end = { line = 2, character = 10 },
          }),
          -- Method bar on line 3
          mock_sym({
            name = 'bar',
            kind = SK.Method,
            start_line = 3, start_char = 2,
            end_line = 3, end_char = 12,
            sel_start = { line = 3, character = 6 },
            sel_end = { line = 3, character = 9 },
          }),
        },
      })

      local class_sym = SourceSymbol.new(class_raw, 'file:///test.hpp', nil)
      local doc = create_doc_with_symbols(lines, { class_sym })

      -- Cursor on line 2 (foo method line) at any character
      local result = doc:get_symbol_at_position({ line = 2, character = 0 })
      assert.truthy(result, 'should find a symbol')
      eq('foo', result.name, 'should return method foo, not class A')
      eq(SK.Method, result.kind)

      -- Cursor on line 3 (bar method line)
      local result2 = doc:get_symbol_at_position({ line = 3, character = 5 })
      assert.truthy(result2, 'should find a symbol')
      eq('bar', result2.name, 'should return method bar, not class A')
    end)

    it('cursor on class definition line (not method line) returns class', function()
      local lines = {
        'class A {',
        'public:',
        '  void foo();',
        '};',
      }

      local class_raw = mock_sym({
        name = 'A',
        kind = SK.Class,
        start_line = 0, start_char = 0,
        end_line = 3, end_char = 2,
        sel_start = { line = 0, character = 6 },
        sel_end = { line = 0, character = 7 },
        children = {
          mock_sym({
            name = 'foo',
            kind = SK.Method,
            start_line = 2, start_char = 2,
            end_line = 2, end_char = 14,
            sel_start = { line = 2, character = 7 },
            sel_end = { line = 2, character = 10 },
          }),
        },
      })

      local class_sym = SourceSymbol.new(class_raw, 'file:///test.hpp', nil)
      local doc = create_doc_with_symbols(lines, { class_sym })

      -- Cursor on line 0 (class declaration line)
      local result = doc:get_symbol_at_position({ line = 0, character = 0 })
      assert.truthy(result, 'should find a symbol')
      eq('A', result.name, 'should return class A')
      eq(SK.Class, result.kind)

      -- Cursor on line 1 (public: line - no method there, but still inside class)
      local result2 = doc:get_symbol_at_position({ line = 1, character = 0 })
      assert.truthy(result2, 'should find a symbol on public: line')
      eq('A', result2.name, 'should return class A for line without method')
    end)
  end)

  describe('empty lines and gaps', function()
    it('empty line between symbols returns parent (class)', function()
      local lines = {
        'class A {',
        'public:',
        '  void foo();',
        '',
        '  void bar();',
        '};',
      }

      local class_raw = mock_sym({
        name = 'A',
        kind = SK.Class,
        start_line = 0, start_char = 0,
        end_line = 5, end_char = 2,
        sel_start = { line = 0, character = 6 },
        sel_end = { line = 0, character = 7 },
        children = {
          mock_sym({
            name = 'foo',
            kind = SK.Method,
            start_line = 2, start_char = 2,
            end_line = 2, end_char = 14,
          }),
          mock_sym({
            name = 'bar',
            kind = SK.Method,
            start_line = 4, start_char = 2,
            end_line = 4, end_char = 14,
          }),
        },
      })

      local class_sym = SourceSymbol.new(class_raw, 'file:///test.hpp', nil)
      local doc = create_doc_with_symbols(lines, { class_sym })

      -- Cursor on line 3 (empty line between foo and bar)
      local result = doc:get_symbol_at_position({ line = 3, character = 0 })
      assert.truthy(result, 'should find parent class on empty line')
      eq('A', result.name, 'empty line should return parent class')
      eq(SK.Class, result.kind)
    end)

    it('empty line outside all symbol ranges returns nil', function()
      local lines = {
        '',
        'class A {',
        '  void foo();',
        '};',
        '',
      }

      local class_raw = mock_sym({
        name = 'A',
        kind = SK.Class,
        start_line = 1, start_char = 0,
        end_line = 3, end_char = 2,
        children = {
          mock_sym({
            name = 'foo',
            kind = SK.Method,
            start_line = 2, start_char = 2,
            end_line = 2, end_char = 14,
          }),
        },
      })

      local class_sym = SourceSymbol.new(class_raw, 'file:///test.hpp', nil)
      local doc = create_doc_with_symbols(lines, { class_sym })

      -- Cursor on line 0 (before class)
      local result = doc:get_symbol_at_position({ line = 0, character = 0 })
      assert.falsy(result, 'line before class should return nil')

      -- Cursor on line 4 (after class closing brace)
      local result2 = doc:get_symbol_at_position({ line = 4, character = 0 })
      assert.falsy(result2, 'line after class should return nil')
    end)
  end)

  describe('multi-line symbols', function()
    it('cursor on any line of multi-line symbol finds it', function()
      local lines = {
        'void longFunction() {',
        '  int x = 1;',
        '  int y = 2;',
        '}',
      }

      -- Function spans lines 0-3
      local func_sym = SourceSymbol.new(mock_sym({
        name = 'longFunction',
        kind = SK.Function,
        start_line = 0, start_char = 0,
        end_line = 3, end_char = 1,
        sel_start = { line = 0, character = 5 },
        sel_end = { line = 0, character = 17 },
      }), 'file:///test.cpp', nil)

      local doc = create_doc_with_symbols(lines, { func_sym })

      -- Test all lines of the function
      for line = 0, 3 do
        local result = doc:get_symbol_at_position({ line = line, character = 0 })
        assert.truthy(result, string.format('should find symbol on line %d', line))
        eq('longFunction', result.name)
      end

      -- Line after function should return nil
      local result_after = doc:get_symbol_at_position({ line = 4, character = 0 })
      assert.falsy(result_after, 'line after function should return nil')
    end)

    it('nested multi-line symbols return deepest match', function()
      local lines = {
        'namespace NS {',
        'class A {',
        '  void longMethod() {',
        '    // body',
        '  }',
        '};',
        '}',
      }

      local ns_raw = mock_sym({
        name = 'NS',
        kind = SK.Namespace,
        start_line = 0, start_char = 0,
        end_line = 6, end_char = 1,
        children = {
          mock_sym({
            name = 'A',
            kind = SK.Class,
            start_line = 1, start_char = 0,
            end_line = 5, end_char = 2,
            children = {
              mock_sym({
                name = 'longMethod',
                kind = SK.Method,
                start_line = 2, start_char = 2,
                end_line = 4, end_char = 4,
              }),
            },
          }),
        },
      })

      local ns_sym = SourceSymbol.new(ns_raw, 'file:///test.hpp', nil)
      local doc = create_doc_with_symbols(lines, { ns_sym })

      -- Line 0: namespace only
      local r0 = doc:get_symbol_at_position({ line = 0, character = 0 })
      assert.truthy(r0)
      eq('NS', r0.name)

      -- Line 1: class definition line (inside namespace, but class is deepest)
      local r1 = doc:get_symbol_at_position({ line = 1, character = 0 })
      assert.truthy(r1)
      eq('A', r1.name, 'line 1 should return class A')

      -- Line 2-4: inside method (deepest match)
      local r2 = doc:get_symbol_at_position({ line = 2, character = 0 })
      assert.truthy(r2)
      eq('longMethod', r2.name, 'line 2 should return method')

      local r3 = doc:get_symbol_at_position({ line = 3, character = 0 })
      assert.truthy(r3)
      eq('longMethod', r3.name, 'line 3 should return method')

      -- Line 5: class closing (inside class, no method there)
      local r5 = doc:get_symbol_at_position({ line = 5, character = 0 })
      assert.truthy(r5)
      eq('A', r5.name, 'line 5 should return class A')
    end)
  end)

  describe('edge cases', function()
    it('returns nil when no symbols', function()
      local lines = { 'int main() {}' }
      local doc = create_doc_with_symbols(lines, {})

      local result = doc:get_symbol_at_position({ line = 0, character = 0 })
      assert.falsy(result, 'should return nil when no symbols')
    end)

    it('returns nil when symbols is nil', function()
      local bufnr = helpers.create_buffer({ 'int main() {}' }, 'cpp')
      local doc = SourceDocument.new(bufnr)
      doc.symbols = nil  -- Explicitly nil

      local result = doc:get_symbol_at_position({ line = 0, character = 0 })
      assert.falsy(result, 'should return nil when symbols is nil')
    end)

    it('handles single-line symbol at buffer start', function()
      local lines = { 'int x = 5;' }

      local var_sym = SourceSymbol.new(mock_sym({
        name = 'x',
        kind = SK.Variable,
        start_line = 0, start_char = 0,
        end_line = 0, end_char = 10,
      }), 'file:///test.cpp', nil)

      local doc = create_doc_with_symbols(lines, { var_sym })

      local result = doc:get_symbol_at_position({ line = 0, character = 0 })
      assert.truthy(result)
      eq('x', result.name)

      -- Line 1 (beyond buffer) should return nil
      local result2 = doc:get_symbol_at_position({ line = 1, character = 0 })
      assert.falsy(result2)
    end)

    it('character position is ignored (only line matters)', function()
      local lines = {
        'class A { void foo(); };',
      }

      -- Single-line class with method
      local class_raw = mock_sym({
        name = 'A',
        kind = SK.Class,
        start_line = 0, start_char = 0,
        end_line = 0, end_char = 24,
        children = {
          mock_sym({
            name = 'foo',
            kind = SK.Method,
            start_line = 0, start_char = 10,
            end_line = 0, end_char = 21,
          }),
        },
      })

      local class_sym = SourceSymbol.new(class_raw, 'file:///test.hpp', nil)
      local doc = create_doc_with_symbols(lines, { class_sym })

      -- All character positions on line 0 should find the method (deepest)
      -- because line-based matching doesn't distinguish character positions
      for char = 0, 23 do
        local result = doc:get_symbol_at_position({ line = 0, character = char })
        assert.truthy(result, string.format('should find symbol at char %d', char))
        eq('foo', result.name, string.format('char %d should find method foo', char))
      end
    end)
  end)
end)
