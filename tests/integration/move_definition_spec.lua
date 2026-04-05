local helpers = require('tests.helpers')
local SourceDocument = require('cmantic.source_document')
local SourceFile = require('cmantic.source_file')
local SourceSymbol = require('cmantic.source_symbol')
local CSymbol = require('cmantic.c_symbol')
local header_source = require('cmantic.header_source')
local config = require('cmantic.config')
local move_definition = require('cmantic.commands.move_definition')

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

describe('move_definition execute_to_source', function()
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
    
    move_definition.execute_to_source()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies error when symbol is not a function', function()
    local bufnr = helpers.create_buffer({ 'int x = 5;' }, 'cpp')
    vim.api.nvim_win_set_buf(0, bufnr)
    
    local var_sym = SourceSymbol.new({
      name = 'x',
      kind = 13,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 9 } },
      selectionRange = { start = { line = 0, character = 4 }, ['end'] = { line = 0, character = 5 } },
      children = {},
    }, vim.uri_from_bufnr(bufnr), nil)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(var_sym) } end
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('not a function') then
        notified = true
      end
    end
    
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    move_definition.execute_to_source()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies error when symbol is not a definition', function()
    local bufnr = helpers.create_buffer({ 'void test();' }, 'h')
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
      if msg:match('not a function definition') then
        notified = true
      end
    end
    
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    move_definition.execute_to_source()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies error when not in header file', function()
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
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('Can only move definition from header') then
        notified = true
      end
    end
    
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    move_definition.execute_to_source()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies error when no matching source file found', function()
    local bufnr = helpers.create_buffer({ 'void test() {}' }, 'h')
    vim.api.nvim_buf_set_name(bufnr, 'test_nosrc.h')
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
      if msg:match('No matching source file') then
        notified = true
      end
    end
    
    vim.api.nvim_win_set_cursor(0, { 1, 5 })
    move_definition.execute_to_source()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('moves free function definition from header to source', function()
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'void freeFunc();',
      'void freeFunc() {}',
      '',
      '#endif',
    }, 'c')
    vim.api.nvim_buf_set_name(header_buf, 'test_free.h')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
    }, 'c')
    vim.api.nvim_buf_set_name(source_buf, 'test_free.c')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local decl_sym = SourceSymbol.new({
      name = 'freeFunc',
      kind = 12,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 3, character = 16 } },
      selectionRange = { start = { line = 3, character = 5 }, ['end'] = { line = 3, character = 13 } },
      children = {},
    }, header_uri, nil)
    
    local func_sym = SourceSymbol.new({
      name = 'freeFunc',
      kind = 12,
      range = { start = { line = 4, character = 0 }, ['end'] = { line = 4, character = 18 } },
      selectionRange = { start = { line = 4, character = 5 }, ['end'] = { line = 4, character = 13 } },
      children = {},
    }, header_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == header_uri then
        return { to_raw_symbol(decl_sym), to_raw_symbol(func_sym) }
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == header_uri then return source_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    vim.api.nvim_win_set_buf(0, header_buf)
    vim.api.nvim_win_set_cursor(0, { 5, 5 })
    
    move_definition.execute_to_source()
    
    local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
    local has_definition = false
    for _, line in ipairs(source_lines) do
      if line:match('void freeFunc%(') and line:match('{}') then
        has_definition = true
        break
      end
    end
    assert.True(has_definition)
    
    vim.api.nvim_buf_delete(header_buf, { force = true })
    vim.api.nvim_buf_delete(source_buf, { force = true })
  end)

  it('moves method definition inside class to source with scope prefix', function()
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class MyClass {',
      'public:',
      '  void inlineMethod() { int x = 5; }',
      '};',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'test.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'test.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local method_sym = SourceSymbol.new({
      name = 'inlineMethod',
      kind = 6,
      range = { start = { line = 5, character = 2 }, ['end'] = { line = 5, character = 38 } },
      selectionRange = { start = { line = 5, character = 8 }, ['end'] = { line = 5, character = 20 } },
      children = {},
    }, header_uri, nil)
    
    local class_sym = SourceSymbol.new({
      name = 'MyClass',
      kind = 5,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 6, character = 2 } },
      selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 13 } },
      children = { to_raw_symbol(method_sym) },
    }, header_uri, nil)
    
    local wrapped_method = class_sym.children[1]
    wrapped_method.parent = class_sym
    
    SourceFile.get_symbols = function(self)
      if self.uri == header_uri then
        return { to_raw_symbol(class_sym) }
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == header_uri then return source_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    vim.api.nvim_win_set_buf(0, header_buf)
    vim.api.nvim_win_set_cursor(0, { 6, 8 })
    
    move_definition.execute_to_source()
    
    local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
    local has_scoped_def = false
    for _, line in ipairs(source_lines) do
      if line:match('MyClass::inlineMethod') then
        has_scoped_def = true
        break
      end
    end
    assert.True(has_scoped_def)
    
    vim.api.nvim_buf_delete(header_buf, { force = true })
    vim.api.nvim_buf_delete(source_buf, { force = true })
  end)

  it('moves method definition outside class (but in header) to source', function()
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class MyClass {',
      'public:',
      '  void methodA();',
      '};',
      '',
      'void MyClass::methodA() {}',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'test_class2.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'test_class2.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local method_sym = SourceSymbol.new({
      name = 'methodA',
      kind = 6,
      range = { start = { line = 8, character = 0 }, ['end'] = { line = 8, character = 26 } },
      selectionRange = { start = { line = 8, character = 16 }, ['end'] = { line = 8, character = 23 } },
      children = {},
    }, header_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == header_uri then
        return { to_raw_symbol(method_sym) }
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == header_uri then return source_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    vim.api.nvim_win_set_buf(0, header_buf)
    vim.api.nvim_win_set_cursor(0, { 9, 16 })
    
    move_definition.execute_to_source()
    
    local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
    local has_def = false
    for _, line in ipairs(source_lines) do
      if line:match('MyClass::methodA') then
        has_def = true
        break
      end
    end
    assert.True(has_def)
    
    vim.api.nvim_buf_delete(header_buf, { force = true })
    vim.api.nvim_buf_delete(source_buf, { force = true })
  end)

  it('moves comment with function when always_move_comments = true', function()
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '// This is a comment',
      'void func() {}',
      '',
      '#endif',
    }, 'c')
    vim.api.nvim_buf_set_name(header_buf, 'test_comment.h')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
    }, 'c')
    vim.api.nvim_buf_set_name(source_buf, 'test_comment.c')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'func',
      kind = 12,
      range = { start = { line = 4, character = 0 }, ['end'] = { line = 4, character = 14 } },
      selectionRange = { start = { line = 4, character = 5 }, ['end'] = { line = 4, character = 9 } },
      children = {},
    }, header_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == header_uri then
        return { to_raw_symbol(func_sym) }
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == header_uri then return source_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = true
    
    vim.api.nvim_win_set_buf(0, header_buf)
    vim.api.nvim_win_set_cursor(0, { 5, 5 })
    
    move_definition.execute_to_source()
    
    local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
    local has_comment = false
    for _, line in ipairs(source_lines) do
      if line:match('This is a comment') then
        has_comment = true
        break
      end
    end
    assert.True(has_comment)
    
    vim.api.nvim_buf_delete(header_buf, { force = true })
    vim.api.nvim_buf_delete(source_buf, { force = true })
  end)

  it('leaves comment in header when always_move_comments = false', function()
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '// This comment stays',
      'void func() {}',
      '',
      '#endif',
    }, 'c')
    vim.api.nvim_buf_set_name(header_buf, 'test_nocomment.h')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
    }, 'c')
    vim.api.nvim_buf_set_name(source_buf, 'test_nocomment.c')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'func',
      kind = 12,
      range = { start = { line = 4, character = 0 }, ['end'] = { line = 4, character = 14 } },
      selectionRange = { start = { line = 4, character = 5 }, ['end'] = { line = 4, character = 9 } },
      children = {},
    }, header_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == header_uri then
        return { to_raw_symbol(func_sym) }
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == header_uri then return source_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    vim.api.nvim_win_set_buf(0, header_buf)
    vim.api.nvim_win_set_cursor(0, { 5, 5 })
    
    move_definition.execute_to_source()
    
    local header_lines = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)
    local has_comment = false
    for _, line in ipairs(header_lines) do
      if line:match('This comment stays') then
        has_comment = true
        break
      end
    end
    assert.True(has_comment)
    
    vim.api.nvim_buf_delete(header_buf, { force = true })
    vim.api.nvim_buf_delete(source_buf, { force = true })
  end)

  it('handles function with preceding block comment', function()
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      '/*',
      ' * Block comment',
      ' */',
      'void func() {}',
      '',
      '#endif',
    }, 'c')
    vim.api.nvim_buf_set_name(header_buf, 'test_blockcomment.h')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
    }, 'c')
    vim.api.nvim_buf_set_name(source_buf, 'test_blockcomment.c')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'func',
      kind = 12,
      range = { start = { line = 6, character = 0 }, ['end'] = { line = 6, character = 14 } },
      selectionRange = { start = { line = 6, character = 5 }, ['end'] = { line = 6, character = 9 } },
      children = {},
    }, header_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == header_uri then
        return { to_raw_symbol(func_sym) }
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == header_uri then return source_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = true
    
    vim.api.nvim_win_set_buf(0, header_buf)
    vim.api.nvim_win_set_cursor(0, { 7, 5 })
    
    move_definition.execute_to_source()
    
    local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
    local has_block_comment = false
    for _, line in ipairs(source_lines) do
      if line:match('Block comment') or line:match('/%*') then
        has_block_comment = true
        break
      end
    end
    assert.True(has_block_comment)
    
    vim.api.nvim_buf_delete(header_buf, { force = true })
    vim.api.nvim_buf_delete(source_buf, { force = true })
  end)

  it('handles constructor definition', function()
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'class Test {',
      '  int x;',
      'public:',
      '  Test() : x(0) {}',
      '};',
      '',
      '#endif',
    }, 'cpp')
    vim.api.nvim_buf_set_name(header_buf, 'test_ctor.hpp')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
    }, 'cpp')
    vim.api.nvim_buf_set_name(source_buf, 'test_ctor.cpp')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local ctor_sym = SourceSymbol.new({
      name = 'Test',
      kind = 9,
      range = { start = { line = 6, character = 2 }, ['end'] = { line = 6, character = 18 } },
      selectionRange = { start = { line = 6, character = 2 }, ['end'] = { line = 6, character = 6 } },
      children = {},
    }, header_uri, nil)
    
    local class_sym = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 7, character = 2 } },
      selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 10 } },
      children = { to_raw_symbol(ctor_sym) },
    }, header_uri, nil)
    
    local wrapped_ctor = class_sym.children[1]
    wrapped_ctor.parent = class_sym
    
    SourceFile.get_symbols = function(self)
      if self.uri == header_uri then
        return { to_raw_symbol(class_sym) }
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == header_uri then return source_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    vim.api.nvim_win_set_buf(0, header_buf)
    vim.api.nvim_win_set_cursor(0, { 7, 4 })
    
    move_definition.execute_to_source()
    
    local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
    local has_ctor = false
    for _, line in ipairs(source_lines) do
      if line:match('Test::Test') then
        has_ctor = true
        break
      end
    end
    assert.True(has_ctor)
    
    vim.api.nvim_buf_delete(header_buf, { force = true })
    vim.api.nvim_buf_delete(source_buf, { force = true })
  end)

  it('handles function with trailing comment', function()
    local header_buf = helpers.create_buffer({
      '#ifndef TEST_H',
      '#define TEST_H',
      '',
      'void func() {} // inline comment',
      '',
      '#endif',
    }, 'c')
    vim.api.nvim_buf_set_name(header_buf, 'test_trailing.h')
    local header_uri = vim.uri_from_bufnr(header_buf)
    
    local source_buf = helpers.create_buffer({
      '#include "test.h"',
    }, 'c')
    vim.api.nvim_buf_set_name(source_buf, 'test_trailing.c')
    local source_uri = vim.uri_from_bufnr(source_buf)
    
    local func_sym = SourceSymbol.new({
      name = 'func',
      kind = 12,
      range = { start = { line = 3, character = 0 }, ['end'] = { line = 3, character = 32 } },
      selectionRange = { start = { line = 3, character = 5 }, ['end'] = { line = 3, character = 9 } },
      children = {},
    }, header_uri, nil)
    
    SourceFile.get_symbols = function(self)
      if self.uri == header_uri then
        return { to_raw_symbol(func_sym) }
      end
      return {}
    end
    
    header_source.get_matching = function(uri)
      if uri == header_uri then return source_uri end
      return nil
    end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    vim.api.nvim_win_set_buf(0, header_buf)
    vim.api.nvim_win_set_cursor(0, { 4, 5 })
    
    move_definition.execute_to_source()
    
    local source_lines = vim.api.nvim_buf_get_lines(source_buf, 0, -1, false)
    local has_func = false
    for _, line in ipairs(source_lines) do
      if line:match('void func') then
        has_func = true
        break
      end
    end
    assert.True(has_func)
    
    vim.api.nvim_buf_delete(header_buf, { force = true })
    vim.api.nvim_buf_delete(source_buf, { force = true })
  end)
