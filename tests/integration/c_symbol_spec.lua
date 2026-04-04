local helpers = require('tests.helpers')
local CSymbol = require('cmantic.c_symbol')
local SK = require('cmantic.source_symbol').SymbolKind
local SourceDocument = require('cmantic.source_document')

local eq = assert.are.same

local function make_csymbol(lines, opts)
  opts = opts or {}
  local bufnr = helpers.create_buffer(lines, 'cpp')
  local doc = SourceDocument.new(bufnr)

  local raw_sym = {
    name = opts.name or 'test',
    kind = opts.kind or SK.Function,
    range = opts.range or {
      start = { line = opts.start_line or 0, character = opts.start_char or 0 },
      ['end'] = { line = opts.end_line or (#lines - 1), character = opts.end_char or #(lines[#lines] or '') },
    },
    selectionRange = {
      start = { line = opts.sel_start_line or 0, character = opts.sel_start_char or 0 },
      ['end'] = { line = opts.sel_end_line or 0, character = opts.sel_end_char or 0 },
    },
    detail = opts.detail or '',
    children = opts.children or {},
  }

  return CSymbol.new(raw_sym, doc), doc
end

describe('c_symbol', function()
  describe('is_function_declaration', function()
    it('returns true for declaration without body', function()
      local sym = make_csymbol({ 'void foo(int x);' }, {
        name = 'foo', kind = SK.Function,
        sel_start_char = 5, sel_end_char = 8,
      })
      assert.is_true(sym:is_function_declaration())
    end)

    it('returns false for definition with body', function()
      local sym = make_csymbol({ 'void foo(int x) {', '}' }, {
        name = 'foo', kind = SK.Function,
        end_line = 1, end_char = 1,
        sel_start_char = 5, sel_end_char = 8,
      })
      assert.is_false(sym:is_function_declaration())
    end)
  end)

  describe('is_function_definition', function()
    it('returns true for definition with body', function()
      local sym = make_csymbol({ 'void foo(int x) {', '}' }, {
        name = 'foo', kind = SK.Function,
        end_line = 1, end_char = 1,
        sel_start_char = 5, sel_end_char = 8,
      })
      assert.is_true(sym:is_function_definition())
    end)

    it('returns false for declaration without body', function()
      local sym = make_csymbol({ 'void foo(int x);' }, {
        name = 'foo', kind = SK.Function,
        sel_start_char = 5, sel_end_char = 8,
      })
      assert.is_false(sym:is_function_definition())
    end)
  end)

  describe('specifier detection', function()
    it('detects virtual keyword', function()
      local sym = make_csymbol({ 'virtual void foo();' }, {
        name = 'foo', kind = SK.Method,
        sel_start_char = 13, sel_end_char = 16,
      })
      assert.is_true(sym:is_virtual())
    end)

    it('detects static keyword', function()
      local sym = make_csymbol({ 'static int count();' }, {
        name = 'count', kind = SK.Method,
        sel_start_char = 11, sel_end_char = 16,
      })
      assert.is_true(sym:is_static())
    end)

    it('detects inline keyword', function()
      local sym = make_csymbol({ 'inline void foo() {}' }, {
        name = 'foo', kind = SK.Function,
        sel_start_char = 12, sel_end_char = 15,
      })
      assert.is_true(sym:is_inline())
    end)

    it('detects const qualifier in leading text', function()
      local sym = make_csymbol({ 'const int& getValue();' }, {
        name = 'getValue', kind = SK.Method,
        sel_start_char = 10, sel_end_char = 18,
      })
      assert.is_true(sym:is_const())
    end)
  end)

  describe('getter/setter names', function()
    it('generates getter name for member variable', function()
      local bufnr = helpers.create_buffer({
        'class MyClass {',
        'public:',
        '    int age;',
        '};',
      }, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local parent_raw = {
        name = 'MyClass', kind = SK.Class,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 3, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 13 } },
        detail = '', children = {},
      }
      local parent_sym = require('cmantic.source_symbol').new(parent_raw, doc.uri, nil)

      local csym = CSymbol.new({
        name = 'age',
        kind = SK.Field,
        range = { start = { line = 2, character = 4 }, ['end'] = { line = 2, character = 12 } },
        selectionRange = { start = { line = 2, character = 8 }, ['end'] = { line = 2, character = 11 } },
        detail = 'int',
        children = {},
      }, doc)
      csym.parent = parent_sym

      local getter = csym:getter_name()
      local setter = csym:setter_name()
      eq('get_age', getter)
      eq('set_age', setter)
    end)
  end)

  describe('format_declaration', function()
    local config = require('cmantic.config')

    it('generates definition with body from simple void function declaration', function()
      local sym, doc = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      -- Create a target document (empty source file)
      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local text = sym:format_declaration(target_doc, { line = 0, character = 0 }, '', false)

      assert.is_not_nil(text:find('void foo()'))
      assert.is_not_nil(text:find('{\n}'))
    end)

    it('strips default values from parameters', function()
      local sym, doc = make_csymbol({ 'void bar(int x = 5, const std::string& s = "hello");' }, {
        name = 'bar',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local text = sym:format_declaration(target_doc, { line = 0, character = 0 }, '', false)

      assert.is_not_nil(text:find('void bar'))
      -- Default values should be stripped
      assert.is_nil(text:find('= 5'))
      assert.is_nil(text:find('= "hello"'))
    end)

    it('strips virtual keyword from virtual method', function()
      local sym, doc = make_csymbol({ 'virtual void process();' }, {
        name = 'process',
        kind = SK.Method,
        sel_start_char = 13,
        sel_end_char = 20,
      })

      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local text = sym:format_declaration(target_doc, { line = 0, character = 0 }, '', false)

      assert.is_not_nil(text:find('void process()'))
      assert.is_nil(text:find('virtual'))
    end)

    it('prepends scope string for scoped function', function()
      local sym, doc = make_csymbol({ 'void method();' }, {
        name = 'method',
        kind = SK.Method,
        sel_start_char = 5,
        sel_end_char = 11,
      })

      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local text = sym:format_declaration(target_doc, { line = 0, character = 0 }, 'MyClass::', false)

      assert.is_not_nil(text:find('MyClass::method'))
    end)

    it('uses new_line curly brace style when configured', function()
      local original_style = config.values.cpp_curly_brace_function
      config.values.cpp_curly_brace_function = 'new_line'

      local sym, doc = make_csymbol({ 'void test();' }, {
        name = 'test',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 9,
      })

      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local text = sym:format_declaration(target_doc, { line = 0, character = 0 }, '', false)

      -- Should have newline before brace
      assert.is_not_nil(text:find('\n{\n}'))

      config.values.cpp_curly_brace_function = original_style
    end)

    it('uses same_line curly brace style when configured', function()
      local original_style = config.values.cpp_curly_brace_function
      config.values.cpp_curly_brace_function = 'same_line'

      local sym, doc = make_csymbol({ 'void test();' }, {
        name = 'test',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 9,
      })

      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local text = sym:format_declaration(target_doc, { line = 0, character = 0 }, '', false)

      -- Should have space before brace (same line)
      assert.is_not_nil(text:find(' {\n}'))

      config.values.cpp_curly_brace_function = original_style
    end)
  end)

  describe('new_function_definition', function()
    it('returns empty string for function definitions (not declarations)', function()
      local sym = make_csymbol({ 'void foo() {', '  // body', '}' }, {
        name = 'foo',
        kind = SK.Function,
        end_line = 2,
        end_char = 1,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local text = sym:new_function_definition(target_doc, { line = 0, character = 0 })

      eq('', text)
    end)

    it('returns formatted definition for function declarations', function()
      local sym = make_csymbol({ 'void bar(int x);' }, {
        name = 'bar',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local text = sym:new_function_definition(target_doc, { line = 0, character = 0 })

      assert.is_not_nil(text:find('void bar'))
      assert.is_not_nil(text:find('{\n}'))
    end)
  end)

  describe('new_function_declaration', function()
    it('returns empty string for function declarations (not definitions)', function()
      local sym = make_csymbol({ 'void foo(int x);' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local text = sym:new_function_declaration()

      eq('', text)
    end)

    it('returns declaration with semicolon from definition', function()
      local sym = make_csymbol({ 'void process(int count) {', '  // body', '}' }, {
        name = 'process',
        kind = SK.Function,
        end_line = 2,
        end_char = 1,
        sel_start_char = 5,
        sel_end_char = 12,
      })

      local text = sym:new_function_declaration()

      assert.is_not_nil(text:find('void process'))
      assert.is_not_nil(text:find('int count'))
      -- Should end with semicolon
      assert.is_not_nil(text:find(';$'))
    end)

    it('includes return type in declaration', function()
      local sym = make_csymbol({ 'int getValue() {', '  return 42;', '}' }, {
        name = 'getValue',
        kind = SK.Method,
        end_line = 2,
        end_char = 1,
        sel_start_char = 4,
        sel_end_char = 12,
      })

      local text = sym:new_function_declaration()

      assert.is_not_nil(text:find('int getValue'))
      assert.is_not_nil(text:find(';$'))
    end)
  end)
end)
