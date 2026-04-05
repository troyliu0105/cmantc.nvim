local helpers = require('tests.helpers')
local SourceDocument = require('cmantic.source_document')
local SourceFile = require('cmantic.source_file')
local SourceSymbol = require('cmantic.source_symbol')
local CSymbol = require('cmantic.c_symbol')
local header_source = require('cmantic.header_source')
local config = require('cmantic.config')
local add_declaration = require('cmantic.commands.add_declaration')

local function to_raw_symbol(source_sym)
  local raw_children = {}
  for _, child in ipairs(source_sym.children or {}) do
    table.insert(raw_children, to_raw_symbol(child))
  end
  return {
    name = source_sym.name,
    kind = source_sym.kind,
    range = source_sym.range,
    selectionRange = source_sym.selection_range or source_sym.selectionRange,
    children = raw_children,
    detail = source_sym.detail or '',
  }
end

describe('add_declaration execute', function()
  local orig_get_symbols
  local orig_get_matching
  local orig_get_symbol_at_position
  local saved_config
  local orig_buf

  before_each(function()
    orig_get_symbols = SourceFile.get_symbols
    orig_get_matching = header_source.get_matching
    orig_get_symbol_at_position = SourceDocument.get_symbol_at_position
    saved_config = vim.deepcopy(config.values)
    orig_buf = vim.api.nvim_win_get_buf(0)
    header_source.clear_cache()
  end)

  after_each(function()
    SourceFile.get_symbols = orig_get_symbols
    header_source.get_matching = orig_get_matching
    SourceDocument.get_symbol_at_position = orig_get_symbol_at_position
    config.values = saved_config
    vim.api.nvim_win_set_buf(0, orig_buf)
    header_source.clear_cache()
  end)

  it('notifies error when no symbol at cursor', function()
    local bufnr = helpers.create_buffer({ '' }, 'cpp')
    vim.api.nvim_win_set_buf(0, bufnr)
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('No symbol found') then
        notified = true
      end
    end
    
    SourceFile.get_symbols = function() return {} end
    
    add_declaration.execute()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies error when symbol is not a function definition', function()
    local bufnr = helpers.create_buffer({ 'void test();' }, 'cpp')
    vim.api.nvim_win_set_buf(0, bufnr)
    
    local func_sym = SourceSymbol.new({
      name = 'test',
      kind = 12,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 12 } },
      selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 9 } },
      children = {},
    }, vim.uri_from_bufnr(bufnr), nil)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(func_sym) } end
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('function definition') then
        notified = true
      end
    end
    
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    add_declaration.execute()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies info when function is already defined inside class', function()
    local bufnr = helpers.create_buffer({
      'class Test {',
      'public:',
      '  void method() { int x = 5; }',
      '};',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local method_sym = SourceSymbol.new({
      name = 'method',
      kind = 6,
      range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 32 } },
      selectionRange = { start = { line = 2, character = 8 }, ['end'] = { line = 2, character = 14 } },
      children = {},
    }, uri, nil)
    
    local class_sym = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 3, character = 2 } },
      selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 10 } },
      children = { to_raw_symbol(method_sym) },
    }, uri, nil)
    
    local wrapped_method = class_sym.children[1]
    wrapped_method.parent = class_sym
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('already defined inside class') then
        notified = true
      end
    end
    
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 3, 8 })
    add_declaration.execute()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies error when no matching header file found', function()
    local bufnr = helpers.create_buffer({ 'void test() {}' }, 'cpp')
    vim.api.nvim_win_set_buf(0, bufnr)
    
    local func_sym = SourceSymbol.new({
      name = 'test',
      kind = 12,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } },
      selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 9 } },
      children = {},
    }, vim.uri_from_bufnr(bufnr), nil)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(func_sym) } end
    header_source.get_matching = function() return nil end
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('No matching header file') then
        notified = true
      end
    end
    
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    add_declaration.execute()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe('add_declaration _insert_declaration', function()
  local orig_get_symbols
  local orig_get_matching
  local saved_config
  local orig_buf

  before_each(function()
    orig_get_symbols = SourceFile.get_symbols
    orig_get_matching = header_source.get_matching
    saved_config = vim.deepcopy(config.values)
    orig_buf = vim.api.nvim_win_get_buf(0)
    header_source.clear_cache()
  end)

  after_each(function()
    SourceFile.get_symbols = orig_get_symbols
    header_source.get_matching = orig_get_matching
    config.values = saved_config
    vim.api.nvim_win_set_buf(0, orig_buf)
    header_source.clear_cache()
  end)

  it('inserts declaration for free function definition', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'void freeFunc() {',
      '  int x = 5;',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'class_method_prefix.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'class_method_prefix.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'freeFunc',
      kind = 12,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 2, character = 5 }, ['end'] = { line = 2, character = 13 } },
      children = {},
    }, source_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(func_sym) }
      elseif self.uri == header_uri then
        return {}
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    local source_doc = SourceDocument.new(source_buf)
    local target_doc = SourceDocument.new(header_buf)
    local csymbol = CSymbol.new(func_sym, source_doc)
    
    add_declaration._insert_declaration(csymbol, source_doc, target_doc, nil, nil)
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_declaration = false
    for _, line in ipairs(header_lines) do
      if line:match('void freeFunc%(') and line:match(';') then
        has_declaration = true
        break
      end
    end
    assert.True(has_declaration)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('inserts declaration with semicolon and no body', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'int add(int a, int b) {',
      '  return a + b;',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'class_public.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'class_public.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'add',
      kind = 12,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 2, character = 4 }, ['end'] = { line = 2, character = 7 } },
      children = {},
    }, source_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(func_sym) }
      elseif self.uri == header_uri then
        return {}
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    local source_doc = SourceDocument.new(source_buf)
    local target_doc = SourceDocument.new(header_buf)
    local csymbol = CSymbol.new(func_sym, source_doc)
    
    add_declaration._insert_declaration(csymbol, source_doc, target_doc, nil, nil)
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_correct_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('int add%(') and line:match(';') and not line:match('{}') then
        has_correct_decl = true
        break
      end
    end
    assert.True(has_correct_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)
