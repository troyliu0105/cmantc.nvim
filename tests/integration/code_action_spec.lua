local helpers = require('tests.helpers')
local code_action = require('cmantic.code_action')
local SourceFile = require('cmantic.source_file')
local header_source = require('cmantic.header_source')

local function has_action(actions, id)
  for _, a in ipairs(actions) do
    if a.id == id then return true end
  end
  return false
end

local function find_action(actions, id)
  for _, a in ipairs(actions) do
    if a.id == id then return a end
  end
  return nil
end

local function load_fixture_buf(name, ft)
  local cwd = vim.fn.getcwd()
  local fname = cwd .. '/tests/fixtures/' .. name
  -- Check if buffer already exists, reuse it to avoid E95
  local existing = vim.fn.bufnr(fname)
  if existing > 0 and vim.api.nvim_buf_is_loaded(existing) then
    vim.bo[existing].filetype = ft or 'cpp'
    return existing
  end
  -- Suppress swapfile warnings and use bufadd to find/create buffer
  local prev_swapfile = vim.o.swapfile
  vim.o.swapfile = false
  local bufnr = vim.fn.bufadd(fname)
  vim.fn.bufload(bufnr)
  vim.o.swapfile = prev_swapfile
  vim.bo[bufnr].filetype = ft or 'cpp'
  return bufnr
end

local function get_actions(bufnr, position)
  return code_action.get_applicable_actions(bufnr, {
    range = {
      start = position or { line = 0, character = 0 },
      ['end'] = position or { line = 0, character = 0 },
    },
  })
end

local orig_get_clients = vim.lsp.get_clients
local orig_exec_provider = SourceFile.execute_source_symbol_provider
local orig_get_matching = header_source.get_matching

local function setup_symbol_buffer(lines, filename, raw_symbols)
  vim.fn.mkdir('/tmp/cmantic_test', 'p')
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_name(bufnr, '/tmp/cmantic_test/' .. filename)
  vim.bo[bufnr].filetype = 'cpp'
  vim.api.nvim_set_current_buf(bufnr)

  vim.lsp.get_clients = function()
    return { { name = 'clangd' } }
  end

  SourceFile.execute_source_symbol_provider = function()
    return raw_symbols
  end

  header_source.get_matching = function()
    return nil
  end

  return bufnr, { bufnr = bufnr }
end

local function teardown_mocks(mocks)
  vim.lsp.get_clients = orig_get_clients
  SourceFile.execute_source_symbol_provider = orig_exec_provider
  header_source.get_matching = orig_get_matching
  header_source.clear_cache()
  if mocks and mocks.bufnr then
    pcall(vim.api.nvim_buf_delete, mocks.bufnr, { force = true })
  end
end

