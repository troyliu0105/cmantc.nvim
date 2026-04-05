local eq = assert.are.same
local helpers = require('tests.helpers')

local function get_fresh_module()
  package.loaded['cmantic.code_action_inject'] = nil
  return require('cmantic.code_action_inject')
end

local function mock_cmantic_actions(actions)
  local code_action = require('cmantic.code_action')
  local orig = code_action.get_applicable_actions
  code_action.get_applicable_actions = function() return actions end
  return orig
end

local function restore_cmantic_actions(orig)
  require('cmantic.code_action').get_applicable_actions = orig
end

describe('code_action_inject', function()
  local original_code_action
  local original_buf_request_all
  local original_ui_select
  local original_get_clients
  local original_win_get_cursor
  local original_buf_get_current_buf

  before_each(function()
    original_code_action = vim.lsp.buf.code_action
    original_buf_request_all = vim.lsp.buf_request_all
    original_ui_select = vim.ui.select
    original_get_clients = vim.lsp.get_clients
    original_win_get_cursor = vim.api.nvim_win_get_cursor
    original_buf_get_current_buf = vim.api.nvim_get_current_buf
  end)

  after_each(function()
    vim.lsp.buf.code_action = original_code_action
    vim.lsp.buf_request_all = original_buf_request_all
    vim.ui.select = original_ui_select
    vim.lsp.get_clients = original_get_clients
    vim.api.nvim_win_get_cursor = original_win_get_cursor
    vim.api.nvim_get_current_buf = original_buf_get_current_buf
    package.loaded['cmantic.code_action_inject'] = nil
  end)

  describe('enable()', function()
    it('sets active=true', function()
      local M = get_fresh_module()
      assert.is_false(M.is_active())
      M.enable()
      assert.is_true(M.is_active())
    end)

    it('patches vim.lsp.buf.code_action', function()
      local M = get_fresh_module()
      local original = vim.lsp.buf.code_action
      M.enable()
      assert.is_not_equal(original, vim.lsp.buf.code_action)
    end)

    it('is idempotent (calling twice does not double-patch)', function()
      local M = get_fresh_module()
      M.enable()
      local first_patched = vim.lsp.buf.code_action
      M.enable()
      assert.are.equal(first_patched, vim.lsp.buf.code_action)
    end)
  end)

  describe('disable()', function()
    it('restores original vim.lsp.buf.code_action', function()
      local M = get_fresh_module()
      local original = vim.lsp.buf.code_action
      M.enable()
      local patched = vim.lsp.buf.code_action
      assert.is_not_equal(original, patched)
      M.disable()
      assert.are.equal(original, vim.lsp.buf.code_action)
    end)

    it('sets active=false', function()
      local M = get_fresh_module()
      M.enable()
      assert.is_true(M.is_active())
      M.disable()
      assert.is_false(M.is_active())
    end)

    it('is safe to call when not enabled', function()
      local M = get_fresh_module()
      local original = vim.lsp.buf.code_action
      M.disable()
      assert.are.equal(original, vim.lsp.buf.code_action)
      assert.is_false(M.is_active())
    end)
  end)

  describe('is_active()', function()
    it('returns false initially', function()
      local M = get_fresh_module()
      assert.is_false(M.is_active())
    end)

    it('returns true after enable()', function()
      local M = get_fresh_module()
      M.enable()
      assert.is_true(M.is_active())
    end)

    it('returns false after disable()', function()
      local M = get_fresh_module()
      M.enable()
      M.disable()
      assert.is_false(M.is_active())
    end)
  end)

  describe('non-C/C++ filetypes passthrough', function()
    it('calls original for lua filetype', function()
      local M = get_fresh_module()
      local bufnr = helpers.create_buffer({ 'local x = 1' }, 'lua')
      vim.api.nvim_get_current_buf = function() return bufnr end

      local called_with = nil
      vim.lsp.buf.code_action = function(opts) called_with = opts end

      M.enable()
      vim.lsp.buf.code_action({ filter = function() return true end })

      assert.is_not_nil(called_with)
      assert.is_true(called_with.filter ~= nil)
    end)

    it('calls original for python filetype', function()
      local M = get_fresh_module()
      local bufnr = helpers.create_buffer({ 'x = 1' }, 'python')
      vim.api.nvim_get_current_buf = function() return bufnr end

      local called = false
      vim.lsp.buf.code_action = function() called = true end

      M.enable()
      vim.lsp.buf.code_action({})

      assert.is_true(called)
    end)

    it('calls original for rust filetype', function()
      local M = get_fresh_module()
      local bufnr = helpers.create_buffer({ 'fn main() {}' }, 'rust')
      vim.api.nvim_get_current_buf = function() return bufnr end

      local called = false
      vim.lsp.buf.code_action = function() called = true end

      M.enable()
      vim.lsp.buf.code_action({})

      assert.is_true(called)
    end)
  end)

  describe('C/C++ filetypes with no cmantic actions', function()
    it('passthrough when get_applicable_actions returns empty', function()
      local M = get_fresh_module()
      local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
      vim.api.nvim_get_current_buf = function() return bufnr end
      vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

      local orig_get_actions = mock_cmantic_actions({})

      local called_with = nil
      vim.lsp.buf.code_action = function(opts) called_with = opts end

      M.enable()
      vim.lsp.buf.code_action({ range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } } })

      assert.is_not_nil(called_with)

      restore_cmantic_actions(orig_get_actions)
    end)
  end)

  describe('C/C++ filetypes with cmantic actions', function()
    it('merges cmantic and LSP actions into single picker', function()
      local M = get_fresh_module()
      local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
      vim.api.nvim_get_current_buf = function() return bufnr end
      vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

      local orig_get_actions = mock_cmantic_actions({
        { id = 'cmantic1', title = 'Cmantic Action', kind = 'refactor' },
      })

      vim.lsp.buf_request_all = function(_, _, _, callback)
        callback({
          [1] = {
            result = {
              { title = 'LSP Action 1', kind = 'quickfix' },
              { title = 'LSP Action 2', kind = 'refactor' },
            },
            context = { client_id = 1, bufnr = bufnr },
          },
        })
      end

      local captured_items = nil
      local captured_opts = nil
      vim.ui.select = function(items, opts)
        captured_items = items
        captured_opts = opts
      end

      local orig_make_range_params = vim.lsp.util.make_range_params
      vim.lsp.util.make_range_params = function() return { context = {} } end
      local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
      vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

      M.enable()
      vim.lsp.buf.code_action({})

      assert.is_not_nil(captured_items)
      assert.is_not_nil(captured_opts)
      assert.are.equal('Code actions:', captured_opts.prompt)
      assert.are.equal('codeaction', captured_opts.kind)

      local cmantic_count = 0
      local lsp_count = 0
      for _, item in ipairs(captured_items) do
        if item._cmantic_id then
          cmantic_count = cmantic_count + 1
        else
          lsp_count = lsp_count + 1
        end
      end
      assert.are.equal(1, cmantic_count)
      assert.are.equal(2, lsp_count)

      restore_cmantic_actions(orig_get_actions)
      vim.lsp.util.make_range_params = orig_make_range_params
      vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
    end)
  end)