end)

describe('add_declaration with class methods', function()
  local orig_get_symbols
  local orig_get_matching
  local orig_get_symbol_at_position
  local orig_csymbol_new
  local saved_config
  local orig_buf

  before_each(function()
    orig_get_symbols = SourceFile.get_symbols
    orig_get_matching = header_source.get_matching
    orig_get_symbol_at_position = SourceDocument.get_symbol_at_position
    orig_csymbol_new = CSymbol.new
    saved_config = vim.deepcopy(config.values)
    orig_buf = vim.api.nvim_win_get_buf(0)
    header_source.clear_cache()
  end)

  after_each(function()
    SourceFile.get_symbols = orig_get_symbols
    header_source.get_matching = orig_get_matching
    SourceDocument.get_symbol_at_position = orig_get_symbol_at_position
    CSymbol.new = orig_csymbol_new
    config.values = saved_config
    vim.api.nvim_win_set_buf(0, orig_buf)
    header_source.clear_cache()
  end)

  it('handles method definition with Class:: prefix', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'void MyClass::method() {',
      '  int x = 5;',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'class_protected.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class MyClass {',
      'public:',
      '};',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'class_protected.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local class_sym_header = SourceSymbol.new({
      name = 'MyClass',
      kind = 5,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 5, character = 2 } },
      selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 13 } },
      children = {},
    }, header_uri, nil)
    
    local class_sym_source = SourceSymbol.new({
      name = 'MyClass',
      kind = 5,
      range = { start = { line = 100, character = 0 }, ['end'] = { line = 200, character = 2 } },
      selectionRange = { start = { line = 100, character = 6 }, ['end'] = { line = 100, character = 13 } },
      children = {},
    }, source_uri, nil)
    
    local method_sym = SourceSymbol.new({
      name = 'method',
      kind = 6,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 2, character = 16 }, ['end'] = { line = 2, character = 22 } },
      children = {},
    }, source_uri, class_sym_source)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(method_sym) }
      elseif self.uri == header_uri then
        return { to_raw_symbol(class_sym_header) }
      end
      return {}
    end
    SourceDocument.get_symbol_at_position = function(self, position)
      if self.uri == source_uri then
        return method_sym
      end
      return orig_get_symbol_at_position(self, position)
    end
    CSymbol.new = function(symbol, doc)
      local csymbol = orig_csymbol_new(symbol, doc)
      if doc.uri == source_uri and csymbol.name == 'method' then
        csymbol.parent = nil
        csymbol.scopes = function() return { class_sym_source } end
      elseif doc.uri == header_uri and csymbol.name == 'MyClass' then
        csymbol.find_position_for_new_member_function = function(self, access)
          return require('cmantic.proposed_position').new({ line = 5, character = 0 }, {
            indent = 1,
            blank_lines_before = 1,
            blank_lines_after = 1,
          })
        end
      end
      return csymbol
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    vim.api.nvim_win_set_buf(0, source_buf)
    vim.api.nvim_win_set_cursor(0, { 3, 16 })
    
    vim.ui.select = function(items, opts, on_choice)
      on_choice('public')
    end
    
    add_declaration.execute()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_method_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('void method%(') and line:match(';') then
        has_method_decl = true
        break
      end
    end
    assert.True(has_method_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('inserts declaration in public section when selected', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'int Test::getValue() {',
      '  return value;',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'class_private.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class Test {',
      'public:',
      '  Test();',
      '',
      'private:',
      '  int value;',
      '};',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'class_private.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local class_sym_header = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 9, character = 2 } },
      selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 10 } },
      children = {
        {
          name = 'Test',
          kind = 9,
          range = { start = { line = 5, character = 2 }, ['end'] = { line = 5, character = 10 } },
          selectionRange = { start = { line = 5, character = 2 }, ['end'] = { line = 5, character = 6 } },
          children = {},
        },
        {
          name = 'value',
          kind = 8,
          range = { start = { line = 8, character = 2 }, ['end'] = { line = 8, character = 12 } },
          selectionRange = { start = { line = 8, character = 6 }, ['end'] = { line = 8, character = 11 } },
          children = {},
        },
      },
    }, header_uri, nil)
    
    local class_sym_source = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 100, character = 0 }, ['end'] = { line = 200, character = 2 } },
      selectionRange = { start = { line = 100, character = 6 }, ['end'] = { line = 100, character = 10 } },
      children = {},
    }, source_uri, nil)
    
    local method_sym = SourceSymbol.new({
      name = 'getValue',
      kind = 6,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 2, character = 10 }, ['end'] = { line = 2, character = 18 } },
      children = {},
    }, source_uri, class_sym_source)
    
    local raw_class = to_raw_symbol(class_sym_header)
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(method_sym) }
      elseif self.uri == header_uri then
        return { raw_class }
      end
      return {}
    end
    SourceDocument.get_symbol_at_position = function(self, position)
      if self.uri == source_uri then
        return method_sym
      end
      return orig_get_symbol_at_position(self, position)
    end
    CSymbol.new = function(symbol, doc)
      local csymbol = orig_csymbol_new(symbol, doc)
      if doc.uri == source_uri and csymbol.name == 'getValue' then
        csymbol.parent = nil
        csymbol.scopes = function() return { class_sym_source } end
      elseif doc.uri == header_uri and csymbol.name == 'Test' then
        csymbol.find_position_for_new_member_function = function(self, access)
          return require('cmantic.proposed_position').new({ line = 6, character = 0 }, {
            indent = 1,
            blank_lines_before = 1,
            blank_lines_after = 1,
          })
        end
      end
      return csymbol
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    vim.api.nvim_win_set_buf(0, source_buf)
    vim.api.nvim_win_set_cursor(0, { 3, 10 })
    
    vim.ui.select = function(items, opts, on_choice)
      on_choice('public')
    end
    
    add_declaration.execute()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local found_in_public = false
    local found_decl_line = nil
    for i, line in ipairs(header_lines) do
      if line:match('int getValue%(') then
        found_decl_line = i
        break
      end
    end
    
    if found_decl_line then
      for i = found_decl_line - 1, 1, -1 do
        if header_lines[i]:match('public:') then
          found_in_public = true
          break
        elseif header_lines[i]:match('private:') or header_lines[i]:match('protected:') then
          break
        end
      end
    end
    
    assert.True(found_in_public or found_decl_line ~= nil)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('inserts declaration in protected section when selected', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'void Test::internalMethod() {',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'namespace_func.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class Test {',
      'public:',
      '  Test();',
      '',
      'protected:',
      '};',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'namespace_func.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local class_sym_header = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 8, character = 2 } },
      selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 10 } },
      children = {},
    }, header_uri, nil)
    
    local class_sym_source = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 100, character = 0 }, ['end'] = { line = 200, character = 2 } },
      selectionRange = { start = { line = 100, character = 6 }, ['end'] = { line = 100, character = 10 } },
      children = {},
    }, source_uri, nil)
    
    local method_sym = SourceSymbol.new({
      name = 'internalMethod',
      kind = 6,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 3, character = 1 } },
      selectionRange = { start = { line = 2, character = 11 }, ['end'] = { line = 2, character = 26 } },
      children = {},
    }, source_uri, class_sym_source)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(method_sym) }
      elseif self.uri == header_uri then
        return { to_raw_symbol(class_sym_header) }
      end
      return {}
    end
    SourceDocument.get_symbol_at_position = function(self, position)
      if self.uri == source_uri then
        return method_sym
      end
      return orig_get_symbol_at_position(self, position)
    end
    CSymbol.new = function(symbol, doc)
      local csymbol = orig_csymbol_new(symbol, doc)
      if doc.uri == source_uri and csymbol.name == 'internalMethod' then
        csymbol.parent = nil
        csymbol.scopes = function() return { class_sym_source } end
      elseif doc.uri == header_uri and csymbol.name == 'Test' then
        csymbol.find_position_for_new_member_function = function(self, access)
          return require('cmantic.proposed_position').new({ line = 8, character = 0 }, {
            indent = 1,
            blank_lines_before = 1,
            blank_lines_after = 1,
          })
        end
      end
      return csymbol
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    vim.api.nvim_win_set_buf(0, source_buf)
    vim.api.nvim_win_set_cursor(0, { 3, 11 })
    
    vim.ui.select = function(items, opts, on_choice)
      on_choice('protected')
    end
    
    add_declaration.execute()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('void internalMethod%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('inserts declaration in private section when selected', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'void Test::privateHelper() {',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'namespace_class_method.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class Test {',
      'public:',
      '  Test();',
      '',
      'private:',
      '};',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'namespace_class_method.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local class_sym_header = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 8, character = 2 } },
      selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 10 } },
      children = {},
    }, header_uri, nil)
    
    local class_sym_source = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 100, character = 0 }, ['end'] = { line = 200, character = 2 } },
      selectionRange = { start = { line = 100, character = 6 }, ['end'] = { line = 100, character = 10 } },
      children = {},
    }, source_uri, nil)
    
    local method_sym = SourceSymbol.new({
      name = 'privateHelper',
      kind = 6,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 3, character = 1 } },
      selectionRange = { start = { line = 2, character = 11 }, ['end'] = { line = 2, character = 24 } },
      children = {},
    }, source_uri, class_sym_source)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(method_sym) }
      elseif self.uri == header_uri then
        return { to_raw_symbol(class_sym_header) }
      end
      return {}
    end
    SourceDocument.get_symbol_at_position = function(self, position)
      if self.uri == source_uri then
        return method_sym
      end
      return orig_get_symbol_at_position(self, position)
    end
    CSymbol.new = function(symbol, doc)
      local csymbol = orig_csymbol_new(symbol, doc)
      if doc.uri == source_uri and csymbol.name == 'privateHelper' then
        csymbol.parent = nil
        csymbol.scopes = function() return { class_sym_source } end
      elseif doc.uri == header_uri and csymbol.name == 'Test' then
        csymbol.find_position_for_new_member_function = function(self, access)
          return require('cmantic.proposed_position').new({ line = 8, character = 0 }, {
            indent = 1,
            blank_lines_before = 1,
            blank_lines_after = 1,
          })
        end
      end
      return csymbol
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    vim.api.nvim_win_set_buf(0, source_buf)
    vim.api.nvim_win_set_cursor(0, { 3, 11 })
    
    vim.ui.select = function(items, opts, on_choice)
      on_choice('private')
    end
    
    add_declaration.execute()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('void privateHelper%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)
end)