describe('code_action', function()
  describe('addInclude is always available', function()
    it('offers Add Include for unnamed buffer', function()
      local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
      local actions = get_actions(bufnr)
      assert.is_true(has_action(actions, 'addInclude'))
    end)

    it('returns table for Lua file without error', function()
      local bufnr = helpers.create_buffer({ 'local x = 1' }, 'lua')
      local actions = get_actions(bufnr)
      assert.is_true(type(actions) == 'table')
    end)
  end)

  describe('empty header file', function()
    it('offers Add Header Guard action', function()
      local bufnr = load_fixture_buf('c++/empty_header.h', 'c')
      local actions = get_actions(bufnr)
      assert.is_true(has_action(actions, 'addHeaderGuard'))
    end)

    it('offers Add Include action', function()
      local bufnr = load_fixture_buf('c++/empty_header.h', 'c')
      local actions = get_actions(bufnr)
      assert.is_true(has_action(actions, 'addInclude'))
    end)
  end)

  describe('guarded header file', function()
    it('offers Amend Header Guard action', function()
      local bufnr = load_fixture_buf('c++/guarded_header.h', 'c')
      local actions = get_actions(bufnr)
      assert.is_true(has_action(actions, 'amendHeaderGuard'))
    end)

    it('does NOT offer Add Header Guard (already has one)', function()
      local bufnr = load_fixture_buf('c++/guarded_header.h', 'c')
      local actions = get_actions(bufnr)
      assert.is_false(has_action(actions, 'addHeaderGuard'))
    end)
  end)

  describe('source file', function()
    it('offers Add Include but not Header Guard', function()
      local bufnr = load_fixture_buf('c++/function_defs.cpp', 'cpp')
      local actions = get_actions(bufnr)
      assert.is_true(has_action(actions, 'addInclude'))
      assert.is_false(has_action(actions, 'addHeaderGuard'))
      assert.is_false(has_action(actions, 'amendHeaderGuard'))
    end)
  end)

  describe('action metadata', function()
    it('exposes metadata and callbacks for every action', function()
      local bufnr = load_fixture_buf('c++/guarded_header.h', 'c')
      local actions = get_actions(bufnr)
      for _, action in ipairs(actions) do
        assert.is_true(type(action.id) == 'string' and action.id ~= '')
        assert.is_true(type(action.title) == 'string' and action.title ~= '')
        assert.is_true(type(action.kind) == 'string' and action.kind ~= '')
        assert.is_true(type(action.execute_fn) == 'function')
      end
    end)

    it('ensures addInclude action has expected metadata', function()
      local bufnr = load_fixture_buf('c++/guarded_header.h', 'c')
      local actions = get_actions(bufnr)
      local add_include
      for _, action in ipairs(actions) do
        if action.id == 'addInclude' then
          add_include = action
          break
        end
      end
      assert.is_not_nil(add_include)
      assert.are.equal('addInclude', add_include.id)
      assert.is_true(type(add_include.title) == 'string' and add_include.title ~= '')
      assert.is_true(type(add_include.kind) == 'string' and add_include.kind ~= '')
      assert.is_true(type(add_include.execute_fn) == 'function')
    end)

    it('should have correct title for AddDefinition action', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    void bar();',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5, -- Class
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'bar', kind = 6, -- Method
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 16 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 12 } },
              children = {},
              detail = 'void (int)',
            },
          },
          detail = '',
        },
      })
      local actions = get_actions(bufnr, { line = 1, character = 9 })
      local action = find_action(actions, 'addDefinitionInline')
      assert.is_not_nil(action)
      assert.are.equal('Add Definition in this file', action.title)
      teardown_mocks(mocks)
    end)

    it('should have correct title for GenerateGetterSetter action', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    int value_;',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5, -- Class
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'value_', kind = 8, -- Field
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 15 } },
              selectionRange = { start = { line = 1, character = 8 }, ['end'] = { line = 1, character = 14 } },
              children = {},
              detail = 'int',
            },
          },
          detail = '',
        },
      })
      local actions = get_actions(bufnr, { line = 1, character = 8 })
      local action = find_action(actions, 'generateGetterSetter')
      assert.is_not_nil(action)
      assert.are.equal('Generate Getter and Setter for "value_"', action.title)
      teardown_mocks(mocks)
    end)

    it('should have correct title for GenerateOperators action', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5, -- Class
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {},
          detail = '',
        },
      })
      local actions = get_actions(bufnr, { line = 0, character = 6 })
      local action = find_action(actions, 'generateEqualityOperators')
      assert.is_not_nil(action)
      assert.are.equal('Generate Equality Operators for "Foo"', action.title)
      teardown_mocks(mocks)
    end)
  end)

  describe('action detection for function declaration in header', function()
    it('should offer AddDefinition action when cursor is on function declaration in header', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    void bar();',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5, -- Class
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'bar', kind = 6, -- Method
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 16 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 12 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })
      local actions = get_actions(bufnr, { line = 1, character = 9 })
      assert.is_true(has_action(actions, 'addDefinitionInline'))
      assert.is_false(has_action(actions, 'addDefinitionMatching'))
      teardown_mocks(mocks)
    end)

    it('should offer MoveDefinition action for inline function definition in header', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    void bar() {}',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5, -- Class
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'bar', kind = 6, -- Method
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 19 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 12 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })
      local actions = get_actions(bufnr, { line = 1, character = 9 })
      assert.is_true(has_action(actions, 'moveDefinitionInOutOfClass'))
      teardown_mocks(mocks)
    end)
  end)

  describe('action detection for function definition in source', function()
    it('should offer AddDeclarationInClass action for function definition inside class in source file', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    void bar() {}',
        '};',
      }, 'test_cls.cpp', {
        {
          name = 'Foo', kind = 5, -- Class
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'bar', kind = 6, -- Method
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 19 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 12 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })
      local actions = get_actions(bufnr, { line = 1, character = 9 })
      assert.is_true(has_action(actions, 'addDeclarationInClass'))
      teardown_mocks(mocks)
    end)
  end)

  describe('action detection for member variable', function()
    it('should offer GenerateGetterSetter when cursor is on member variable inside class', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    int value_;',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5, -- Class
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'value_', kind = 8, -- Field
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 15 } },
              selectionRange = { start = { line = 1, character = 8 }, ['end'] = { line = 1, character = 14 } },
              children = {},
              detail = 'int',
            },
          },
          detail = '',
        },
      })
      local actions = get_actions(bufnr, { line = 1, character = 8 })
      assert.is_true(has_action(actions, 'generateGetter'))
      assert.is_true(has_action(actions, 'generateSetter'))
      assert.is_true(has_action(actions, 'generateGetterSetter'))
      teardown_mocks(mocks)
    end)

    it('should NOT offer GenerateGetterSetter when cursor is on free variable', function()
      local bufnr, mocks = setup_symbol_buffer({
        'int x = 0;',
      }, 'test_src.cpp', {
        {
          name = 'x', kind = 13, -- Variable
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 10 } },
          selectionRange = { start = { line = 0, character = 4 }, ['end'] = { line = 0, character = 5 } },
          children = {},
          detail = 'int',
        },
      })
      local actions = get_actions(bufnr, { line = 0, character = 4 })
      assert.is_false(has_action(actions, 'generateGetter'))
      assert.is_false(has_action(actions, 'generateSetter'))
      assert.is_false(has_action(actions, 'generateGetterSetter'))
      teardown_mocks(mocks)
    end)
  end)

  describe('action detection for class/struct', function()
    it('should offer GenerateOperators when cursor is on class symbol', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5, -- Class
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {},
          detail = '',
        },
      })
      local actions = get_actions(bufnr, { line = 0, character = 6 })
      assert.is_true(has_action(actions, 'generateEqualityOperators'))
      assert.is_true(has_action(actions, 'generateRelationalOperators'))
      assert.is_true(has_action(actions, 'generateStreamOperator'))
      teardown_mocks(mocks)
    end)

    it('should offer GenerateOperators when cursor is on struct symbol', function()
      local bufnr, mocks = setup_symbol_buffer({
        'struct Point {',
        '    int x;',
        '    int y;',
        '};',
      }, 'test_struct.h', {
        {
          name = 'Point', kind = 23, -- Struct
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 3, character = 1 } },
          selectionRange = { start = { line = 0, character = 7 }, ['end'] = { line = 0, character = 12 } },
          children = {
            {
              name = 'x', kind = 8, -- Field
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 9 } },
              selectionRange = { start = { line = 1, character = 8 }, ['end'] = { line = 1, character = 9 } },
              children = {},
              detail = 'int',
            },
            {
              name = 'y', kind = 8, -- Field
              range = { start = { line = 2, character = 4 }, ['end'] = { line = 2, character = 9 } },
              selectionRange = { start = { line = 2, character = 8 }, ['end'] = { line = 2, character = 9 } },
              children = {},
              detail = 'int',
            },
          },
          detail = '',
        },
      })
      local actions = get_actions(bufnr, { line = 0, character = 7 })
      assert.is_true(has_action(actions, 'generateEqualityOperators'))
      assert.is_true(has_action(actions, 'generateRelationalOperators'))
      assert.is_true(has_action(actions, 'generateStreamOperator'))
      teardown_mocks(mocks)
    end)
  end)

  describe('execute_by_id', function()
    it('should execute matching action execute_fn', function()
      local executed = false
      local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
      local orig_fn = code_action.get_applicable_actions
      code_action.get_applicable_actions = function()
        return {
          {
            id = 'testAction',
            title = 'Test Action',
            kind = 'refactor',
            execute_fn = function()
              executed = true
            end,
          },
        }
      end

      local orig_get_buf = vim.api.nvim_get_current_buf
      local orig_get_cursor = vim.api.nvim_win_get_cursor
      vim.api.nvim_get_current_buf = function() return bufnr end
      vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

      code_action.execute_by_id('testAction')
      assert.is_true(executed)

      code_action.get_applicable_actions = orig_fn
      vim.api.nvim_get_current_buf = orig_get_buf
      vim.api.nvim_win_get_cursor = orig_get_cursor
    end)

    it('should notify when action not found for invalid ID', function()
      local notified = false
      local notified_msg = ''
      local orig_fn = code_action.get_applicable_actions
      code_action.get_applicable_actions = function()
        return {
          {
            id = 'someAction',
            title = 'Some Action',
            kind = 'refactor',
            execute_fn = function() end,
          },
        }
      end

      local orig_get_buf = vim.api.nvim_get_current_buf
      local orig_get_cursor = vim.api.nvim_win_get_cursor
      local orig_notify = vim.notify
      vim.api.nvim_get_current_buf = function() return 0 end
      vim.api.nvim_win_get_cursor = function() return { 1, 0 } end
      vim.notify = function(msg, level)
        notified = true
        notified_msg = msg
      end

      code_action.execute_by_id('nonexistentAction')
      assert.is_true(notified)
      assert.is_true(notified_msg:find('nonexistentAction') ~= nil)

      code_action.get_applicable_actions = orig_fn
      vim.api.nvim_get_current_buf = orig_get_buf
      vim.api.nvim_win_get_cursor = orig_get_cursor
      vim.notify = orig_notify
    end)
  end)

  describe('_has_method', function()
    local SourceSymbol = require('cmantic.source_symbol')

    it('should return true when method exists in class children', function()
      local class_sym = SourceSymbol.new({
        name = 'MyClass',
        kind = 5, -- Class
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 5, character = 1 },
        },
        selectionRange = {
          start = { line = 0, character = 6 },
          ['end'] = { line = 0, character = 13 },
        },
        children = {
          {
            name = 'getValue',
            kind = 6, -- Method
            range = {
              start = { line = 1, character = 4 },
              ['end'] = { line = 1, character = 20 },
            },
            selectionRange = {
              start = { line = 1, character = 8 },
              ['end'] = { line = 1, character = 16 },
            },
            children = {},
            detail = 'int ()',
          },
        },
      }, 'file:///test.h', nil)

      assert.is_true(code_action._has_method(class_sym, 'getValue'))
    end)

    it('should return false when method not found', function()
      local class_sym = SourceSymbol.new({
        name = 'MyClass',
        kind = 5, -- Class
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 2, character = 1 },
        },
        selectionRange = {
          start = { line = 0, character = 6 },
          ['end'] = { line = 0, character = 13 },
        },
        children = {
          {
            name = 'getValue',
            kind = 6, -- Method
            range = {
              start = { line = 1, character = 4 },
              ['end'] = { line = 1, character = 20 },
            },
            selectionRange = {
              start = { line = 1, character = 8 },
              ['end'] = { line = 1, character = 16 },
            },
            children = {},
            detail = 'int ()',
          },
        },
      }, 'file:///test.h', nil)

      assert.is_false(code_action._has_method(class_sym, 'setValue'))
    end)

    it('should return false when class has no children', function()
      local class_sym = SourceSymbol.new({
        name = 'EmptyClass',
        kind = 5, -- Class
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 1, character = 1 },
        },
        selectionRange = {
          start = { line = 0, character = 6 },
          ['end'] = { line = 0, character = 16 },
        },
        children = {},
      }, 'file:///test.h', nil)

      assert.is_false(code_action._has_method(class_sym, 'anyMethod'))
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: Action detection — matching source file
  --------------------------------------------------------------------------------

  describe('action detection — matching source file', function()
    it('should offer addDefinitionMatching when header has matching source file', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    void bar();',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'bar', kind = 6,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 16 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 12 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })
      -- Mock matching source file exists
      header_source.get_matching = function() return 'file:///tmp/cmantic_test/test_cls.cpp' end

      local actions = get_actions(bufnr, { line = 1, character = 9 })
      assert.is_true(has_action(actions, 'addDefinitionMatching'))
      teardown_mocks(mocks)
    end)

    it('should NOT offer addDefinitionMatching when header has NO matching source file', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    void bar();',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'bar', kind = 6,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 16 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 12 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })
      -- Mock no matching source file
      header_source.get_matching = function() return nil end

      local actions = get_actions(bufnr, { line = 1, character = 9 })
      assert.is_false(has_action(actions, 'addDefinitionMatching'))
      teardown_mocks(mocks)
    end)

    it('should offer addDeclaration when source file has matching header', function()
      local bufnr, mocks = setup_symbol_buffer({
        'void Foo::bar() {',
        '}',
      }, 'test_cls.cpp', {
        {
          name = 'bar', kind = 6,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 1 } },
          selectionRange = { start = { line = 0, character = 10 }, ['end'] = { line = 0, character = 13 } },
          children = {},
          detail = 'void ()',
        },
      })
      -- Mock matching header file exists
      header_source.get_matching = function() return 'file:///tmp/cmantic_test/test_cls.h' end

      local actions = get_actions(bufnr, { line = 0, character = 10 })
      assert.is_true(has_action(actions, 'addDeclaration'))
      teardown_mocks(mocks)
    end)

    it('should handle gracefully when source file has NO matching header', function()
      local bufnr, mocks = setup_symbol_buffer({
        'void Foo::bar() {',
        '}',
      }, 'test_cls.cpp', {
        {
          name = 'bar', kind = 6,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 1 } },
          selectionRange = { start = { line = 0, character = 10 }, ['end'] = { line = 0, character = 13 } },
          children = {},
          detail = 'void ()',
        },
      })
      -- Mock no matching header file
      header_source.get_matching = function() return nil end

      local actions = get_actions(bufnr, { line = 0, character = 10 })
      -- Should not crash, may still offer other actions
      assert.is_true(type(actions) == 'table')
      teardown_mocks(mocks)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: Action detection — special function types
  --------------------------------------------------------------------------------

  describe('action detection — special function types', function()
    it('should offer AddDefinition with correct title for constructor declaration', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    Foo(int x);',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'Foo', kind = 9, -- Constructor
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 15 } },
              selectionRange = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 7 } },
              children = {},
              detail = 'void (int)',
            },
          },
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 1, character = 4 })
      local action = find_action(actions, 'addDefinitionInline')
      assert.is_not_nil(action)
      assert.is_not_nil(action.title:find('Constructor'))
      teardown_mocks(mocks)
    end)

    it('should NOT offer AddDefinition for destructor declaration', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    ~Foo();',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = '~Foo', kind = 9, -- Constructor (clangd uses same kind for dtor)
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 11 } },
              selectionRange = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 8 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 1, character = 4 })
      -- Destructors should not offer AddDefinition
      assert.is_false(has_action(actions, 'addDefinitionInline'))
      assert.is_false(has_action(actions, 'addDefinitionMatching'))
      teardown_mocks(mocks)
    end)

    it('should NOT offer AddDefinition for = delete function', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    Foo(const Foo&) = delete;',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'Foo', kind = 6,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 30 } },
              selectionRange = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 7 } },
              children = {},
              detail = 'void (const Foo &)',
            },
          },
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 1, character = 4 })
      -- = delete functions should not offer AddDefinition
      assert.is_false(has_action(actions, 'addDefinitionInline'))
      teardown_mocks(mocks)
    end)

    it('should NOT offer AddDefinition for = default function', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    Foo() = default;',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'Foo', kind = 9,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 22 } },
              selectionRange = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 7 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 1, character = 4 })
      -- = default functions should not offer AddDefinition
      assert.is_false(has_action(actions, 'addDefinitionInline'))
      teardown_mocks(mocks)
    end)

    it('should NOT offer AddDefinition for pure virtual function', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Base {',
        '    virtual void foo() = 0;',
        '};',
      }, 'test_base.h', {
        {
          name = 'Base', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 10 } },
          children = {
            {
              name = 'foo', kind = 6,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 28 } },
              selectionRange = { start = { line = 1, character = 17 }, ['end'] = { line = 1, character = 20 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 1, character = 17 })
      -- Pure virtual functions should not offer AddDefinition
      assert.is_false(has_action(actions, 'addDefinitionInline'))
      assert.is_false(has_action(actions, 'addDefinitionMatching'))
      teardown_mocks(mocks)
    end)

    it('should offer AddDefinition for static method declaration', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    static void bar();',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'bar', kind = 6,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 23 } },
              selectionRange = { start = { line = 1, character = 16 }, ['end'] = { line = 1, character = 19 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 1, character = 16 })
      -- Static methods should still offer AddDefinition
      assert.is_true(has_action(actions, 'addDefinitionInline'))
      teardown_mocks(mocks)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: Action detection — operator overloads
  --------------------------------------------------------------------------------

  describe('action detection — operator overloads', function()
    it('should still offer generateEqualityOperators even if operator== exists', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    bool operator==(const Foo&) const;',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'operator==', kind = 6,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 41 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 19 } },
              children = {},
              detail = 'bool (const Foo &) const',
            },
          },
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 0, character = 6 })
      -- Note: Current implementation doesn't check for existing operators
      -- This test documents the current behavior
      assert.is_true(has_action(actions, 'generateEqualityOperators'))
      teardown_mocks(mocks)
    end)

    it('should offer operators for class with no members', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class EmptyClass {',
        '};',
      }, 'test_empty.h', {
        {
          name = 'EmptyClass', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 16 } },
          children = {},
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 0, character = 6 })
      -- Operators should still be offered for empty classes (edge case)
      assert.is_true(has_action(actions, 'generateEqualityOperators'))
      teardown_mocks(mocks)
    end)

    it('should offer operators for class with only static members', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class StaticOnly {',
        '    static int count;',
        '};',
      }, 'test_static.h', {
        {
          name = 'StaticOnly', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 15 } },
          children = {
            {
              name = 'count', kind = 8,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 21 } },
              selectionRange = { start = { line = 1, character = 15 }, ['end'] = { line = 1, character = 20 } },
              children = {},
              detail = 'int',
            },
          },
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 0, character = 6 })
      -- Operators should still be offered (current behavior doesn't filter static-only classes)
      assert.is_true(has_action(actions, 'generateEqualityOperators'))
      teardown_mocks(mocks)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: _add_bulk_definitions_action
  --------------------------------------------------------------------------------

  describe('_add_bulk_definitions_action', function()
    it('should offer addDefinitionsBulk for header with multiple declarations', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    void foo();',
        '    void bar();',
        '    void baz();',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 4, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'foo', kind = 6,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 16 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 12 } },
              children = {},
              detail = 'void ()',
            },
            {
              name = 'bar', kind = 6,
              range = { start = { line = 2, character = 4 }, ['end'] = { line = 2, character = 16 } },
              selectionRange = { start = { line = 2, character = 9 }, ['end'] = { line = 2, character = 12 } },
              children = {},
              detail = 'void ()',
            },
            {
              name = 'baz', kind = 6,
              range = { start = { line = 3, character = 4 }, ['end'] = { line = 3, character = 16 } },
              selectionRange = { start = { line = 3, character = 9 }, ['end'] = { line = 3, character = 12 } },
              children = {},
              detail = 'void ()',
            },
          },
          detail = '',
        },
      })

      local actions = get_actions(bufnr, { line = 0, character = 6 })
      assert.is_true(has_action(actions, 'addDefinitionsBulk'))
      teardown_mocks(mocks)
    end)

    it('should NOT offer addDefinitionsBulk for source file', function()
      local bufnr, mocks = setup_symbol_buffer({
        'void foo() {}',
      }, 'test_src.cpp', {
        {
          name = 'foo', kind = 6,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } },
          selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 8 } },
          children = {},
          detail = 'void ()',
        },
      })

      local actions = get_actions(bufnr, { line = 0, character = 5 })
      assert.is_false(has_action(actions, 'addDefinitionsBulk'))
      teardown_mocks(mocks)
    end)

    it('should still offer addDefinitionsBulk for header with no declarations', function()
      -- Note: Current implementation offers bulk action for all headers
      -- This test documents current behavior
      local bufnr, mocks = setup_symbol_buffer({
        '// Empty header',
      }, 'test_empty.h', {})

      local actions = get_actions(bufnr, { line = 0, character = 0 })
      -- Bulk action is offered for all headers per current implementation
      assert.is_true(has_action(actions, 'addDefinitionsBulk'))
      teardown_mocks(mocks)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: UpdateSignature action
  --------------------------------------------------------------------------------

  describe('UpdateSignature action', function()
    it('should offer UpdateSignature when signature tracking detects change', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    void bar(int x, int y);',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'bar', kind = 6,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 28 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 12 } },
              children = {},
              detail = 'void (int, int)',
            },
          },
          detail = '',
        },
      })

      -- Simulate signature change detection
      code_action._signature_changed = true
      code_action._previous_signature = { name = 'bar', params = '(int x)' }

      local actions = get_actions(bufnr, { line = 1, character = 9 })
      -- When signature_changed is true, should offer update action
      assert.is_true(has_action(actions, 'updateFunctionDefinition'))

      -- Reset state
      code_action._signature_changed = false
      code_action._previous_signature = nil
      teardown_mocks(mocks)
    end)

    it('should NOT offer UpdateSignature when signature unchanged', function()
      local bufnr, mocks = setup_symbol_buffer({
        'class Foo {',
        '    void bar(int x);',
        '};',
      }, 'test_cls.h', {
        {
          name = 'Foo', kind = 5,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 1 } },
          selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 9 } },
          children = {
            {
              name = 'bar', kind = 6,
              range = { start = { line = 1, character = 4 }, ['end'] = { line = 1, character = 22 } },
              selectionRange = { start = { line = 1, character = 9 }, ['end'] = { line = 1, character = 12 } },
              children = {},
              detail = 'void (int)',
            },
          },
          detail = '',
        },
      })

      -- Ensure signature change flag is false
      code_action._signature_changed = false

      local actions = get_actions(bufnr, { line = 1, character = 9 })
      assert.is_false(has_action(actions, 'updateFunctionDefinition'))
      assert.is_false(has_action(actions, 'updateFunctionDeclaration'))
      teardown_mocks(mocks)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: Error paths
  --------------------------------------------------------------------------------

  describe('error paths', function()
    it('should return empty table for nil bufnr without crashing', function()
      local actions = code_action.get_applicable_actions(nil, {
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
      })
      assert.is_true(type(actions) == 'table')
      assert.are.equal(0, #actions)
    end)

    it('should handle unloaded buffer without crashing', function()
      local bufnr = vim.api.nvim_create_buf(false, false)
      -- Don't load the buffer
      local actions = code_action.get_applicable_actions(bufnr, {
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
      })
      assert.is_true(type(actions) == 'table')
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)

    it('should notify and not crash when execute_by_id called with empty action list', function()
      local notified = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        notified = true
      end

      local orig_get_actions = code_action.get_applicable_actions
      code_action.get_applicable_actions = function() return {} end

      local orig_get_buf = vim.api.nvim_get_current_buf
      local orig_get_cursor = vim.api.nvim_win_get_cursor
      vim.api.nvim_get_current_buf = function() return 0 end
      vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

      code_action.execute_by_id('nonexistentAction')
      assert.is_true(notified)

      code_action.get_applicable_actions = orig_get_actions
      vim.api.nvim_get_current_buf = orig_get_buf
      vim.api.nvim_win_get_cursor = orig_get_cursor
      vim.notify = orig_notify
    end)

    it('should handle invalid position gracefully', function()
      local bufnr, mocks = setup_symbol_buffer({
        'int x;',
      }, 'test.cpp', {
        {
          name = 'x', kind = 13,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 7 } },
          selectionRange = { start = { line = 0, character = 4 }, ['end'] = { line = 0, character = 5 } },
          children = {},
          detail = 'int',
        },
      })

      -- Position way outside buffer
      local actions = get_actions(bufnr, { line = 999, character = 999 })
      assert.is_true(type(actions) == 'table')
      teardown_mocks(mocks)
    end)

    it('should handle buffer with no LSP client attached', function()
      local bufnr = helpers.create_buffer({ 'int main() { return 0; }' }, 'cpp')
      -- No LSP client mocked
      vim.lsp.get_clients = function() return {} end

      local actions = get_actions(bufnr)
      assert.is_true(type(actions) == 'table')
      -- Should still have addInclude (source action)
      assert.is_true(has_action(actions, 'addInclude'))
    end)
  end)
end)