end)

describe('to_lsp_items', function()
  it('produces items with action, ctx, and _cmantic_id fields', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'testAction', title = 'Test Action', kind = 'refactor' },
    })

    local captured_items = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(items) captured_items = items end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    assert.is_not_nil(captured_items)
    assert.are.equal(1, #captured_items)

    local item = captured_items[1]
    assert.is_not_nil(item.action)
    eq('Test Action', item.action.title)
    eq('refactor', item.action.kind)
    assert.is_not_nil(item.ctx)
    eq(-1, item.ctx.client_id)
    eq(bufnr, item.ctx.bufnr)
    eq('testAction', item._cmantic_id)

    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)

  it('filters out disabled actions', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'enabledAction', title = 'Enabled', kind = 'refactor' },
      { id = 'disabledAction', title = 'Disabled', kind = 'refactor', disabled = true },
      { id = 'anotherEnabled', title = 'Another', kind = 'refactor' },
    })

    local captured_items = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(items) captured_items = items end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    assert.is_not_nil(captured_items)
    assert.are.equal(2, #captured_items)

    local ids = {}
    for _, item in ipairs(captured_items) do
      table.insert(ids, item._cmantic_id)
    end

    assert.is_true(vim.tbl_contains(ids, 'enabledAction'))
    assert.is_true(vim.tbl_contains(ids, 'anotherEnabled'))
    assert.is_false(vim.tbl_contains(ids, 'disabledAction'))

    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)
end)