end)

describe('move_definition execute_into_or_out_of_class', function()
  local orig_get_symbols
  local saved_config
  local orig_buf

  before_each(function()
    orig_get_symbols = SourceFile.get_symbols
    saved_config = vim.deepcopy(config.values)
    orig_buf = vim.api.nvim_win_get_buf(0)
  end)

  after_each(function()
    SourceFile.get_symbols = orig_get_symbols
    config.values = saved_config
    vim.api.nvim_win_set_buf(0, orig_buf)
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
    
    move_definition.execute_into_or_out_of_class()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies error when symbol is not a function definition', function()
    local bufnr = helpers.create_buffer({ 'int x = 5;' }, 'cpp')
    vim.api.nvim_win_set_buf(0, bufnr)
    
    local var_sym = SourceSymbol.new({
      name = 'x',
      kind = 13,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 9 } },
      selectionRange = { start = { line = 0, character = 4 }, ['end'] = { line = 0, character = 5 } },
      children = {},
    }, vim.uri_from_bufnr(bufnr), nil)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(var_sym) } end
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('not a function') then
        notified = true
      end
    end
    
    vim.api.nvim_win_set_cursor(0, { 1, 4 })
    move_definition.execute_into_or_out_of_class()
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('detects definition inside class and moves out', function()
    local bufnr = helpers.create_buffer({
      'class MyClass {',
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
      name = 'MyClass',
      kind = 5,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 3, character = 2 } },
      selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 13 } },
      children = { to_raw_symbol(method_sym) },
    }, uri, nil)
    
    local wrapped_method = class_sym.children[1]
    wrapped_method.parent = class_sym
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 3, 8 })
    
    move_definition.execute_into_or_out_of_class()
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_outside = false
    for i, line in ipairs(lines) do
      if i > 4 and line:match('MyClass::method') then
        found_outside = true
        break
      end
    end
    assert.True(found_outside)
    
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe('move_definition _move_out_of_class', function()
  local orig_get_symbols
  local saved_config
  local orig_buf

  before_each(function()
    orig_get_symbols = SourceFile.get_symbols
    saved_config = vim.deepcopy(config.values)
    orig_buf = vim.api.nvim_win_get_buf(0)
  end)

  after_each(function()
    SourceFile.get_symbols = orig_get_symbols
    config.values = saved_config
    vim.api.nvim_win_set_buf(0, orig_buf)
  end)

  it('moves simple method out of class with scope prefix', function()
    local bufnr = helpers.create_buffer({
      'class Test {',
      'public:',
      '  void foo() {}',
      '};',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local method_sym = SourceSymbol.new({
      name = 'foo',
      kind = 6,
      range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 16 } },
      selectionRange = { start = { line = 2, character = 8 }, ['end'] = { line = 2, character = 11 } },
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
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(wrapped_method, doc)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    move_definition._move_out_of_class(doc, csymbol)
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_scoped = false
    for _, line in ipairs(lines) do
      if line:match('Test::foo') then
        found_scoped = true
        break
      end
    end
    assert.True(found_scoped)
    
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies error when function is not inside a class', function()
    local bufnr = helpers.create_buffer({
      'void freeFunc() {}',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local func_sym = SourceSymbol.new({
      name = 'freeFunc',
      kind = 12,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 18 } },
      selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 13 } },
      children = {},
    }, uri, nil)
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(func_sym, doc)
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('not inside a class') then
        notified = true
      end
    end
    
    move_definition._move_out_of_class(doc, csymbol)
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('handles function with virtual keyword', function()
    local bufnr = helpers.create_buffer({
      'class Base {',
      'public:',
      '  virtual void foo() {}',
      '};',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local method_sym = SourceSymbol.new({
      name = 'foo',
      kind = 6,
      range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 26 } },
      selectionRange = { start = { line = 2, character = 16 }, ['end'] = { line = 2, character = 19 } },
      children = {},
    }, uri, nil)
    
    local class_sym = SourceSymbol.new({
      name = 'Base',
      kind = 5,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 3, character = 2 } },
      selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 10 } },
      children = { to_raw_symbol(method_sym) },
    }, uri, nil)
    
    local wrapped_method = class_sym.children[1]
    wrapped_method.parent = class_sym
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(wrapped_method, doc)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    move_definition._move_out_of_class(doc, csymbol)
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_def = false
    for _, line in ipairs(lines) do
      if line:match('Base::foo') then
        found_def = true
        break
      end
    end
    assert.True(found_def)
    
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('handles method with access specifier context', function()
    local bufnr = helpers.create_buffer({
      'class Test {',
      'public:',
      '  void pubMethod() {}',
      'protected:',
      '  void protMethod() {}',
      '};',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local method_sym = SourceSymbol.new({
      name = 'protMethod',
      kind = 6,
      range = { start = { line = 4, character = 2 }, ['end'] = { line = 4, character = 26 } },
      selectionRange = { start = { line = 4, character = 8 }, ['end'] = { line = 4, character = 18 } },
      children = {},
    }, uri, nil)
    
    local class_sym = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 5, character = 2 } },
      selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 10 } },
      children = { to_raw_symbol(method_sym) },
    }, uri, nil)
    
    local wrapped_method = class_sym.children[1]
    wrapped_method.parent = class_sym
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(wrapped_method, doc)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    move_definition._move_out_of_class(doc, csymbol)
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_scoped = false
    for _, line in ipairs(lines) do
      if line:match('Test::protMethod') then
        found_scoped = true
        break
      end
    end
    assert.True(found_scoped)
    
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe('move_definition _move_into_class', function()
  local orig_get_symbols
  local saved_config
  local orig_buf

  before_each(function()
    orig_get_symbols = SourceFile.get_symbols
    saved_config = vim.deepcopy(config.values)
    orig_buf = vim.api.nvim_win_get_buf(0)
  end)

  after_each(function()
    SourceFile.get_symbols = orig_get_symbols
    config.values = saved_config
    vim.api.nvim_win_set_buf(0, orig_buf)
  end)

  it('notifies error when no parent class found', function()
    local bufnr = helpers.create_buffer({
      'void freeFunc() {}',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local func_sym = SourceSymbol.new({
      name = 'freeFunc',
      kind = 12,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 18 } },
      selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 13 } },
      children = {},
    }, uri, nil)
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(func_sym, doc)
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('No parent class') then
        notified = true
      end
    end
    
    move_definition._move_into_class(doc, csymbol)
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('notifies error when class definition not in current file', function()
    local bufnr = helpers.create_buffer({
      '#include "other.h"',
      '',
      'void OtherClass::method() {}',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local class_sym = SourceSymbol.new({
      name = 'OtherClass',
      kind = 5,
      range = { start = { line = 100, character = 0 }, ['end'] = { line = 110, character = 2 } },
      selectionRange = { start = { line = 100, character = 6 }, ['end'] = { line = 100, character = 16 } },
      children = {},
    }, 'file:///other.h', nil)
    
    local method_sym = SourceSymbol.new({
      name = 'method',
      kind = 6,
      range = { start = { line = 2, character = 0 }, ['end'] = { line = 2, character = 28 } },
      selectionRange = { start = { line = 2, character = 17 }, ['end'] = { line = 2, character = 23 } },
      children = {},
    }, uri, class_sym)
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(method_sym, doc)
    
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('Could not find class definition') then
        notified = true
      end
    end
    
    move_definition._move_into_class(doc, csymbol)
    
    vim.notify = orig_notify
    assert.True(notified)
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe('move_definition execute dispatcher', function()
  local orig_get_symbols
  local saved_config
  local orig_buf
  local orig_execute_to_source
  local orig_execute_in_out

  before_each(function()
    orig_get_symbols = SourceFile.get_symbols
    saved_config = vim.deepcopy(config.values)
    orig_buf = vim.api.nvim_win_get_buf(0)
    orig_execute_to_source = move_definition.execute_to_source
    orig_execute_in_out = move_definition.execute_into_or_out_of_class
  end)

  after_each(function()
    SourceFile.get_symbols = orig_get_symbols
    config.values = saved_config
    vim.api.nvim_win_set_buf(0, orig_buf)
    move_definition.execute_to_source = orig_execute_to_source
    move_definition.execute_into_or_out_of_class = orig_execute_in_out
  end)

  it('calls execute_to_source when mode = to_source', function()
    local called = false
    move_definition.execute_to_source = function()
      called = true
    end
    
    move_definition.execute({ mode = 'to_source' })
    
    assert.True(called)
  end)

  it('calls execute_into_or_out_of_class when mode = in_out_class', function()
    local called = false
    move_definition.execute_into_or_out_of_class = function()
      called = true
    end
    
    move_definition.execute({ mode = 'in_out_class' })
    
    assert.True(called)
  end)

  it('defaults to to_source when no mode specified', function()
    local called = false
    move_definition.execute_to_source = function()
      called = true
    end
    
    move_definition.execute({})
    
    assert.True(called)
  end)

  it('notifies error for unknown mode', function()
    local notified = false
    local orig_notify = vim.notify
    vim.notify = function(msg, level)
      if msg:match('Unknown mode') then
        notified = true
      end
    end
    
    move_definition.execute({ mode = 'invalid_mode' })
    
    vim.notify = orig_notify
    assert.True(notified)
  end)

  it('handles nil opts by using default mode', function()
    local called = false
    move_definition.execute_to_source = function()
      called = true
    end
    
    move_definition.execute(nil)
    
    assert.True(called)
  end)
end)

describe('move_definition additional coverage', function()
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

  it('handles function with const qualifier', function()
    local bufnr = helpers.create_buffer({
      'class Test {',
      'public:',
      '  int getValue() const { return value; }',
      'private:',
      '  int value;',
      '};',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local method_sym = SourceSymbol.new({
      name = 'getValue',
      kind = 6,
      range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 42 } },
      selectionRange = { start = { line = 2, character = 6 }, ['end'] = { line = 2, character = 14 } },
      children = {},
    }, uri, nil)
    
    local class_sym = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 5, character = 2 } },
      selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 10 } },
      children = { to_raw_symbol(method_sym) },
    }, uri, nil)
    
    local wrapped_method = class_sym.children[1]
    wrapped_method.parent = class_sym
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(wrapped_method, doc)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    move_definition._move_out_of_class(doc, csymbol)
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_def = false
    for _, line in ipairs(lines) do
      if line:match('Test::getValue') then
        found_def = true
        break
      end
    end
    assert.True(found_def)
    
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('handles static method', function()
    local bufnr = helpers.create_buffer({
      'class Test {',
      'public:',
      '  static int getCount() { return count; }',
      'private:',
      '  static int count;',
      '};',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local method_sym = SourceSymbol.new({
      name = 'getCount',
      kind = 6,
      range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 44 } },
      selectionRange = { start = { line = 2, character = 13 }, ['end'] = { line = 2, character = 21 } },
      children = {},
    }, uri, nil)
    
    local class_sym = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 5, character = 2 } },
      selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 10 } },
      children = { to_raw_symbol(method_sym) },
    }, uri, nil)
    
    local wrapped_method = class_sym.children[1]
    wrapped_method.parent = class_sym
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(wrapped_method, doc)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    move_definition._move_out_of_class(doc, csymbol)
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_def = false
    for _, line in ipairs(lines) do
      if line:match('Test::getCount') then
        found_def = true
        break
      end
    end
    assert.True(found_def)
    
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('handles inline method', function()
    local bufnr = helpers.create_buffer({
      'class Test {',
      'public:',
      '  inline void process() { /* do work */ }',
      '};',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local method_sym = SourceSymbol.new({
      name = 'process',
      kind = 6,
      range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 44 } },
      selectionRange = { start = { line = 2, character = 13 }, ['end'] = { line = 2, character = 20 } },
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
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(wrapped_method, doc)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    move_definition._move_out_of_class(doc, csymbol)
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_def = false
    for _, line in ipairs(lines) do
      if line:match('Test::process') then
        found_def = true
        break
      end
    end
    assert.True(found_def)
    
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('handles destructor', function()
    local bufnr = helpers.create_buffer({
      'class Test {',
      'public:',
      '  ~Test() { cleanup(); }',
      '};',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local dtor_sym = SourceSymbol.new({
      name = '~Test',
      kind = 6,
      range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 26 } },
      selectionRange = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 7 } },
      children = {},
    }, uri, nil)
    
    local class_sym = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 3, character = 2 } },
      selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 10 } },
      children = { to_raw_symbol(dtor_sym) },
    }, uri, nil)
    
    local wrapped_dtor = class_sym.children[1]
    wrapped_dtor.parent = class_sym
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(wrapped_dtor, doc)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    move_definition._move_out_of_class(doc, csymbol)
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_def = false
    for _, line in ipairs(lines) do
      if line:match('Test::~Test') then
        found_def = true
        break
      end
    end
    assert.True(found_def)
    
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('handles method with parameters', function()
    local bufnr = helpers.create_buffer({
      'class Test {',
      'public:',
      '  void setValue(int x, const std::string& s) { value = x; name = s; }',
      'private:',
      '  int value;',
      '  std::string name;',
      '};',
    }, 'cpp')
    local uri = vim.uri_from_bufnr(bufnr)
    
    local method_sym = SourceSymbol.new({
      name = 'setValue',
      kind = 6,
      range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 66 } },
      selectionRange = { start = { line = 2, character = 8 }, ['end'] = { line = 2, character = 16 } },
      children = {},
    }, uri, nil)
    
    local class_sym = SourceSymbol.new({
      name = 'Test',
      kind = 5,
      range = { start = { line = 0, character = 0 }, ['end'] = { line = 6, character = 2 } },
      selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 10 } },
      children = { to_raw_symbol(method_sym) },
    }, uri, nil)
    
    local wrapped_method = class_sym.children[1]
    wrapped_method.parent = class_sym
    
    local doc = SourceDocument.new(bufnr)
    local csymbol = CSymbol.new(wrapped_method, doc)
    
    SourceFile.get_symbols = function() return { to_raw_symbol(class_sym) } end
    
    config.values.reveal_new_definition = false
    config.values.always_move_comments = false
    
    move_definition._move_out_of_class(doc, csymbol)
    
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local found_def = false
    for _, line in ipairs(lines) do
      if line:match('Test::setValue') then
        found_def = true
        break
      end
    end
    assert.True(found_def)
    
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
