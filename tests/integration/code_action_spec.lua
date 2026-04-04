local helpers = require('tests.helpers')
local code_action = require('cmantic.code_action')

local function has_action(actions, id)
  for _, a in ipairs(actions) do
    if a.id == id then return true end
  end
  return false
end

local function load_fixture_buf(name, ft)
  local cwd = vim.fn.getcwd()
  local fname = cwd .. '/tests/fixtures/' .. name
  local bufnr = vim.fn.bufadd(fname)
  vim.fn.bufload(bufnr)
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
  end)
end)