describe('format_action', function()
  it('returns raw title for cmantic items', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'test', title = 'Test Action', kind = 'refactor' },
    })

    local captured_opts = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, opts) captured_opts = opts end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    assert.is_not_nil(captured_opts)
    assert.is_not_nil(captured_opts.format_item)

    local cmantic_item = {
      action = { title = 'My Cmantic Action', kind = 'refactor' },
      ctx = { client_id = -1, bufnr = bufnr },
      _cmantic_id = 'testAction',
    }
    eq('My Cmantic Action', captured_opts.format_item(cmantic_item))

    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)

  it('escapes LF in LSP item titles', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'test', title = 'Test', kind = 'refactor' },
    })

    local captured_opts = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, opts) captured_opts = opts end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    local lsp_item = {
      action = { title = 'Fix\nthis\nissue', kind = 'quickfix' },
      ctx = { client_id = 1, bufnr = bufnr },
    }
    eq('Fix\\nthis\\nissue', captured_opts.format_item(lsp_item))

    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)

  it('escapes CRLF in LSP item titles', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'test', title = 'Test', kind = 'refactor' },
    })

    local captured_opts = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, opts) captured_opts = opts end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    local lsp_item = {
      action = { title = 'Fix\r\nthis', kind = 'quickfix' },
      ctx = { client_id = 1, bufnr = bufnr },
    }
    eq('Fix\\r\\nthis', captured_opts.format_item(lsp_item))

    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)

  it('handles mixed CRLF and LF correctly', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'test', title = 'Test', kind = 'refactor' },
    })

    local captured_opts = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, opts) captured_opts = opts end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    local lsp_item = {
      action = { title = 'Line1\r\nLine2\nLine3', kind = 'quickfix' },
      ctx = { client_id = 1, bufnr = bufnr },
    }
    eq('Line1\\r\\nLine2\\nLine3', captured_opts.format_item(lsp_item))

    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)
end)

describe('on_user_choice', function()
  it('calls execute_by_id for cmantic actions', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'addInclude', title = 'Add Include', kind = 'source' },
    })

    local executed_id = nil
    local code_action = require('cmantic.code_action')
    local orig_execute_by_id = code_action.execute_by_id
    code_action.execute_by_id = function(id) executed_id = id end

    local captured_on_choice = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, _, on_choice) captured_on_choice = on_choice end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    local cmantic_choice = {
      action = { title = 'Add Include', kind = 'source' },
      ctx = { client_id = -1, bufnr = bufnr },
      _cmantic_id = 'addInclude',
    }
    captured_on_choice(cmantic_choice)

    eq('addInclude', executed_id)

    code_action.execute_by_id = orig_execute_by_id
    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)

  it('does nothing for nil choice (user cancelled)', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'test', title = 'Test', kind = 'refactor' },
    })

    local executed = false
    local code_action = require('cmantic.code_action')
    local orig_execute_by_id = code_action.execute_by_id
    code_action.execute_by_id = function() executed = true end

    local captured_on_choice = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, _, on_choice) captured_on_choice = on_choice end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    captured_on_choice(nil)

    assert.is_false(executed)

    code_action.execute_by_id = orig_execute_by_id
    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)

  it('executes LSP command via client:exec_cmd', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'test', title = 'Test', kind = 'refactor' },
    })

    local executed_cmd = nil
    local executed_ctx = nil
    local mock_client = {
      id = 1,
      name = 'clangd',
      offset_encoding = 'utf-16',
      exec_cmd = function(self, cmd, ctx)
        executed_cmd = cmd
        executed_ctx = ctx
      end,
    }

    local orig_get_client_by_id = vim.lsp.get_client_by_id
    vim.lsp.get_client_by_id = function(id)
      return id == 1 and mock_client or nil
    end

    local captured_on_choice = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, _, on_choice) captured_on_choice = on_choice end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    local lsp_choice = {
      action = {
        title = 'Fix Issue',
        kind = 'quickfix',
        command = { command = 'clangd.applyFix', arguments = { 'arg1', 'arg2' } },
      },
      ctx = { client_id = 1, bufnr = bufnr },
    }
    captured_on_choice(lsp_choice)

    assert.is_not_nil(executed_cmd)
    eq('clangd.applyFix', executed_cmd.command)
    eq({ 'arg1', 'arg2' }, executed_cmd.arguments)
    eq(bufnr, executed_ctx.bufnr)

    vim.lsp.get_client_by_id = orig_get_client_by_id
    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)

  it('applies workspace edit before executing command', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'test', title = 'Test', kind = 'refactor' },
    })

    local cmd_executed = false
    local mock_client = {
      id = 1,
      name = 'clangd',
      offset_encoding = 'utf-8',
      exec_cmd = function() cmd_executed = true end,
    }

    local orig_get_client_by_id = vim.lsp.get_client_by_id
    vim.lsp.get_client_by_id = function(id)
      return id == 1 and mock_client or nil
    end

    local applied_edit = nil
    local orig_apply_workspace_edit = vim.lsp.util.apply_workspace_edit
    vim.lsp.util.apply_workspace_edit = function(edit, encoding)
      applied_edit = { edit = edit, encoding = encoding }
    end

    local captured_on_choice = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, _, on_choice) captured_on_choice = on_choice end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    local lsp_choice = {
      action = {
        title = 'Apply Fix',
        kind = 'quickfix',
        edit = { documentChanges = { { edits = {} } } },
        command = { command = 'doSomething', arguments = {} },
      },
      ctx = { client_id = 1, bufnr = bufnr },
    }
    captured_on_choice(lsp_choice)

    assert.is_not_nil(applied_edit)
    eq('utf-8', applied_edit.encoding)
    assert.is_true(cmd_executed)

    vim.lsp.get_client_by_id = orig_get_client_by_id
    vim.lsp.util.apply_workspace_edit = orig_apply_workspace_edit
    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)

  it('handles missing client gracefully', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'test', title = 'Test', kind = 'refactor' },
    })

    local orig_get_client_by_id = vim.lsp.get_client_by_id
    vim.lsp.get_client_by_id = function() return nil end

    local captured_on_choice = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, _, on_choice) captured_on_choice = on_choice end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    local lsp_choice = {
      action = { title = 'Fix', kind = 'quickfix', command = { command = 'test' } },
      ctx = { client_id = 999, bufnr = bufnr },
    }
    captured_on_choice(lsp_choice)

    vim.lsp.get_client_by_id = orig_get_client_by_id
    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)

  it('handles action.command as string (falls back to action itself)', function()
    local M = get_fresh_module()
    local bufnr = helpers.create_buffer({ 'int x;' }, 'cpp')
    vim.api.nvim_get_current_buf = function() return bufnr end
    vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

    local orig_get_actions = mock_cmantic_actions({
      { id = 'test', title = 'Test', kind = 'refactor' },
    })

    local executed_cmd = nil
    local mock_client = {
      id = 1,
      name = 'clangd',
      offset_encoding = 'utf-8',
      exec_cmd = function(self, cmd, ctx) executed_cmd = cmd end,
    }

    local orig_get_client_by_id = vim.lsp.get_client_by_id
    vim.lsp.get_client_by_id = function(id)
      return id == 1 and mock_client or nil
    end

    local captured_on_choice = nil
    vim.lsp.buf_request_all = function(_, _, _, callback) callback({}) end
    vim.ui.select = function(_, _, on_choice) captured_on_choice = on_choice end

    local orig_make_range_params = vim.lsp.util.make_range_params
    vim.lsp.util.make_range_params = function() return { context = {} } end
    local orig_get_line_diagnostics = vim.lsp.diagnostic.get_line_diagnostics
    vim.lsp.diagnostic.get_line_diagnostics = function() return {} end

    M.enable()
    vim.lsp.buf.code_action({})

    local lsp_choice = {
      action = {
        title = 'Fix Issue',
        kind = 'quickfix',
        command = 'stringCommand',
      },
      ctx = { client_id = 1, bufnr = bufnr },
    }
    captured_on_choice(lsp_choice)

    assert.is_not_nil(executed_cmd)
    eq('Fix Issue', executed_cmd.title)

    vim.lsp.get_client_by_id = orig_get_client_by_id
    restore_cmantic_actions(orig_get_actions)
    vim.lsp.util.make_range_params = orig_make_range_params
    vim.lsp.diagnostic.get_line_diagnostics = orig_get_line_diagnostics
  end)
