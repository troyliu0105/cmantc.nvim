--- Tests for commands/generate_operators.lua
---
--- Strategy: mock SourceDocument.new to inject pre-built SourceSymbol trees
--- into a real document backed by a real buffer, so that text insertion,
--- operator generation, and notify calls can all be verified end-to-end.

local gen_ops = require('cmantic.commands.generate_operators')
local helpers = require('tests.helpers')
local config = require('cmantic.config')
local SourceDocument = require('cmantic.source_document')
local SourceSymbol = require('cmantic.source_symbol')
local utils = require('cmantic.utils')

local SK = SourceSymbol.SymbolKind
local eq = assert.are.same

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Create a mock LSP DocumentSymbol raw table
--- @param opts table
--- @return table raw DocumentSymbol
local function mock_sym(opts)
  return {
    name = opts.name or 'test',
    kind = opts.kind or SK.Field,
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

--- Build a SourceSymbol tree for a class with named member variables
--- Returns the class SourceSymbol (children have .parent set)
--- @param class_name string
--- @param members string[] member variable names
--- @param class_start_line number 0-indexed line where class begins
--- @return table class SourceSymbol
local function make_class_sym(class_name, members, class_start_line)
  class_start_line = class_start_line or 0
  local children_raw = {}
  for i, mname in ipairs(members) do
    local field_line = class_start_line + 2 + (i - 1) -- line after "public:"
    table.insert(children_raw, mock_sym({
      name = mname,
      kind = SK.Field,
      start_line = field_line,
      start_char = 2,
      end_line = field_line,
      end_char = 2 + #mname + 5, -- "  int x;" ~ 5 extra chars
      sel_start = { line = field_line, character = 6 },
      sel_end = { line = field_line, character = 6 + #mname },
    }))
  end

  local class_end_line = class_start_line + 2 + #members
  local raw = mock_sym({
    name = class_name,
    kind = SK.Class,
    start_line = class_start_line,
    start_char = 0,
    end_line = class_end_line,
    end_char = 2,
    sel_start = { line = class_start_line, character = 6 },
    sel_end = { line = class_start_line, character = 6 + #class_name },
    children = children_raw,
  })

  return SourceSymbol.new(raw, 'file:///test.hpp', nil)
end

--- Build buffer lines for a class with given members
--- @param class_name string
--- @param members string[]
--- @return string[] lines
local function class_buffer_lines(class_name, members)
  local lines = {
    'class ' .. class_name .. ' {',
    'public:',
  }
  for _, mname in ipairs(members) do
    table.insert(lines, '  int ' .. mname .. ';')
  end
  table.insert(lines, '};')
  return lines
end

--- Build buffer lines for a class with a static member
--- @param class_name string
--- @param members string[] non-static members
--- @param static_members string[] static members
--- @return string[] lines
local function class_buffer_lines_with_statics(class_name, members, static_members)
  local lines = {
    'class ' .. class_name .. ' {',
    'public:',
  }
  for _, mname in ipairs(members) do
    table.insert(lines, '  int ' .. mname .. ';')
  end
  for _, mname in ipairs(static_members) do
    table.insert(lines, '  static int ' .. mname .. ';')
  end
  table.insert(lines, '};')
  return lines
end

--- Find a notify call matching predicate
--- @param calls table[] notify_calls list
--- @param msg_pattern string substring to match in msg
--- @return table|nil
local function find_notify(calls, msg_pattern)
  for _, c in ipairs(calls) do
    if c.msg:find(msg_pattern) then
      return c
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Test suite
--------------------------------------------------------------------------------

describe('generate_operators', function()
  local saved_config
  local saved_sd_new
  local saved_notify
  local notify_calls
  local cleanup_bufs

  before_each(function()
    saved_config = vim.deepcopy(config.values)
    saved_sd_new = SourceDocument.new
    saved_notify = utils.notify
    notify_calls = {}
    cleanup_bufs = {}

    -- Spy on utils.notify
    utils.notify = function(msg, level)
      table.insert(notify_calls, { msg = msg, level = level })
    end
  end)

  after_each(function()
    config.values = saved_config
    SourceDocument.new = saved_sd_new
    utils.notify = saved_notify

    -- Clean up buffers we created
    for _, bufnr in ipairs(cleanup_bufs) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end)

  --- Create a buffer, make it current, set cursor, and mock SourceDocument.new
  --- to inject symbols into the doc
  --- @param lines string[] buffer content
  --- @param symbols table[] SourceSymbol instances to inject
  --- @param cursor_line number 0-indexed
  --- @param cursor_char number 0-indexed
  --- @return number bufnr
  local function setup_buffer_and_mock(lines, symbols, cursor_line, cursor_char)
    local bufnr = helpers.create_buffer(lines, 'cpp')
    table.insert(cleanup_bufs, bufnr)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_cursor(0, { cursor_line + 1, cursor_char })

    SourceDocument.new = function(b)
      local doc = saved_sd_new(b)
      doc.symbols = symbols
      return doc
    end

    return bufnr
  end

  --[[ Input validation ]]

  describe('input validation', function()
    it('should notify warn when no symbol at cursor position', function()
      local bufnr = setup_buffer_and_mock(
        { 'int main() {}' },
        {}, -- no symbols
        0, 0
      )

      gen_ops.execute({ mode = 'equality' })

      local call = find_notify(notify_calls, 'No symbol at cursor position')
      assert.is_not_nil(call, 'should warn about no symbol')
      eq(vim.log.levels.WARN, call.level)
    end)

    it('should notify warn when cursor is on a free function (non-class, non-member)', function()
      local func_sym = SourceSymbol.new(mock_sym({
        name = 'freeFunc',
        kind = SK.Function,
        start_line = 0, start_char = 0,
        end_line = 0, end_char = 20,
        sel_start = { line = 0, character = 5 },
        sel_end = { line = 0, character = 12 },
      }), 'file:///test.cpp', nil)

      setup_buffer_and_mock(
        { 'void freeFunc() {}' },
        { func_sym },
        0, 5
      )

      gen_ops.execute({ mode = 'equality' })

      local call = find_notify(notify_calls, 'Cursor must be on a class')
      assert.is_not_nil(call, 'should warn about wrong symbol type')
      eq(vim.log.levels.WARN, call.level)
    end)

    it('should notify warn when cursor is on a namespace', function()
      local ns_sym = SourceSymbol.new(mock_sym({
        name = 'MyNS',
        kind = SK.Namespace,
        start_line = 0, start_char = 0,
        end_line = 2, end_char = 1,
        sel_start = { line = 0, character = 10 },
        sel_end = { line = 0, character = 14 },
      }), 'file:///test.hpp', nil)

      setup_buffer_and_mock(
        { 'namespace MyNS {', '}', '' },
        { ns_sym },
        0, 10
      )

      gen_ops.execute({ mode = 'equality' })

      local call = find_notify(notify_calls, 'Cursor must be on a class')
      assert.is_not_nil(call, 'should warn about namespace')
    end)
  end)

  --[[ Mode routing ]]

  describe('mode routing', function()
    it('should generate equality operators when mode = "equality"', function()
      local class_sym = make_class_sym('Point', { 'x' })
      local lines = class_buffer_lines('Point', { 'x' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local call = find_notify(notify_calls, 'Generated == and != operators')
      assert.is_not_nil(call, 'should generate equality operators')
      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator==') ~= nil, 'buffer should contain operator==')
      assert.is_true(all_text:find('operator!=') ~= nil, 'buffer should contain operator!=')
    end)

    it('should generate relational operators when mode = "relational"', function()
      local class_sym = make_class_sym('Vec', { 'x' })
      local lines = class_buffer_lines('Vec', { 'x' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'relational' })

      local call = find_notify(notify_calls, 'Generated <, >, <=, >= operators')
      assert.is_not_nil(call, 'should generate relational operators')

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator<') ~= nil)
      assert.is_true(all_text:find('operator>') ~= nil)
      assert.is_true(all_text:find('operator<=') ~= nil)
      assert.is_true(all_text:find('operator>=') ~= nil)
    end)

    it('should generate stream operator when mode = "stream"', function()
      local class_sym = make_class_sym('Data', { 'value' })
      local lines = class_buffer_lines('Data', { 'value' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'stream' })

      local call = find_notify(notify_calls, 'Generated << operator')
      assert.is_not_nil(call, 'should generate stream operator')

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator<<') ~= nil)
    end)

    it('should default to equality mode when no mode specified', function()
      local class_sym = make_class_sym('Foo', { 'a' })
      local lines = class_buffer_lines('Foo', { 'a' })
      setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({})

      local call = find_notify(notify_calls, 'Generated == and != operators')
      assert.is_not_nil(call, 'should default to equality mode')
    end)

    it('should default to equality mode when opts is nil', function()
      local class_sym = make_class_sym('Foo', { 'a' })
      local lines = class_buffer_lines('Foo', { 'a' })
      setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute()

      local call = find_notify(notify_calls, 'Generated == and != operators')
      assert.is_not_nil(call, 'should default to equality mode with nil opts')
    end)

    it('should notify warn on unknown mode string', function()
      local class_sym = make_class_sym('Foo', { 'a' })
      local lines = class_buffer_lines('Foo', { 'a' })
      setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'unknown_mode' })

      local call = find_notify(notify_calls, 'Unknown mode')
      assert.is_not_nil(call, 'should warn about unknown mode')
      eq(vim.log.levels.WARN, call.level)
    end)
  end)

  --[[ Equality mode ]]

  describe('equality mode', function()
    it('should generate == and != declarations for class with members', function()
      local class_sym = make_class_sym('Widget', { 'size', 'capacity' })
      local lines = class_buffer_lines('Widget', { 'size', 'capacity' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator==') ~= nil)
      assert.is_true(all_text:find('operator!=') ~= nil)
      assert.is_true(all_text:find('Equality operators') ~= nil, 'should have comment')
    end)

    it('should generate member operators when friend_comparison_operators = false', function()
      config.values.friend_comparison_operators = false
      local class_sym = make_class_sym('MyClass', { 'x' })
      local lines = class_buffer_lines('MyClass', { 'x' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      -- Member style: "bool operator==(const MyClass& other) const;"
      assert.is_true(all_text:find('const MyClass& other') ~= nil, 'should use member style')
      assert.is_true(all_text:find('friend') == nil, 'should NOT have friend keyword')
    end)

    it('should generate friend operators when friend_comparison_operators = true', function()
      config.values.friend_comparison_operators = true
      local class_sym = make_class_sym('MyClass', { 'x' })
      local lines = class_buffer_lines('MyClass', { 'x' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      -- Friend style: "friend bool operator==(const MyClass& lhs, const MyClass& rhs);"
      assert.is_true(all_text:find('friend bool') ~= nil, 'should have friend keyword')
      assert.is_true(all_text:find('const MyClass& lhs') ~= nil, 'should have lhs param')
      assert.is_true(all_text:find('const MyClass& rhs') ~= nil, 'should have rhs param')
    end)

    it('should handle class with single member variable', function()
      local class_sym = make_class_sym('Single', { 'val' })
      local lines = class_buffer_lines('Single', { 'val' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator==') ~= nil)
      assert.is_true(all_text:find('operator!=') ~= nil)
    end)

    it('should handle class with multiple member variables', function()
      local class_sym = make_class_sym('Multi', { 'a', 'b', 'c' })
      local lines = class_buffer_lines('Multi', { 'a', 'b', 'c' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator==') ~= nil)
      assert.is_true(all_text:find('operator!=') ~= nil)
      assert.is_true(all_text:find('Multi') ~= nil, 'declarations should reference class name')
    end)
  end)

  --[[ Relational mode ]]

  describe('relational mode', function()
    it('should generate <, >, <=, >= declarations', function()
      local class_sym = make_class_sym('Point', { 'x', 'y' })
      local lines = class_buffer_lines('Point', { 'x', 'y' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'relational' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator<') ~= nil, 'should have operator<')
      assert.is_true(all_text:find('operator>') ~= nil, 'should have operator>')
      assert.is_true(all_text:find('operator<=') ~= nil, 'should have operator<=')
      assert.is_true(all_text:find('operator>=') ~= nil, 'should have operator>=')
      assert.is_true(all_text:find('Relational operators') ~= nil, 'should have comment')
    end)

    it('should handle single operand', function()
      local class_sym = make_class_sym('Mono', { 'value' })
      local lines = class_buffer_lines('Mono', { 'value' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'relational' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator<') ~= nil)
      assert.is_true(all_text:find('operator>') ~= nil)
    end)
  end)

  --[[ Stream mode ]]

  describe('stream mode', function()
    it('should generate << operator declaration', function()
      local class_sym = make_class_sym('LogEntry', { 'msg' })
      local lines = class_buffer_lines('LogEntry', { 'msg' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'stream' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator<<') ~= nil)
      assert.is_true(all_text:find('std::ostream') ~= nil, 'should use std::ostream')
      assert.is_true(all_text:find('Stream output operator') ~= nil, 'should have comment')
    end)

    it('should handle multiple operands with separator', function()
      local class_sym = make_class_sym('Vec3', { 'x', 'y', 'z' })
      local lines = class_buffer_lines('Vec3', { 'x', 'y', 'z' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'stream' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator<<') ~= nil)
      assert.is_true(all_text:find('Vec3') ~= nil, 'declaration should reference class name')
    end)
  end)

  --[[ Edge cases ]]

  describe('edge cases', function()
    it('should warn when no non-static member variables found', function()
      local class_sym = make_class_sym('Empty', {})
      local lines = class_buffer_lines('Empty', {})
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator==') == nil, 'should NOT insert operators for class with no members')
    end)

    it('should skip static members and warn if only statics exist', function()
      local class_sym = make_class_sym('StaticOnly', { 'count' })
      local lines = class_buffer_lines('StaticOnly', { 'count' })
      class_sym.children[1].detail = 'static int'
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator==') == nil, 'should NOT insert operators when only static members exist')
    end)

    it('should accept cursor directly on class/struct symbol', function()
      local class_sym = make_class_sym('MyStruct', { 'data' })
      local lines = class_buffer_lines('MyStruct', { 'data' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 6)

      -- Cursor on the class name line
      gen_ops.execute({ mode = 'equality' })

      local call = find_notify(notify_calls, 'Generated == and != operators')
      assert.is_not_nil(call, 'should work when cursor is on class symbol')
    end)

    it('should accept cursor on member variable (resolves parent)', function()
      local class_sym = make_class_sym('Box', { 'width', 'height' })
      local lines = class_buffer_lines('Box', { 'width', 'height' })
      -- Cursor on line 2 (the 'width' field), char 6 (on the name)
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 2, 6)

      gen_ops.execute({ mode = 'equality' })

      local call = find_notify(notify_calls, 'Generated == and != operators')
      assert.is_not_nil(call, 'should resolve parent when cursor on member var')

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')
      assert.is_true(all_text:find('operator==') ~= nil)
    end)

    it('should accept struct kind as class type', function()
      local struct_sym = make_class_sym('Pair', { 'first', 'second' })
      -- Override kind to Struct
      struct_sym.kind = SK.Struct
      local lines = class_buffer_lines('Pair', { 'first', 'second' })
      local bufnr = setup_buffer_and_mock(lines, { struct_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local call = find_notify(notify_calls, 'Generated == and != operators')
      assert.is_not_nil(call, 'should work for struct')
    end)
  end)

  --[[ Config interaction ]]

  describe('config interaction', function()
    it('reads friend_comparison_operators at call time (not cached)', function()
      local class_sym = make_class_sym('Foo', { 'x' })
      local lines = class_buffer_lines('Foo', { 'x' })

      -- Call with member variant
      config.values.friend_comparison_operators = false
      local bufnr1 = setup_buffer_and_mock(lines, { class_sym }, 0, 0)
      gen_ops.execute({ mode = 'equality' })
      local buf_lines1 = vim.api.nvim_buf_get_lines(bufnr1, 0, -1, false)
      local text1 = table.concat(buf_lines1, '\n')
      assert.is_true(text1:find('friend') == nil, 'member variant should not have friend')

      -- Re-create for second call with friend variant
      local class_sym2 = make_class_sym('Foo', { 'x' })
      config.values.friend_comparison_operators = true
      local bufnr2 = setup_buffer_and_mock(lines, { class_sym2 }, 0, 0)
      gen_ops.execute({ mode = 'equality' })
      local buf_lines2 = vim.api.nvim_buf_get_lines(bufnr2, 0, -1, false)
      local text2 = table.concat(buf_lines2, '\n')
      assert.is_true(text2:find('friend bool') ~= nil, 'friend variant should have friend')
    end)
  end)

  --[[ Verify inserted text content ]]

  describe('inserted text content', function()
    it('equality mode inserts comment header and two declarations', function()
      local class_sym = make_class_sym('Foo', { 'x' })
      local lines = class_buffer_lines('Foo', { 'x' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'equality' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')

      -- Should have the comment
      assert.is_true(all_text:find('// Equality operators') ~= nil)
      -- Should have both operator declarations
      assert.is_true(all_text:find('operator==') ~= nil)
      assert.is_true(all_text:find('operator!=') ~= nil)
    end)

    it('relational mode inserts comment header and four declarations', function()
      local class_sym = make_class_sym('Foo', { 'x' })
      local lines = class_buffer_lines('Foo', { 'x' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'relational' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')

      assert.is_true(all_text:find('// Relational operators') ~= nil)
    end)

    it('stream mode inserts comment header and friend declaration', function()
      local class_sym = make_class_sym('Foo', { 'x' })
      local lines = class_buffer_lines('Foo', { 'x' })
      local bufnr = setup_buffer_and_mock(lines, { class_sym }, 0, 0)

      gen_ops.execute({ mode = 'stream' })

      local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local all_text = table.concat(buf_lines, '\n')

      assert.is_true(all_text:find('// Stream output operator') ~= nil)
      assert.is_true(all_text:find('friend std::ostream&') ~= nil)
    end)
  end)
end)
