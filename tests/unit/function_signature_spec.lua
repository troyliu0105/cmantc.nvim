local FunctionSignature = require('cmantic.function_signature')
local SourceDocument = require('cmantic.source_document')
local SourceSymbol = require('cmantic.source_symbol')
local CSymbol = require('cmantic.c_symbol')
local SK = SourceSymbol.SymbolKind
local eq = assert.are.same

describe('function_signature', function()
  describe('new', function()
    it('parses simple function', function()
      local sig = FunctionSignature.new('void foo(int x, int y);')
      eq('void', sig.return_type)
      eq('foo', sig.name)
      eq('int x, int y', sig.parameters)
      eq(';', sig.trailing)
    end)

    it('parses function with no parameters', function()
      local sig = FunctionSignature.new('int bar();')
      eq('int', sig.return_type)
      eq('bar', sig.name)
      eq('', sig.parameters)
    end)

    it('parses const member function', function()
      local sig = FunctionSignature.new('int getValue() const;')
      eq('int', sig.return_type)
      eq('getValue', sig.name)
      eq('const;', sig.trailing)
    end)

    it('parses function with scope resolution', function()
      local sig = FunctionSignature.new('void MyClass::method(int x);')
      eq('void', sig.return_type)
      eq('method', sig.name)
      eq('int x', sig.parameters)
    end)

    it('parses function with default values', function()
      local sig = FunctionSignature.new('void set(int x = 5, const std::string& s = "hello");')
      eq('void', sig.return_type)
      eq('set', sig.name)
    end)

    it('parses template function', function()
      local sig = FunctionSignature.new('T max_val<T>(T a, T b);')
      eq('T', sig.return_type)
    end)

    it('handles empty input', function()
      local sig = FunctionSignature.new('')
      eq('', sig.return_type)
      eq('', sig.name)
      eq('', sig.parameters)
    end)

    it('handles nil input', function()
      local sig = FunctionSignature.new(nil)
      eq('', sig.return_type)
      eq('', sig.name)
    end)
  end)

  describe('from_symbol', function()
    it('creates signature from CSymbol range text', function()
      local buf = vim.api.nvim_create_buf(false, true)
      local line = 'int sum(int x, int y);'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
      local doc = SourceDocument.new(buf)
      local range = {
        start = { line = 0, character = 0 },
        ['end'] = { line = 0, character = #line },
      }
      local raw = {
        name = 'sum',
        kind = SK.Function,
        range = range,
        selectionRange = {
          start = { line = 0, character = 4 },
          ['end'] = { line = 0, character = 7 },
        },
      }
      local csymbol = CSymbol.new(raw, doc)
      local sig = FunctionSignature.from_symbol(csymbol, doc)
      eq('sum', sig.name)
      eq('int', sig.return_type)
      eq('int x, int y', sig.parameters)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('handles function with no parameters', function()
      local buf = vim.api.nvim_create_buf(false, true)
      local line = 'void empty_func();'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
      local doc = SourceDocument.new(buf)
      local range = {
        start = { line = 0, character = 0 },
        ['end'] = { line = 0, character = #line },
      }
      local raw = {
        name = 'empty_func',
        kind = SK.Function,
        range = range,
        selectionRange = {
          start = { line = 0, character = 5 },
          ['end'] = { line = 0, character = 16 },
        },
      }
      local csymbol = CSymbol.new(raw, doc)
      local sig = FunctionSignature.from_symbol(csymbol, doc)
      eq('empty_func', sig.name)
      eq('void', sig.return_type)
      eq('', sig.parameters)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it('handles function with const modifier', function()
      local buf = vim.api.nvim_create_buf(false, true)
      local line = 'int get_value() const;'
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
      local doc = SourceDocument.new(buf)
      local range = {
        start = { line = 0, character = 0 },
        ['end'] = { line = 0, character = #line },
      }
      local raw = {
        name = 'get_value',
        kind = SK.Method,
        range = range,
        selectionRange = {
          start = { line = 0, character = 4 },
          ['end'] = { line = 0, character = 13 },
        },
      }
      local csymbol = CSymbol.new(raw, doc)
      local sig = FunctionSignature.from_symbol(csymbol, doc)
      eq('get_value', sig.name)
      eq('int', sig.return_type)
      eq('', sig.parameters)
      eq('const;', sig.trailing)
      vim.api.nvim_buf_delete(buf, { force = true })
    end)
  end)

  describe('equals', function()
    it('same signatures are equal', function()
      local a = FunctionSignature.new('void foo(int x);')
      local b = FunctionSignature.new('void foo(int x);')
      assert.is_true(a:equals(b))
    end)

    it('different names are not equal', function()
      local a = FunctionSignature.new('void foo(int x);')
      local b = FunctionSignature.new('void bar(int x);')
      assert.is_false(a:equals(b))
    end)

    it('different return types are not equal', function()
      local a = FunctionSignature.new('void foo(int x);')
      local b = FunctionSignature.new('int foo(int x);')
      assert.is_false(a:equals(b))
    end)

    it('different parameters are not equal', function()
      local a = FunctionSignature.new('void foo(int x);')
      local b = FunctionSignature.new('void foo(int y);')
      assert.is_false(a:equals(b))
    end)

    it('ignores default values in comparison', function()
      local a = FunctionSignature.new('void foo(int x = 5);')
      local b = FunctionSignature.new('void foo(int x = 10);')
      assert.is_true(a:equals(b))
    end)

    it('nil is not equal', function()
      local a = FunctionSignature.new('void foo();')
      assert.is_false(a:equals(nil))
    end)
  end)
end)