end)

describe('enable/disable cycle', function()
  it('preserves original function through multiple cycles', function()
    local M = get_fresh_module()
    local original = vim.lsp.buf.code_action

    M.enable()
    M.disable()
    assert.are.equal(original, vim.lsp.buf.code_action)

    M.enable()
    M.disable()
    assert.are.equal(original, vim.lsp.buf.code_action)
  end)

  it('maintains consistent active state through cycles', function()
    local M = get_fresh_module()

    M.enable()
    assert.is_true(M.is_active())

    M.disable()
    assert.is_false(M.is_active())

    M.enable()
    assert.is_true(M.is_active())

    M.disable()
    assert.is_false(M.is_active())
  end)
end)

describe('supported filetypes', function()
  local supported_fts = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' }

  for _, ft in ipairs(supported_fts) do
    it('processes ' .. ft .. ' filetype', function()
      local M = get_fresh_module()
      local bufnr = helpers.create_buffer({ '' }, ft)
      vim.api.nvim_get_current_buf = function() return bufnr end
      vim.api.nvim_win_get_cursor = function() return { 1, 0 } end

      local orig_get_actions = mock_cmantic_actions({})

      local called = false
      vim.lsp.buf.code_action = function() called = true end

      M.enable()
      vim.lsp.buf.code_action({})

      assert.is_true(called)

      restore_cmantic_actions(orig_get_actions)
    end)
  end
end)