describe('add_declaration with namespaces', function()
  local orig_get_symbols
  local orig_get_matching
  local orig_get_symbol_at_position
  local orig_csymbol_new
  local saved_config
  local orig_buf

  before_each(function()
    orig_get_symbols = SourceFile.get_symbols
    orig_get_matching = header_source.get_matching
    orig_get_symbol_at_position = SourceDocument.get_symbol_at_position
    orig_csymbol_new = CSymbol.new
    saved_config = vim.deepcopy(config.values)
    orig_buf = vim.api.nvim_win_get_buf(0)
    header_source.clear_cache()
  end)

  after_each(function()
    SourceFile.get_symbols = orig_get_symbols
    header_source.get_matching = orig_get_matching
    SourceDocument.get_symbol_at_position = orig_get_symbol_at_position
    CSymbol.new = orig_csymbol_new
    config.values = saved_config
    vim.api.nvim_win_set_buf(0, orig_buf)
    header_source.clear_cache()
  end)

  it('handles function in namespace', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'namespace MyNS {',
      'void namespacedFunc() {',
      '}',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'ctor_decl.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'namespace MyNS {',
      '}',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'ctor_decl.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'namespacedFunc',
      kind = 12,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 3, character = 5 }, ['end'] = { line = 3, character = 19 } },
      children = {},
    }, source_uri, nil)

    local ns_sym_source = SourceSymbol.new({
      name = 'MyNS',
      kind = 3,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 5, character = 1 } },
      selectionRange = { start = { line = 2, character = 10 }, ['end'] = { line = 2, character = 14 } },
      children = { to_raw_symbol(func_sym) },
    }, source_uri, nil)
    func_sym.parent = ns_sym_source
    
    local ns_sym_header = SourceSymbol.new({
      name = 'MyNS',
      kind = 3,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 3, character = 10 }, ['end'] = { line = 3, character = 14 } },
      children = {},
    }, header_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(ns_sym_source) }
      elseif self.uri == header_uri then
        return { to_raw_symbol(ns_sym_header) }
      end
      return {}
    end
    SourceDocument.get_symbol_at_position = function(self, position)
      if self.uri == source_uri then
        return func_sym
      end
      return orig_get_symbol_at_position(self, position)
    end
    CSymbol.new = function(symbol, doc)
      local csymbol = orig_csymbol_new(symbol, doc)
      if doc.uri == source_uri and csymbol.name == 'namespacedFunc' then
        csymbol.parent = ns_sym_source
        csymbol.scopes = function() return { ns_sym_source } end
      end
      return csymbol
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    vim.api.nvim_win_set_buf(0, source_buf)
    vim.api.nvim_win_set_cursor(0, { 4, 5 })
    
    add_declaration.execute()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('void namespacedFunc%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('handles method in nested namespace and class', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'namespace Outer {',
      'namespace Inner {',
      'void MyClass::method() {',
      '}',
      '}',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'dtor_decl.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'namespace Outer {',
      'namespace Inner {',
      'class MyClass {',
      'public:',
      '};',
      '}',
      '}',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'dtor_decl.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local class_sym_header = SourceSymbol.new({
      name = 'MyClass',
      kind = 5,
      range = { start = { line = 5, character = 0 }, ['end'] = { line = 7, character = 2 } },
      selectionRange = { start = { line = 5, character = 6 }, ['end'] = { line = 5, character = 13 } },
      children = {},
    }, header_uri, nil)

    local inner_ns_header = SourceSymbol.new({
      name = 'Inner',
      kind = 3,
      range = { start = { line = 4, character = 0 }, ['end'] = { line = 8, character = 1 } },
      selectionRange = { start = { line = 4, character = 10 }, ['end'] = { line = 4, character = 15 } },
      children = { to_raw_symbol(class_sym_header) },
    }, header_uri, nil)

    local outer_ns_header = SourceSymbol.new({
      name = 'Outer',
      kind = 3,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 9, character = 1 } },
      selectionRange = { start = { line = 3, character = 10 }, ['end'] = { line = 3, character = 15 } },
      children = { to_raw_symbol(inner_ns_header) },
    }, header_uri, nil)
    
    local method_sym = SourceSymbol.new({
      name = 'method',
      kind = 6,
      range = { start = { line = 4, character = 0 }, ['end'] = { line = 5, character = 1 } },
      selectionRange = { start = { line = 4, character = 18 }, ['end'] = { line = 4, character = 24 } },
      children = {},
    }, source_uri, nil)

    local class_sym_source = SourceSymbol.new({
      name = 'MyClass',
      kind = 5,
      range = { start = { line = 100, character = 0 }, ['end'] = { line = 200, character = 2 } },
      selectionRange = { start = { line = 100, character = 6 }, ['end'] = { line = 100, character = 13 } },
      children = { to_raw_symbol(method_sym) },
    }, source_uri, nil)

    local inner_ns_source = SourceSymbol.new({
      name = 'Inner',
      kind = 3,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 6, character = 1 } },
      selectionRange = { start = { line = 3, character = 10 }, ['end'] = { line = 3, character = 15 } },
      children = { to_raw_symbol(class_sym_source) },
    }, source_uri, nil)

    local outer_ns_source = SourceSymbol.new({
      name = 'Outer',
      kind = 3,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 7, character = 1 } },
      selectionRange = { start = { line = 2, character = 10 }, ['end'] = { line = 2, character = 15 } },
      children = { to_raw_symbol(inner_ns_source) },
    }, source_uri, nil)
    method_sym.parent = class_sym_source
    class_sym_source.parent = inner_ns_source
    inner_ns_source.parent = outer_ns_source
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(outer_ns_source) }
      elseif self.uri == header_uri then
        return { to_raw_symbol(outer_ns_header) }
      end
      return {}
    end
    SourceDocument.get_symbol_at_position = function(self, position)
      if self.uri == source_uri then
        return method_sym
      end
      return orig_get_symbol_at_position(self, position)
    end
    CSymbol.new = function(symbol, doc)
      local csymbol = orig_csymbol_new(symbol, doc)
      if doc.uri == source_uri and csymbol.name == 'method' then
        csymbol.parent = inner_ns_source
        csymbol.scopes = function() return { outer_ns_source, inner_ns_source, class_sym_source } end
      elseif doc.uri == header_uri and csymbol.name == 'MyClass' then
        csymbol.find_position_for_new_member_function = function(self, access)
          return require('cmantic.proposed_position').new({ line = 7, character = 0 }, {
            indent = 1,
            blank_lines_before = 1,
            blank_lines_after = 1,
          })
        end
      end
      return csymbol
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    vim.api.nvim_win_set_buf(0, source_buf)
    vim.api.nvim_win_set_cursor(0, { 5, 18 })
    
    vim.ui.select = function(items, opts, on_choice)
      on_choice('public')
    end
    
    add_declaration.execute()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('void method%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)
end)

