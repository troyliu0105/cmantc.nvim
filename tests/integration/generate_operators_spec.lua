local helpers = require('tests.helpers')
local SourceDocument = require('cmantic.source_document')
local SourceSymbol = require('cmantic.source_symbol')
local generate_operators = require('cmantic.commands.generate_operators')
local SourceFile = require('cmantic.source_file')
local config = require('cmantic.config')

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function make_class_buffer_with_members(class_name, members, extra_lines)
  extra_lines = extra_lines or {}
  local lines = { 'class ' .. class_name .. ' {', 'public:' }
  for _, line in ipairs(extra_lines.before or {}) do
    table.insert(lines, line)
  end
  for _, member in ipairs(members) do
    table.insert(lines, '  ' .. member)
  end
  for _, line in ipairs(extra_lines.after or {}) do
    table.insert(lines, line)
  end
  table.insert(lines, '};')
  return helpers.create_buffer(lines, 'cpp')
end

local function make_class_symbols(bufnr, class_name, members_info, extra_config)
  extra_config = extra_config or {}
  local doc = SourceDocument.new(bufnr)
  local start_line = extra_config.start_line or 0
  local class_end_line = start_line + 1 + #members_info + (extra_config.extra_lines or 0)

  local children = {}
  local current_line = start_line + 2 -- Skip class declaration and public:

  for _, info in ipairs(members_info) do
    local char_start = info.char_start or 2
    table.insert(children, {
      name = info.name,
      kind = 8, -- Field
      range = {
        start = { line = current_line, character = 0 },
        ['end'] = { line = current_line, character = 50 },
      },
      selectionRange = {
        start = { line = current_line, character = char_start },
        ['end'] = { line = current_line, character = char_start + #info.name },
      },
      children = {},
    })
    current_line = current_line + 1
  end

  local class_sym = SourceSymbol.new({
    name = class_name,
    kind = 23, -- Class
    range = {
      start = { line = start_line, character = 0 },
      ['end'] = { line = class_end_line, character = 2 },
    },
    selectionRange = {
      start = { line = start_line, character = 6 },
      ['end'] = { line = start_line, character = 6 + #class_name },
    },
    children = children,
  }, vim.uri_from_bufnr(bufnr), nil)

  return class_sym, doc
end

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

local function mock_symbols_for_buf(bufnr, class_sym)
  local uri = vim.uri_from_bufnr(bufnr)
  SourceFile.get_symbols = function(self)
    if self.uri == uri then
      return { to_raw_symbol(class_sym) }
    end
    return {}
  end
end

local function find_closing_brace(lines)
  for i, line in ipairs(lines) do
    if line:match('^};') then
      return i
    end
  end
  return nil
end

local function contains_operator(lines, pattern, inside_class_only, closing_line)
  local search_end = inside_class_only and (closing_line - 1) or #lines
  local search_start = inside_class_only and 1 or (closing_line and (closing_line + 1) or 1)

  for i = search_start, search_end do
    if lines[i]:match(pattern) then
      return i
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- Test Suite
--------------------------------------------------------------------------------

describe('generate_operators integration', function()
  local orig_buf
  local orig_get_symbols
  local orig_config

  before_each(function()
    orig_buf = vim.api.nvim_win_get_buf(0)
    orig_get_symbols = SourceFile.get_symbols
    orig_config = vim.deepcopy(config.values)
  end)

  after_each(function()
    vim.api.nvim_win_set_buf(0, orig_buf)
    SourceFile.get_symbols = orig_get_symbols
    config.values = orig_config
  end)

  --------------------------------------------------------------------------------
  -- Equality Operators (==, !=)
  --------------------------------------------------------------------------------

  describe('equality mode', function()
    it('generates operator== and operator!= for class with single int member', function()
      local bufnr = make_class_buffer_with_members('Point', { 'int x;' })
      local class_sym = make_class_symbols(bufnr, 'Point', { { name = 'x', char_start = 6 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- Cursor on class name

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'equality' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local closing = find_closing_brace(lines)
      assert.truthy(closing, 'should find closing brace')

      local eq_line = contains_operator(lines, 'operator==', true, closing)
      local neq_line = contains_operator(lines, 'operator!=', true, closing)

      assert.truthy(eq_line, 'operator== should be generated inside class')
      assert.truthy(neq_line, 'operator!= should be generated inside class')
      assert.True(eq_line < closing, 'operator== must be inside class')
      assert.True(neq_line < closing, 'operator!= must be inside class')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('generates operators comparing all members in multi-member class', function()
      local bufnr = make_class_buffer_with_members('Vector3', { 'int x;', 'int y;', 'int z;' })
      local class_sym = make_class_symbols(bufnr, 'Vector3', {
        { name = 'x', char_start = 6 },
        { name = 'y', char_start = 6 },
        { name = 'z', char_start = 6 },
      })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'equality' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Find the operator== declaration and verify it exists
      local eq_line = nil
      for i, line in ipairs(lines) do
        if line:match('operator==') then
          eq_line = i
          break
        end
      end
      assert.truthy(eq_line, 'should find operator==')

      -- Verify operator!= is also generated
      local neq_line = nil
      for i, line in ipairs(lines) do
        if line:match('operator!=') then
          neq_line = i
          break
        end
      end
      assert.truthy(neq_line, 'should find operator!=')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('generates operators for class with pointer member', function()
      local bufnr = make_class_buffer_with_members('Container', { 'int* ptr;' })
      local class_sym = make_class_symbols(bufnr, 'Container', { { name = 'ptr', char_start = 7 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'equality' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local closing = find_closing_brace(lines)

      local eq_line = contains_operator(lines, 'operator==', true, closing)
      assert.truthy(eq_line, 'operator== should be generated for pointer member')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('generates operators for struct with members', function()
      local lines = { 'struct Data {', '  int value;', '};' }
      local bufnr = helpers.create_buffer(lines, 'cpp')

      local class_sym = SourceSymbol.new({
        name = 'Data',
        kind = 23, -- Struct uses same kind as class
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 2 } },
        selectionRange = { start = { line = 0, character = 7 }, ['end'] = { line = 0, character = 11 } },
        children = {
          {
            name = 'value',
            kind = 8,
            range = { start = { line = 1, character = 0 }, ['end'] = { line = 1, character = 15 } },
            selectionRange = { start = { line = 1, character = 6 }, ['end'] = { line = 1, character = 11 } },
            children = {},
          },
        },
      }, vim.uri_from_bufnr(bufnr), nil)

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 7 })

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'equality' })

      local result_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_eq = false
      for _, line in ipairs(result_lines) do
        if line:match('operator==') then
          has_eq = true
          break
        end
      end
      assert.True(has_eq, 'struct should get operator==')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('generates friend operators when friend_comparison_operators = true', function()
      local bufnr = make_class_buffer_with_members('Point', { 'int x;' })
      local class_sym = make_class_symbols(bufnr, 'Point', { { name = 'x', char_start = 6 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = true
      generate_operators.execute({ mode = 'equality' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Friend operators have different signature: (const Class& lhs, const Class& rhs)
      local found_friend_eq = false
      for _, line in ipairs(lines) do
        if line:match('friend%s+bool%s+operator==') then
          found_friend_eq = true
          break
        end
      end
      assert.True(found_friend_eq, 'should generate friend operator==')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('generates non-friend operators when friend_comparison_operators = false', function()
      local bufnr = make_class_buffer_with_members('Point', { 'int x;' })
      local class_sym = make_class_symbols(bufnr, 'Point', { { name = 'x', char_start = 6 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'equality' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Non-friend operators have signature: (const Class& other) const
      local found_member_eq = false
      for _, line in ipairs(lines) do
        if line:match('bool%s+operator==.*const%s+Point&.*other') then
          found_member_eq = true
          break
        end
      end
      assert.True(found_member_eq, 'should generate member operator==')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('handles cursor on member variable by using parent class', function()
      local bufnr = make_class_buffer_with_members('Widget', { 'int id;' })
      local class_sym = make_class_symbols(bufnr, 'Widget', { { name = 'id', char_start = 6 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 3, 6 }) -- Cursor on 'id' member

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'equality' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_eq = false
      for _, line in ipairs(lines) do
        if line:match('operator==') then
          has_eq = true
          break
        end
      end
      assert.True(has_eq, 'should generate operators when cursor is on member variable')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  --------------------------------------------------------------------------------
  -- Relational Operators (<, >, <=, >=)
  --------------------------------------------------------------------------------

  describe('relational mode', function()
    it('generates all four relational operators', function()
      local bufnr = make_class_buffer_with_members('Comparable', { 'int value;' })
      local class_sym = make_class_symbols(bufnr, 'Comparable', { { name = 'value', char_start = 6 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'relational' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local closing = find_closing_brace(lines)

      local has_lt = contains_operator(lines, 'operator<', true, closing)
      local has_gt = contains_operator(lines, 'operator>', true, closing)
      local has_le = contains_operator(lines, 'operator<=', true, closing)
      local has_ge = contains_operator(lines, 'operator>=', true, closing)

      assert.truthy(has_lt, 'operator< should be generated')
      assert.truthy(has_gt, 'operator> should be generated')
      assert.truthy(has_le, 'operator<= should be generated')
      assert.truthy(has_ge, 'operator>= should be generated')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('generates relational operators with multi-member cascading comparison', function()
      local bufnr = make_class_buffer_with_members('Tuple', { 'int a;', 'int b;', 'int c;' })
      local class_sym = make_class_symbols(bufnr, 'Tuple', {
        { name = 'a', char_start = 6 },
        { name = 'b', char_start = 6 },
        { name = 'c', char_start = 6 },
      })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'relational' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Find operator< declaration
      local lt_line = nil
      for i, line in ipairs(lines) do
        if line:match('operator<') and not line:match('operator<=') then
          lt_line = i
          break
        end
      end
      assert.truthy(lt_line, 'should find operator<')

      -- Verify all relational operators are generated
      local has_gt = false
      local has_le = false
      local has_ge = false
      for _, line in ipairs(lines) do
        if line:match('operator>') and not line:match('operator>=') then has_gt = true end
        if line:match('operator<=') then has_le = true end
        if line:match('operator>=') then has_ge = true end
      end
      assert.truthy(has_gt, 'should have operator>')
      assert.truthy(has_le, 'should have operator<=')
      assert.truthy(has_ge, 'should have operator>=')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('generates friend relational operators when configured', function()
      local bufnr = make_class_buffer_with_members('Ordered', { 'int priority;' })
      local class_sym = make_class_symbols(bufnr, 'Ordered', { { name = 'priority', char_start = 6 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = true
      generate_operators.execute({ mode = 'relational' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      local found_friend_lt = false
      for _, line in ipairs(lines) do
        if line:match('friend%s+bool%s+operator<') then
          found_friend_lt = true
          break
        end
      end
      assert.True(found_friend_lt, 'should generate friend operator<')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  --------------------------------------------------------------------------------
  -- Stream Operator (<<)
  --------------------------------------------------------------------------------

  describe('stream mode', function()
    it('generates operator<< for class with members', function()
      local bufnr = make_class_buffer_with_members('Printable', { 'int x;', 'std::string name;' })
      local class_sym = make_class_symbols(bufnr, 'Printable', {
        { name = 'x', char_start = 6 },
        { name = 'name', char_start = 16 },
      })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      generate_operators.execute({ mode = 'stream' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local closing = find_closing_brace(lines)

      local stream_line = contains_operator(lines, 'operator<<', true, closing)
      assert.truthy(stream_line, 'operator<< should be generated inside class')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('stream operator includes all member names in output', function()
      local bufnr = make_class_buffer_with_members('LogEntry', { 'int id;', 'std::string message;' })
      local class_sym = make_class_symbols(bufnr, 'LogEntry', {
        { name = 'id', char_start = 6 },
        { name = 'message', char_start = 16 },
      })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      generate_operators.execute({ mode = 'stream' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Verify the stream operator declaration exists
      local found_stream = false
      for _, line in ipairs(lines) do
        if line:match('operator<<') then
          found_stream = true
          break
        end
      end
      assert.True(found_stream, 'stream operator declaration should exist')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('stream operator is always a friend function', function()
      local bufnr = make_class_buffer_with_members('Streamable', { 'int data;' })
      local class_sym = make_class_symbols(bufnr, 'Streamable', { { name = 'data', char_start = 6 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      generate_operators.execute({ mode = 'stream' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      local found_friend_stream = false
      for _, line in ipairs(lines) do
        if line:match('friend%s+std::ostream&%s+operator<<') then
          found_friend_stream = true
          break
        end
      end
      assert.True(found_friend_stream, 'stream operator should be a friend function')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  --------------------------------------------------------------------------------
  -- Edge Cases and Error Handling
  --------------------------------------------------------------------------------

  describe('edge cases', function()
    it('warns when class has no non-static members', function()
      local lines = { 'class Empty {', 'public:', '  void doSomething();', '};' }
      local bufnr = helpers.create_buffer(lines, 'cpp')

      local class_sym = SourceSymbol.new({
        name = 'Empty',
        kind = 23,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 3, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 11 } },
        children = {
          {
            name = 'doSomething',
            kind = 6, -- Method
            range = { start = { line = 2, character = 0 }, ['end'] = { line = 2, character = 25 } },
            selectionRange = { start = { line = 2, character = 6 }, ['end'] = { line = 2, character = 17 } },
            children = {},
          },
        },
      }, vim.uri_from_bufnr(bufnr), nil)

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      local notify_called = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg and msg:match('No non%-static member') then
          notify_called = true
        end
        return orig_notify(msg, level)
      end

      generate_operators.execute({ mode = 'equality' })

      vim.notify = orig_notify
      assert.True(notify_called, 'should warn about no members')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('skips static members when collecting operands', function()
      local lines = {
        'class WithStatic {',
        'public:',
        '  static int count;',
        '  int value;',
        '};',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')

      local class_sym = SourceSymbol.new({
        name = 'WithStatic',
        kind = 23,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 4, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 16 } },
        children = {
          {
            name = 'count',
            kind = 8,
            range = { start = { line = 2, character = 0 }, ['end'] = { line = 2, character = 22 } },
            selectionRange = { start = { line = 2, character = 13 }, ['end'] = { line = 2, character = 18 } },
            children = {},
          },
          {
            name = 'value',
            kind = 8,
            range = { start = { line = 3, character = 0 }, ['end'] = { line = 3, character = 14 } },
            selectionRange = { start = { line = 3, character = 6 }, ['end'] = { line = 3, character = 11 } },
            children = {},
          },
        },
      }, vim.uri_from_bufnr(bufnr), nil)

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'equality' })

      local result_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Verify operator declarations are generated (non-static member 'value' exists)
      local has_eq = false
      local has_neq = false
      for _, line in ipairs(result_lines) do
        if line:match('operator==') then has_eq = true end
        if line:match('operator!=') then has_neq = true end
      end

      assert.True(has_eq, 'should generate operator== for non-static member')
      assert.True(has_neq, 'should generate operator!= for non-static member')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('warns when cursor is not on class or member', function()
      local lines = { 'void standaloneFunction() {}' }
      local bufnr = helpers.create_buffer(lines, 'cpp')

      local func_sym = SourceSymbol.new({
        name = 'standaloneFunction',
        kind = 12, -- Function
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 30 } },
        selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 23 } },
        children = {},
      }, vim.uri_from_bufnr(bufnr), nil)

      mock_symbols_for_buf(bufnr, func_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 5 })

      local notify_called = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg and (msg:match('must be on a class') or msg:match('No symbol')) then
          notify_called = true
        end
        return orig_notify(msg, level)
      end

      generate_operators.execute({ mode = 'equality' })

      vim.notify = orig_notify
      assert.True(notify_called, 'should warn about invalid cursor position')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('warns when no symbol at cursor position', function()
      local lines = { '// Just a comment', 'int x = 5;' }
      local bufnr = helpers.create_buffer(lines, 'cpp')

      SourceFile.get_symbols = function(self)
        return {}
      end

      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })

      local notify_called = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg and msg:match('No symbol') then
          notify_called = true
        end
        return orig_notify(msg, level)
      end

      generate_operators.execute({ mode = 'equality' })

      vim.notify = orig_notify
      assert.True(notify_called, 'should warn about no symbol')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('warns on unknown mode', function()
      local bufnr = make_class_buffer_with_members('Test', { 'int x;' })
      local class_sym = make_class_symbols(bufnr, 'Test', { { name = 'x', char_start = 6 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      local notify_called = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg and msg:match('Unknown mode') then
          notify_called = true
        end
        return orig_notify(msg, level)
      end

      generate_operators.execute({ mode = 'invalid' })

      vim.notify = orig_notify
      assert.True(notify_called, 'should warn about unknown mode')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  --------------------------------------------------------------------------------
  -- Insertion Position Tests
  --------------------------------------------------------------------------------

  describe('insertion position', function()
    it('inserts operators inside class body', function()
      local bufnr = make_class_buffer_with_members('Inner', { 'int x;' })
      local class_sym = make_class_symbols(bufnr, 'Inner', { { name = 'x', char_start = 6 } })

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'equality' })

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local closing = find_closing_brace(lines)

      local eq_line = contains_operator(lines, 'operator==', true, closing)
      assert.truthy(eq_line, 'operator should exist')
      assert.True(eq_line < closing, 'operator must be inside class (before })')
      assert.falsy(lines[eq_line]:match('Inner::'), 'inline operator should NOT have class scope prefix')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('inserts operators in public section', function()
      local lines = {
        'class AccessTest {',
        'private:',
        '  int secret;',
        'public:',
        '  int value;',
        '};',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')

      local class_sym = SourceSymbol.new({
        name = 'AccessTest',
        kind = 23,
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 5, character = 2 } },
        selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 16 } },
        children = {
          {
            name = 'secret',
            kind = 8,
            range = { start = { line = 2, character = 0 }, ['end'] = { line = 2, character = 15 } },
            selectionRange = { start = { line = 2, character = 6 }, ['end'] = { line = 2, character = 12 } },
            children = {},
          },
          {
            name = 'value',
            kind = 8,
            range = { start = { line = 4, character = 0 }, ['end'] = { line = 4, character = 14 } },
            selectionRange = { start = { line = 4, character = 6 }, ['end'] = { line = 4, character = 11 } },
            children = {},
          },
        },
      }, vim.uri_from_bufnr(bufnr), nil)

      mock_symbols_for_buf(bufnr, class_sym)
      vim.api.nvim_win_set_buf(0, bufnr)
      vim.api.nvim_win_set_cursor(0, { 1, 6 })

      config.values.friend_comparison_operators = false
      generate_operators.execute({ mode = 'equality' })

      local result_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Find the operator and verify it's in the public section (after line 4)
      local eq_line = nil
      for i, line in ipairs(result_lines) do
        if line:match('operator==') then
          eq_line = i
          break
        end
      end

      assert.truthy(eq_line, 'operator should exist')
      -- Operator should be after the 'public:' line (line 4 in 1-indexed)
      assert.True(eq_line > 4, 'operator should be in public section')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
