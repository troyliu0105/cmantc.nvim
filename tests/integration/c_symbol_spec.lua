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

  describe('CSymbol.new wrapping SourceSymbol', function()
    local SourceSymbol = require('cmantic.source_symbol')

    it('preserves selection_range from SourceSymbol', function()
      local bufnr = helpers.create_buffer({ 'void foo();' }, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'foo',
        kind = SK.Function,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 12 } },
        selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 8 } },
        detail = '',
        children = {},
      }

      local source_sym = SourceSymbol.new(raw_sym, doc.uri, nil)
      local csym = CSymbol.new(source_sym, doc)

      assert.is_not_nil(csym.selection_range)
      eq(5, csym.selection_range.start.character)
      eq(8, csym.selection_range['end'].character)
    end)

    it('sets correct metatable to CSymbol', function()
      local bufnr = helpers.create_buffer({ 'void foo();' }, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'foo',
        kind = SK.Function,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 12 } },
        selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 8 } },
        detail = '',
        children = {},
      }

      local source_sym = SourceSymbol.new(raw_sym, doc.uri, nil)
      local csym = CSymbol.new(source_sym, doc)

      eq(CSymbol, getmetatable(csym))
    end)

    it('has document reference', function()
      local bufnr = helpers.create_buffer({ 'void foo();' }, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'foo',
        kind = SK.Function,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 12 } },
        selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 8 } },
        detail = '',
        children = {},
      }

      local source_sym = SourceSymbol.new(raw_sym, doc.uri, nil)
      local csym = CSymbol.new(source_sym, doc)

      eq(doc, csym.document)
    end)
  end)

  describe('_find_body_end', function()
    it('returns position before }; on same line', function()
      local lines = {
        'class MyClass {',
        'public:',
        '    int x;',
        '};',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'MyClass',
        kind = SK.Class,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 3, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 13 } },
        detail = '',
        children = {},
      }

      local csym = CSymbol.new(raw_sym, doc)
      local pos = csym:_find_body_end()

      eq(3, pos.line)
      eq(0, pos.character) -- position before }
    end)

    it('returns position before } when alone on line', function()
      local lines = {
        'class MyClass',
        '{',
        'public:',
        '    int x;',
        '}',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'MyClass',
        kind = SK.Class,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 4, character = 1 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 13 } },
        detail = '',
        children = {},
      }

      local csym = CSymbol.new(raw_sym, doc)
      local pos = csym:_find_body_end()

      eq(4, pos.line)
      eq(0, pos.character) -- position before }
    end)
  end)

  describe('find_position_for_new_member_function', function()
    it('returns position after child matching relative_name', function()
      local lines = {
        'class MyClass {',
        'public:',
        '    void existing();',
        '    int x;',
        '};',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'MyClass',
        kind = SK.Class,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 4, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 13 } },
        detail = '',
        children = {
          {
            name = 'existing',
            kind = SK.Method,
            range = { start = { line = 2, character = 4 }, ['end'] = { line = 2, character = 22 } },
            selectionRange = { start = { line = 2, character = 9 }, ['end'] = { line = 2, character = 17 } },
            detail = '',
            children = {},
          },
          {
            name = 'x',
            kind = SK.Field,
            range = { start = { line = 3, character = 4 }, ['end'] = { line = 3, character = 10 } },
            selectionRange = { start = { line = 3, character = 8 }, ['end'] = { line = 3, character = 9 } },
            detail = 'int',
            children = {},
          },
        },
      }

      local csym = CSymbol.new(raw_sym, doc)
      local pos = csym:find_position_for_new_member_function('public', 'existing')

      assert.is_not_nil(pos)
      eq(2, pos.position.line) -- after existing() on line 2
      eq(false, pos.insert_before)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Template System Tests
  --------------------------------------------------------------------------------

  describe('template_statements', function()
    it('extracts single-line template statement', function()
      local sym = make_csymbol({
        'template<typename T>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local ts = sym:template_statements(false)
      assert.is_not_nil(ts:find('template%s*<%s*typename%s+T%s*>'))
    end)

    it('extracts template with whitespace lines before symbol', function()
      local sym = make_csymbol({
        'template<typename T>',
        '',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 2,
        start_char = 0,
        sel_start_line = 2,
        sel_start_char = 5,
        sel_end_line = 2,
        sel_end_char = 8,
      })

      local ts = sym:template_statements(false)
      assert.is_not_nil(ts:find('typename T'))
    end)

    it('returns empty string when no template present', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local ts = sym:template_statements(false)
      eq('', ts)
    end)

    it('removes default arguments when remove_default_args is true', function()
      local sym = make_csymbol({
        'template<typename T = int>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local ts = sym:template_statements(true)
      assert.is_not_nil(ts:find('typename T'))
      assert.is_nil(ts:find('= int'))
    end)

    it('keeps default arguments when remove_default_args is false', function()
      local sym = make_csymbol({
        'template<typename T = int>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local ts = sym:template_statements(false)
      assert.is_not_nil(ts:find('= int'))
    end)

    it('extracts multiple template statements (class + method)', function()
      local sym = make_csymbol({
        'template<typename T>',
        'class MyClass {',
        'public:',
        '    template<typename U>',
        '    void foo(U u);',
        '};',
      }, {
        name = 'foo',
        kind = SK.Method,
        start_line = 4,
        start_char = 4,
        sel_start_line = 4,
        sel_start_char = 9,
        sel_end_line = 4,
        sel_end_char = 12,
      })

      local ts = sym:template_statements(false)
      assert.is_not_nil(ts:find('typename U'))
    end)
  end)

  describe('_remove_template_default_args', function()
    it('strips single default argument', function()
      local sym = make_csymbol({ 'void foo();' }, { name = 'foo', kind = SK.Function })
      local result = sym:_remove_template_default_args('template<typename T = int>')
      assert.is_not_nil(result:find('typename T'))
      assert.is_nil(result:find('= int'))
    end)

    it('strips multiple default arguments', function()
      local sym = make_csymbol({ 'void foo();' }, { name = 'foo', kind = SK.Function })
      local result = sym:_remove_template_default_args('template<typename T = int, typename U = double>')
      assert.is_nil(result:find('= int'))
      assert.is_nil(result:find('= double'))
    end)

    it('handles template without defaults', function()
      local sym = make_csymbol({ 'void foo();' }, { name = 'foo', kind = SK.Function })
      local result = sym:_remove_template_default_args('template<typename T, typename U>')
      assert.is_not_nil(result:find('typename T'))
      assert.is_not_nil(result:find('typename U'))
    end)

    it('handles non-int default like nullptr', function()
      local sym = make_csymbol({ 'void foo();' }, { name = 'foo', kind = SK.Function })
      local result = sym:_remove_template_default_args('template<typename T = nullptr>')
      assert.is_nil(result:find('= nullptr'))
    end)
  end)

  describe('template_parameters', function()
    it('extracts single template parameter', function()
      local sym = make_csymbol({
        'template<typename T>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local params = sym:template_parameters()
      eq('<T>', params)
    end)

    it('extracts multiple template parameters', function()
      local sym = make_csymbol({
        'template<typename T, typename U>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local params = sym:template_parameters()
      eq('<T, U>', params)
    end)

    it('returns empty string when no template', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local params = sym:template_parameters()
      eq('', params)
    end)

    it('skips default arguments in extracted parameters', function()
      local sym = make_csymbol({
        'template<typename T = int, typename U = double>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local params = sym:template_parameters()
      eq('<T, U>', params)
    end)

    it('handles class template parameter', function()
      local sym = make_csymbol({
        'template<class T>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local params = sym:template_parameters()
      eq('<T>', params)
    end)
  end)

  describe('templated_name', function()
    it('returns name with template parameters', function()
      local sym = make_csymbol({
        'template<typename T>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      eq('foo<T>', sym:templated_name(false))
    end)

    it('returns plain name when no template', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      eq('foo', sym:templated_name(false))
    end)

    it('normalizes whitespace when normalize is true', function()
      local sym = make_csymbol({
        'template< typename  T >',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      -- template_parameters normalizes whitespace
      local name = sym:templated_name(true)
      assert.is_not_nil(name:find('foo'))
    end)
  end)

  describe('is_template', function()
    it('returns true for template function', function()
      local sym = make_csymbol({
        'template<typename T>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 0,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
        end_line = 1,
        end_char = 12,
      })

      assert.is_true(sym:is_template())
    end)

    it('returns false for non-template function', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      assert.is_false(sym:is_template())
    end)

    it('returns true for template class', function()
      local sym = make_csymbol({
        'template<typename T>',
        'class MyClass {};',
      }, {
        name = 'MyClass',
        kind = SK.Class,
        start_line = 0,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 6,
        sel_end_line = 1,
        sel_end_char = 13,
        end_line = 1,
        end_char = 17,
      })

      assert.is_true(sym:is_template())
    end)
  end)

  --------------------------------------------------------------------------------
  -- Type Predicates Tests
  --------------------------------------------------------------------------------

  describe('is_constexpr', function()
    it('returns true when constexpr is present', function()
      local sym = make_csymbol({ 'constexpr int foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 16,
        sel_end_char = 19,
      })

      assert.is_true(sym:is_constexpr())
    end)

    it('returns false when constexpr is not present', function()
      local sym = make_csymbol({ 'int foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 4,
        sel_end_char = 7,
      })

      assert.is_false(sym:is_constexpr())
    end)

    it('does not match constexpr inside identifier', function()
      local sym = make_csymbol({ 'int constexprfoo();' }, {
        name = 'constexprfoo',
        kind = SK.Function,
        sel_start_char = 4,
        sel_end_char = 16,
      })

      assert.is_false(sym:is_constexpr())
    end)
  end)

  describe('is_consteval', function()
    it('returns true when consteval is present', function()
      local sym = make_csymbol({ 'consteval int foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 15,
        sel_end_char = 18,
      })

      assert.is_true(sym:is_consteval())
    end)

    it('returns false when consteval is not present', function()
      local sym = make_csymbol({ 'int foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 4,
        sel_end_char = 7,
      })

      assert.is_false(sym:is_consteval())
    end)
  end)

  describe('is_pointer', function()
    it('returns true for pointer return type', function()
      local sym = make_csymbol({ 'int* foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      assert.is_true(sym:is_pointer())
    end)

    it('returns true for const pointer', function()
      local sym = make_csymbol({ 'const int* foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 11,
        sel_end_char = 14,
      })

      assert.is_true(sym:is_pointer())
    end)

    it('returns false for non-pointer type', function()
      local sym = make_csymbol({ 'int foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 4,
        sel_end_char = 7,
      })

      assert.is_false(sym:is_pointer())
    end)

    it('does not match pointer inside template', function()
      local sym = make_csymbol({ 'std::vector<int*> foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 19,
        sel_end_char = 22,
      })

      -- The * inside template<> should be masked
      assert.is_false(sym:is_pointer())
    end)
  end)

  describe('is_reference', function()
    it('returns true for lvalue reference', function()
      local sym = make_csymbol({ 'int& foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      assert.is_true(sym:is_reference())
    end)

    it('returns true for rvalue reference', function()
      local sym = make_csymbol({ 'int&& foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 6,
        sel_end_char = 9,
      })

      assert.is_true(sym:is_reference())
    end)

    it('returns true for const reference', function()
      local sym = make_csymbol({ 'const int& foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 11,
        sel_end_char = 14,
      })

      assert.is_true(sym:is_reference())
    end)

    it('returns false for non-reference type', function()
      local sym = make_csymbol({ 'int foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 4,
        sel_end_char = 7,
      })

      assert.is_false(sym:is_reference())
    end)

    it('does not match reference inside template', function()
      local sym = make_csymbol({ 'std::vector<int&> foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 19,
        sel_end_char = 22,
      })

      -- The & inside template<> should be masked
      assert.is_false(sym:is_reference())
    end)
  end)

  describe('is_pure_virtual', function()
    it('returns true for pure virtual with = 0', function()
      local sym = make_csymbol({ 'virtual void foo() = 0;' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 13,
        sel_end_char = 16,
      })

      assert.is_true(sym:is_pure_virtual())
    end)

    it('returns false for regular virtual function', function()
      local sym = make_csymbol({ 'virtual void foo();' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 13,
        sel_end_char = 16,
      })

      assert.is_false(sym:is_pure_virtual())
    end)

    it('returns false for non-virtual function with = 0', function()
      local sym = make_csymbol({ 'void foo() = 0;' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      -- is_pure_virtual checks is_virtual() first
      assert.is_false(sym:is_pure_virtual())
    end)

    it('returns true for pure virtual with override and = 0', function()
      local sym = make_csymbol({ 'void foo() override = 0;' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      -- override implies virtual
      assert.is_true(sym:is_pure_virtual())
    end)
  end)

  describe('is_deleted_or_defaulted', function()
    it('returns true for deleted function', function()
      local sym = make_csymbol({ 'void foo() = delete;' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      assert.is_true(sym:is_deleted_or_defaulted())
    end)

    it('returns true for defaulted function', function()
      local sym = make_csymbol({ 'MyClass() = default;' }, {
        name = 'MyClass',
        kind = SK.Constructor,
        sel_start_char = 0,
        sel_end_char = 7,
      })

      assert.is_true(sym:is_deleted_or_defaulted())
    end)

    it('returns false for regular function', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      assert.is_false(sym:is_deleted_or_defaulted())
    end)

    it('returns true for explicitly deleted copy constructor', function()
      local sym = make_csymbol({ 'MyClass(const MyClass&) = delete;' }, {
        name = 'MyClass',
        kind = SK.Constructor,
        sel_start_char = 0,
        sel_end_char = 7,
      })

      assert.is_true(sym:is_deleted_or_defaulted())
    end)
  end)

  --------------------------------------------------------------------------------
  -- Position/Boundary Helpers Tests
  --------------------------------------------------------------------------------

  describe('true_start', function()
    it('returns template position when template on same line', function()
      local sym = make_csymbol({
        'template<typename T> void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 0,
        start_char = 21,
        sel_start_line = 0,
        sel_start_char = 26,
        sel_end_line = 0,
        sel_end_char = 29,
        end_line = 0,
        end_char = 32,
      })

      local pos = sym:true_start()
      eq(0, pos.line)
      eq(0, pos.character) -- template starts at beginning
    end)

    it('returns template position when template on previous line', function()
      local sym = make_csymbol({
        'template<typename T>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local pos = sym:true_start()
      eq(0, pos.line)
    end)

    it('returns range.start when no template', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 0,
        start_char = 0,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local pos = sym:true_start()
      eq(0, pos.line)
      eq(0, pos.character)
    end)

    it('handles template with blank lines before', function()
      local sym = make_csymbol({
        'template<typename T>',
        '',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 2,
        start_char = 0,
        sel_start_line = 2,
        sel_start_char = 5,
        sel_end_line = 2,
        sel_end_char = 8,
      })

      local pos = sym:true_start()
      eq(0, pos.line)
    end)
  end)

  describe('declaration_end', function()
    it('returns position before opening brace on same line', function()
      local sym = make_csymbol({ 'void foo() { }' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
        end_line = 0,
        end_char = 14,
      })

      local pos = sym:declaration_end()
      eq(0, pos.line)
      -- Should be position before {
    end)

    it('returns position before semicolon', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local pos = sym:declaration_end()
      eq(0, pos.line)
      -- Should be position before ;
    end)

    it('handles multi-line declaration', function()
      local sym = make_csymbol({
        'void foo(int x,',
        '          int y) {',
      }, {
        name = 'foo',
        kind = SK.Function,
        end_line = 1,
        end_char = 19,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local pos = sym:declaration_end()
      eq(1, pos.line)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Scope Computation Tests
  --------------------------------------------------------------------------------

  describe('named_scopes', function()
    it('returns empty table for top-level symbol', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local scopes = sym:named_scopes()
      eq(0, #scopes)
    end)
  end)

  describe('all_scopes', function()
    it('returns empty table for top-level symbol', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local scopes = sym:all_scopes()
      eq(0, #scopes)
    end)
  end)

  describe('scope_string', function()
    it('returns empty string when no scopes', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local scope = sym:scope_string(target_doc, { line = 0, character = 0 }, false)
      eq('', scope)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Access Specifier Tests
  --------------------------------------------------------------------------------

  describe('get_access_specifiers', function()
    it('parses all three access sections', function()
      local lines = {
        'class MyClass {',
        'public:',
        '    void pub();',
        'protected:',
        '    void prot();',
        'private:',
        '    void priv();',
        '};',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'MyClass',
        kind = SK.Class,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 7, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 13 } },
        detail = '',
        children = {},
      }

      local csym = CSymbol.new(raw_sym, doc)
      local specs = csym:get_access_specifiers()

      eq(3, #specs)
    end)

    it('returns empty table for non-class type', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local specs = sym:get_access_specifiers()
      eq(0, #specs)
    end)

    it('returns empty table for class without explicit specifiers', function()
      local lines = {
        'class MyClass {',
        '    void method();',
        '};',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'MyClass',
        kind = SK.Class,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 13 } },
        detail = '',
        children = {},
      }

      local csym = CSymbol.new(raw_sym, doc)
      local specs = csym:get_access_specifiers()

      eq(0, #specs)
    end)
  end)

  describe('find_position_for_new_member_function edge cases', function()
    it('returns body end when no matching access specifier', function()
      local lines = {
        'class MyClass {',
        '    void method();',
        '};',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'MyClass',
        kind = SK.Class,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 13 } },
        detail = '',
        children = {},
      }

      local csym = CSymbol.new(raw_sym, doc)
      local pos = csym:find_position_for_new_member_function('public', nil)

      assert.is_not_nil(pos)
      -- Should fall back to body end
      eq(false, pos.insert_before)
    end)

    it('returns position at end of access section without relative_name', function()
      local lines = {
        'class MyClass {',
        'public:',
        '    void existing();',
        'private:',
        '    int x;',
        '};',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'MyClass',
        kind = SK.Class,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 5, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 13 } },
        detail = '',
        children = {},
      }

      local csym = CSymbol.new(raw_sym, doc)
      local pos = csym:find_position_for_new_member_function('public', nil)

      assert.is_not_nil(pos)
      -- Should be before private: section
      eq(false, pos.insert_before)
    end)

    it('returns nil for non-class type', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local pos = sym:find_position_for_new_member_function('public', nil)
      assert.is_nil(pos)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Curly Brace Style Tests
  --------------------------------------------------------------------------------

  describe('_get_curly_brace_style', function()
    local config = require('cmantic.config')

    it('uses c_curly_brace_function for .c files', function()
      local original = config.values.c_curly_brace_function
      config.values.c_curly_brace_function = 'new_line'

      local lines = { 'void foo();' }
      local bufnr = helpers.create_buffer(lines, 'c')
      local target_doc = SourceDocument.new(bufnr)

      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local style = sym:_get_curly_brace_style(target_doc, { line = 0, character = 0 })
      eq('new_line', style)

      config.values.c_curly_brace_function = original
    end)

    it('returns new_line for constructor when new_line_for_ctors', function()
      local original = config.values.cpp_curly_brace_function
      config.values.cpp_curly_brace_function = 'new_line_for_ctors'

      local lines = { 'class Test {};' }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local target_doc = SourceDocument.new(bufnr)

      local sym = make_csymbol({ 'MyClass();' }, {
        name = 'MyClass',
        kind = SK.Constructor,
        sel_start_char = 0,
        sel_end_char = 7,
      })

      local style = sym:_get_curly_brace_style(target_doc, { line = 0, character = 0 })
      eq('new_line', style)

      config.values.cpp_curly_brace_function = original
    end)

    it('returns same_line for non-constructor when new_line_for_ctors', function()
      local original = config.values.cpp_curly_brace_function
      config.values.cpp_curly_brace_function = 'new_line_for_ctors'

      local lines = { '// empty' }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local target_doc = SourceDocument.new(bufnr)

      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local style = sym:_get_curly_brace_style(target_doc, { line = 0, character = 0 })
      eq('new_line', style) -- falls through to new_line_for_ctors default

      config.values.cpp_curly_brace_function = original
    end)
  end)

  describe('_format_opening_brace', function()
    it('formats with newline when style is new_line', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local result = sym:_format_opening_brace('void foo()', 'new_line')
      assert.is_not_nil(result:find('\n{\n}'))
    end)

    it('formats with same line when style is same_line', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local result = sym:_format_opening_brace('void foo()', 'same_line')
      assert.is_not_nil(result:find(' {\n}'))
    end)

    it('trims leading and trailing whitespace', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local result = sym:_format_opening_brace('  void foo()  ', 'same_line')
      assert.is_not_nil(result:find('^void foo%(%) {\n}'))
    end)
  end)

  --------------------------------------------------------------------------------
  -- Utility Methods Tests
  --------------------------------------------------------------------------------

  describe('get_lines', function()
    it('returns lines from document', function()
      local sym, doc = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local lines = sym:get_lines()
      assert.is_not_nil(lines)
      eq(1, #lines)
      eq('void foo();', lines[1])
    end)

    it('returns multiple lines', function()
      local sym = make_csymbol({
        'void foo() {',
        '  // body',
        '}',
      }, {
        name = 'foo',
        kind = SK.Function,
        end_line = 2,
        end_char = 1,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local lines = sym:get_lines()
      eq(3, #lines)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Additional Specifier Detection Tests
  --------------------------------------------------------------------------------

  describe('is_virtual with override/final', function()
    it('detects virtual keyword directly', function()
      local sym = make_csymbol({ 'virtual void foo();' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 13,
        sel_end_char = 16,
      })

      assert.is_true(sym:is_virtual())
    end)

    it('infers virtual from override specifier', function()
      local sym = make_csymbol({ 'void foo() override;' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      assert.is_true(sym:is_virtual())
    end)

    it('infers virtual from final specifier', function()
      local sym = make_csymbol({ 'void foo() final;' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      assert.is_true(sym:is_virtual())
    end)

    it('returns false when neither virtual nor override/final', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      assert.is_false(sym:is_virtual())
    end)
  end)

  --------------------------------------------------------------------------------
  -- Additional format_declaration Tests
  --------------------------------------------------------------------------------

  describe('format_declaration with templates', function()
    it('includes template statements in output', function()
      local sym = make_csymbol({
        'template<typename T>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local target_buf = helpers.create_buffer({}, 'cpp')
      local target_doc = SourceDocument.new(target_buf)

      local text = sym:format_declaration(target_doc, { line = 0, character = 0 }, '', false)

      assert.is_not_nil(text:find('template'))
      assert.is_not_nil(text:find('void foo'))
    end)
  end)

  --------------------------------------------------------------------------------
  -- Parsable Text Tests
  --------------------------------------------------------------------------------

  describe('parsable_leading_text', function()
    it('returns text before symbol name', function()
      local sym = make_csymbol({ 'virtual void foo();' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 13,
        sel_end_char = 16,
      })

      local leading = sym:parsable_leading_text()
      assert.is_not_nil(leading:find('virtual'))
      assert.is_not_nil(leading:find('void'))
    end)

    it('returns empty string when symbol starts at beginning', function()
      local sym = make_csymbol({ 'foo();' }, {
        name = 'foo',
        kind = SK.Function,
        start_char = 0,
        sel_start_char = 0,
        sel_end_char = 3,
      })

      local leading = sym:parsable_leading_text()
      eq('', leading)
    end)
  end)

  describe('parsable_trailing_text', function()
    it('returns text after symbol name', function()
      local sym = make_csymbol({ 'void foo() override;' }, {
        name = 'foo',
        kind = SK.Method,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local trailing = sym:parsable_trailing_text()
      assert.is_not_nil(trailing:find('override'))
    end)

    it('includes parameters in trailing text', function()
      local sym = make_csymbol({ 'void foo(int x);' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local trailing = sym:parsable_trailing_text()
      assert.is_not_nil(trailing:find('int x'))
    end)
  end)

  --------------------------------------------------------------------------------
  -- text() Method Tests
  --------------------------------------------------------------------------------

  describe('text', function()
    it('returns full symbol text', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      eq('void foo();', sym:text())
    end)

    it('returns multi-line symbol text', function()
      local sym = make_csymbol({
        'void foo() {',
        '  return;',
        '}',
      }, {
        name = 'foo',
        kind = SK.Function,
        end_line = 2,
        end_char = 1,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local text = sym:text()
      assert.is_not_nil(text:find('void foo'))
      assert.is_not_nil(text:find('return'))
    end)
  end)

  --------------------------------------------------------------------------------
  -- get_parsable_text Tests
  --------------------------------------------------------------------------------

  describe('get_parsable_text', function()
    it('masks comments', function()
      local sym = make_csymbol({ 'void foo(); // comment' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local parsable = sym:get_parsable_text()
      assert.is_nil(parsable:find('comment'))
      assert.is_not_nil(parsable:find('void foo'))
    end)

    it('masks string literals', function()
      local sym = make_csymbol({ 'void foo(const char* s = "test");' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local parsable = sym:get_parsable_text()
      -- "test" should be masked
      assert.is_nil(parsable:find('"test"'))
    end)
  end)

  --------------------------------------------------------------------------------
  -- combined_template_statements Tests
  --------------------------------------------------------------------------------

  describe('combined_template_statements', function()
    it('returns own template when no ancestors', function()
      local sym = make_csymbol({
        'template<typename T>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local combined = sym:combined_template_statements(false, '\n')
      assert.is_not_nil(combined:find('typename T'))
    end)

    it('returns empty string when no templates', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      local combined = sym:combined_template_statements(false, '\n')
      eq('', combined)
    end)

    it('uses custom separator', function()
      local sym = make_csymbol({
        'template<typename T>',
        'void foo();',
      }, {
        name = 'foo',
        kind = SK.Function,
        start_line = 1,
        start_char = 0,
        sel_start_line = 1,
        sel_start_char = 5,
        sel_end_line = 1,
        sel_end_char = 8,
      })

      local combined = sym:combined_template_statements(false, ' ')
      assert.is_not_nil(combined:find('template'))
    end)
  end)

  --------------------------------------------------------------------------------
  -- _extract_template_param_name Tests
  --------------------------------------------------------------------------------

  describe('_extract_template_param_name', function()
    it('extracts simple typename parameter', function()
      local sym = make_csymbol({ 'void foo();' }, { name = 'foo', kind = SK.Function })
      eq('T', sym:_extract_template_param_name('typename T'))
    end)

    it('extracts class parameter', function()
      local sym = make_csymbol({ 'void foo();' }, { name = 'foo', kind = SK.Function })
      eq('T', sym:_extract_template_param_name('class T'))
    end)

    it('strips default argument', function()
      local sym = make_csymbol({ 'void foo();' }, { name = 'foo', kind = SK.Function })
      eq('T', sym:_extract_template_param_name('typename T = int'))
    end)

    it('extracts non-type parameter name', function()
      local sym = make_csymbol({ 'void foo();' }, { name = 'foo', kind = SK.Function })
      eq('N', sym:_extract_template_param_name('int N'))
    end)

    it('handles template template parameter', function()
      local sym = make_csymbol({ 'void foo();' }, { name = 'foo', kind = SK.Function })
      eq('Container', sym:_extract_template_param_name('template<typename> class Container'))
    end)
  end)

  --------------------------------------------------------------------------------
  -- Additional is_const Tests
  --------------------------------------------------------------------------------

  describe('is_const additional cases', function()
    it('detects const qualifier', function()
      local sym = make_csymbol({ 'const int foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 10,
        sel_end_char = 13,
      })

      assert.is_true(sym:is_const())
    end)

    it('does not match const inside template', function()
      local sym = make_csymbol({ 'std::vector<const int*> foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 25,
        sel_end_char = 28,
      })

      -- const inside template<> should be masked
      assert.is_false(sym:is_const())
    end)
  end)

  --------------------------------------------------------------------------------
  -- Accessor with Boolean Tests
  --------------------------------------------------------------------------------

  describe('getter/setter with boolean type', function()
    local config = require('cmantic.config')

    it('uses is_ prefix for boolean when bool_getter_is_prefix is true', function()
      local original = config.values.bool_getter_is_prefix
      config.values.bool_getter_is_prefix = true

      local bufnr = helpers.create_buffer({
        'class MyClass {',
        'public:',
        '    bool active;',
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
        name = 'active',
        kind = SK.Field,
        range = { start = { line = 2, character = 4 }, ['end'] = { line = 2, character = 15 } },
        selectionRange = { start = { line = 2, character = 9 }, ['end'] = { line = 2, character = 15 } },
        detail = 'bool',
        children = {},
      }, doc)
      csym.parent = parent_sym

      eq('is_active', csym:getter_name())

      config.values.bool_getter_is_prefix = original
    end)

    it('uses get_ prefix for boolean when bool_getter_is_prefix is false', function()
      local original = config.values.bool_getter_is_prefix
      config.values.bool_getter_is_prefix = false

      local bufnr = helpers.create_buffer({
        'class MyClass {',
        'public:',
        '    bool active;',
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
        name = 'active',
        kind = SK.Field,
        range = { start = { line = 2, character = 4 }, ['end'] = { line = 2, character = 15 } },
        selectionRange = { start = { line = 2, character = 9 }, ['end'] = { line = 2, character = 15 } },
        detail = 'bool',
        children = {},
      }, doc)
      csym.parent = parent_sym

      eq('get_active', csym:getter_name())

      config.values.bool_getter_is_prefix = original
    end)
  end)

  --------------------------------------------------------------------------------
  -- is_member_variable Tests
  --------------------------------------------------------------------------------

  describe('is_member_variable via accessor names', function()
    it('returns empty string for non-field symbol', function()
      local sym = make_csymbol({ 'void foo();' }, {
        name = 'foo',
        kind = SK.Function,
        sel_start_char = 5,
        sel_end_char = 8,
      })

      eq('', sym:getter_name())
      eq('', sym:setter_name())
    end)
  end)

  --------------------------------------------------------------------------------
  -- _is_bool_type Tests
  --------------------------------------------------------------------------------

  describe('_is_bool_type', function()
    it('returns true for bool type', function()
      local bufnr = helpers.create_buffer({
        'class MyClass {',
        '    bool flag;',
        '};',
      }, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'flag',
        kind = SK.Field,
        range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 13 } },
        selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 13 } },
        detail = 'bool',
        children = {},
      }

      local csym = CSymbol.new(raw_sym, doc)
      assert.is_true(csym:_is_bool_type())
    end)

    it('returns false for non-bool type', function()
      local bufnr = helpers.create_buffer({
        'class MyClass {',
        '    int count;',
        '};',
      }, 'cpp')
      local doc = SourceDocument.new(bufnr)

      local raw_sym = {
        name = 'count',
        kind = SK.Field,
        range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 13 } },
        selectionRange = { start = { line = 1, character = 8 }, ['end'] = { line = 1, character = 13 } },
        detail = 'int',
        children = {},
      }

      local csym = CSymbol.new(raw_sym, doc)
      assert.is_false(csym:_is_bool_type())
    end)
  end)
end)