describe('add_declaration additional coverage', function()
  local orig_get_symbols
  local orig_get_matching
  local orig_get_symbol_at_position
  local orig_csymbol_new
  local saved_config
  local orig_buf

  before_each(function()
    orig_get_symbols = SourceFile.get_symbols
    orig_get_matching = header_source.get_matching
    orig_get_symbol_at_position = SourceDocument.get_symbol_at_position
    orig_csymbol_new = CSymbol.new
    saved_config = vim.deepcopy(config.values)
    orig_buf = vim.api.nvim_win_get_buf(0)
    header_source.clear_cache()
  end)

  after_each(function()
    SourceFile.get_symbols = orig_get_symbols
    header_source.get_matching = orig_get_matching
    SourceDocument.get_symbol_at_position = orig_get_symbol_at_position
    CSymbol.new = orig_csymbol_new
    config.values = saved_config
    vim.api.nvim_win_set_buf(0, orig_buf)
    header_source.clear_cache()
  end)

  it('handles static function definition', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'static void helper() {',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'const_method_decl.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'const_method_decl.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'helper',
      kind = 12,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 3, character = 1 } },
      selectionRange = { start = { line = 2, character = 13 }, ['end'] = { line = 2, character = 19 } },
      children = {},
    }, source_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(func_sym) }
      elseif self.uri == header_uri then
        return {}
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    local source_doc = SourceDocument.new(source_buf)
    local target_doc = SourceDocument.new(header_buf)
    local csymbol = CSymbol.new(func_sym, source_doc)
    
    add_declaration._insert_declaration(csymbol, source_doc, target_doc, nil, nil)
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('void helper%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('handles inline function definition', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'inline int square(int x) {',
      '  return x * x;',
      '}',
    }, 'cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '#endif',
    }, 'cpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'square',
      kind = 12,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 2, character = 12 }, ['end'] = { line = 2, character = 18 } },
      children = {},
    }, source_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(func_sym) }
      elseif self.uri == header_uri then
        return {}
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    local source_doc = SourceDocument.new(source_buf)
    local target_doc = SourceDocument.new(header_buf)
    local csymbol = CSymbol.new(func_sym, source_doc)
    
    add_declaration._insert_declaration(csymbol, source_doc, target_doc, nil, nil)
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('int square%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('handles constexpr function definition', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'constexpr int power(int base, int exp) {',
      '  return exp == 0 ? 1 : base * power(base, exp - 1);',
      '}',
    }, 'cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '#endif',
    }, 'cpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'power',
      kind = 12,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 2, character = 15 }, ['end'] = { line = 2, character = 20 } },
      children = {},
    }, source_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(func_sym) }
      elseif self.uri == header_uri then
        return {}
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    local source_doc = SourceDocument.new(source_buf)
    local target_doc = SourceDocument.new(header_buf)
    local csymbol = CSymbol.new(func_sym, source_doc)
    
    add_declaration._insert_declaration(csymbol, source_doc, target_doc, nil, nil)
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('int power%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('handles function returning pointer', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'int* createArray(int size) {',
      '  return new int[size];',
      '}',
    }, 'cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '#endif',
    }, 'cpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'createArray',
      kind = 12,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 2, character = 5 }, ['end'] = { line = 2, character = 16 } },
      children = {},
    }, source_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(func_sym) }
      elseif self.uri == header_uri then
        return {}
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    local source_doc = SourceDocument.new(source_buf)
    local target_doc = SourceDocument.new(header_buf)
    local csymbol = CSymbol.new(func_sym, source_doc)
    
    add_declaration._insert_declaration(csymbol, source_doc, target_doc, nil, nil)
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('int%* createArray%(') or line:match('int %*createArray%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('handles function returning reference', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'int& getRef() {',
      '  static int x = 0;',
      '  return x;',
      '}',
    }, 'cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '#endif',
    }, 'cpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'getRef',
      kind = 12,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 5, character = 1 } },
      selectionRange = { start = { line = 2, character = 5 }, ['end'] = { line = 2, character = 11 } },
      children = {},
    }, source_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(func_sym) }
      elseif self.uri == header_uri then
        return {}
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    local source_doc = SourceDocument.new(source_buf)
    local target_doc = SourceDocument.new(header_buf)
    local csymbol = CSymbol.new(func_sym, source_doc)
    
    add_declaration._insert_declaration(csymbol, source_doc, target_doc, nil, nil)
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('int& getRef%(') or line:match('int &getRef%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('handles constructor definition', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'Test::Test(int val) : value(val) {',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'add_decl_ctor.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class Test {',
      'public:',
      '};',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'add_decl_ctor.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local class_sym_header = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 5, character = 2 } },
      selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 10 } },
      children = {},
    }, header_uri, nil)
    
    local class_sym_source = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 100, character = 0 }, ['end'] = { line = 200, character = 2 } },
      selectionRange = { start = { line = 100, character = 6 }, ['end'] = { line = 100, character = 10 } },
      children = {},
    }, source_uri, nil)
    
    local ctor_sym = SourceSymbol.new({
      name = 'Test',
      kind = 9,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 3, character = 1 } },
      selectionRange = { start = { line = 2, character = 6 }, ['end'] = { line = 2, character = 10 } },
      children = {},
    }, source_uri, class_sym_source)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(ctor_sym) }
      elseif self.uri == header_uri then
        return { to_raw_symbol(class_sym_header) }
      end
      return {}
    end
    SourceDocument.get_symbol_at_position = function(self, position)
      if self.uri == source_uri then
        return ctor_sym
      end
      return orig_get_symbol_at_position(self, position)
    end
    CSymbol.new = function(symbol, doc)
      local csymbol = orig_csymbol_new(symbol, doc)
      if doc.uri == source_uri and csymbol.name == 'Test' then
        csymbol.parent = nil
        csymbol.scopes = function() return { class_sym_source } end
      elseif doc.uri == header_uri and csymbol.name == 'Test' then
        csymbol.find_position_for_new_member_function = function(self, access)
          return require('cmantic.proposed_position').new({ line = 5, character = 0 }, {
            indent = 1,
            blank_lines_before = 1,
            blank_lines_after = 1,
          })
        end
      end
      return csymbol
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    vim.api.nvim_win_set_buf(0, source_buf)
    vim.api.nvim_win_set_cursor(0, { 3, 6 })
    
    vim.ui.select = function(items, opts, on_choice)
      on_choice('public')
    end
    
    add_declaration.execute()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_ctor = false
    for _, line in ipairs(header_lines) do
      if line:match('Test%(') and line:match('int val') then
        has_ctor = true
        break
      end
    end
    assert.True(has_ctor)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('handles destructor definition', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'Test::~Test() {',
      '  cleanup();',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'add_decl_dtor.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class Test {',
      'public:',
      '};',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'add_decl_dtor.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local class_sym_header = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 5, character = 2 } },
      selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 10 } },
      children = {},
    }, header_uri, nil)
    
    local class_sym_source = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 100, character = 0 }, ['end'] = { line = 200, character = 2 } },
      selectionRange = { start = { line = 100, character = 6 }, ['end'] = { line = 100, character = 10 } },
      children = {},
    }, source_uri, nil)
    
    local dtor_sym = SourceSymbol.new({
      name = '~Test',
      kind = 6,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 2, character = 6 }, ['end'] = { line = 2, character = 11 } },
      children = {},
    }, source_uri, class_sym_source)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(dtor_sym) }
      elseif self.uri == header_uri then
        return { to_raw_symbol(class_sym_header) }
      end
      return {}
    end
    SourceDocument.get_symbol_at_position = function(self, position)
      if self.uri == source_uri then
        return dtor_sym
      end
      return orig_get_symbol_at_position(self, position)
    end
    CSymbol.new = function(symbol, doc)
      local csymbol = orig_csymbol_new(symbol, doc)
      if doc.uri == source_uri and csymbol.name == '~Test' then
        csymbol.parent = nil
        csymbol.scopes = function() return { class_sym_source } end
      elseif doc.uri == header_uri and csymbol.name == 'Test' then
        csymbol.find_position_for_new_member_function = function(self, access)
          return require('cmantic.proposed_position').new({ line = 5, character = 0 }, {
            indent = 1,
            blank_lines_before = 1,
            blank_lines_after = 1,
          })
        end
      end
      return csymbol
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    vim.api.nvim_win_set_buf(0, source_buf)
    vim.api.nvim_win_set_cursor(0, { 3, 6 })
    
    vim.ui.select = function(items, opts, on_choice)
      on_choice('public')
    end
    
    add_declaration.execute()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_dtor = false
    for _, line in ipairs(header_lines) do
      if line:match('~Test%(') then
        has_dtor = true
        break
      end
    end
    assert.True(has_dtor)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('handles function with default parameters', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'void greet(const std::string& name, int times) {',
      '  for (int i = 0; i < times; ++i) {',
      '    std::cout << name << std::endl;',
      '  }',
      '}',
    }, 'cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '#include <string>',
      '',
      '#endif',
    }, 'cpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'greet',
      kind = 12,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 6, character = 1 } },
      selectionRange = { start = { line = 2, character = 5 }, ['end'] = { line = 2, character = 10 } },
      children = {},
    }, source_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(func_sym) }
      elseif self.uri == header_uri then
        return {}
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    local source_doc = SourceDocument.new(source_buf)
    local target_doc = SourceDocument.new(header_buf)
    local csymbol = CSymbol.new(func_sym, source_doc)
    
    add_declaration._insert_declaration(csymbol, source_doc, target_doc, nil, nil)
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_decl = false
    for _, line in ipairs(header_lines) do
      if line:match('void greet%(') then
        has_decl = true
        break
      end
    end
    assert.True(has_decl)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)

  it('handles const member function', function()
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
      '',
      'int Test::getValue() const {',
      '  return value;',
      '}',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'add_decl_const.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class Test {',
      'public:',
      'private:',
      '  int value;',
      '};',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'add_decl_const.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local class_sym_header = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 7, character = 2 } },
      selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 10 } },
      children = {},
    }, header_uri, nil)
    
    local class_sym_source = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 100, character = 0 }, ['end'] = { line = 200, character = 2 } },
      selectionRange = { start = { line = 100, character = 6 }, ['end'] = { line = 100, character = 10 } },
      children = {},
    }, source_uri, nil)
    
    local method_sym = SourceSymbol.new({
      name = 'getValue',
      kind = 6,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 4, character = 1 } },
      selectionRange = { start = { line = 2, character = 10 }, ['end'] = { line = 2, character = 18 } },
      children = {},
    }, source_uri, class_sym_source)
    
    SourceFile.get_symbols = function(self)
      if self.uri == source_uri then
        return { to_raw_symbol(method_sym) }
      elseif self.uri == header_uri then
        return { to_raw_symbol(class_sym_header) }
      end
      return {}
    end
    SourceDocument.get_symbol_at_position = function(self, position)
      if self.uri == source_uri then
        return method_sym
      end
      return orig_get_symbol_at_position(self, position)
    end
    CSymbol.new = function(symbol, doc)
      local csymbol = orig_csymbol_new(symbol, doc)
      if doc.uri == source_uri and csymbol.name == 'getValue' then
        csymbol.parent = nil
        csymbol.scopes = function() return { class_sym_source } end
      elseif doc.uri == header_uri and csymbol.name == 'Test' then
        csymbol.find_position_for_new_member_function = function(self, access)
          return require('cmantic.proposed_position').new({ line = 5, character = 0 }, {
            indent = 1,
            blank_lines_before = 1,
            blank_lines_after = 1,
          })
        end
      end
      return csymbol
    end
    
    header_source.get_matching = function(uri)
      if uri == source_uri then return header_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    
    vim.api.nvim_win_set_buf(0, source_buf)
    vim.api.nvim_win_set_cursor(0, { 3, 10 })
    
    vim.ui.select = function(items, opts, on_choice)
      on_choice('public')
    end
    
    add_declaration.execute()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_const_method = false
    for _, line in ipairs(header_lines) do
      if line:match('int getValue%(') and line:match('const') then
        has_const_method = true
        break
      end
    end
    assert.True(has_const_method)
    
    vim.api.nvim_buf_delete(source_buf, { force = true })
    vim.api.nvim_buf_delete(header_buf, { force = true })
  end)
end)
