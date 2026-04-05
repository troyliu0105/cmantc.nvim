--- code_action_inject.lua
--- Replaces vim.lsp.buf.code_action for C/C++ files to merge cmantic actions
--- with LSP code actions into a single picker.
--- Uses buf_request_all to avoid timing issues — no deferred callbacks.

local M = {}

local original_code_action = vim.lsp.buf.code_action
local active = false

local SUPPORTED_FT = {
  c = true, cpp = true, objc = true, objcpp = true, cuda = true, proto = true,
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

--- Build cmantic actions for the given buffer at the current cursor position.
--- @param bufnr number
--- @return table[] cmantic actions (may be empty)
local function get_cmantic_actions(bufnr)
  local code_action = require('cmantic.code_action')
  local cursor = vim.api.nvim_win_get_cursor(0)
  local position = { line = cursor[1] - 1, character = cursor[2] }
  local ok, actions = pcall(code_action.get_applicable_actions, bufnr, {
    range = { start = position, ['end'] = position },
  })
  if not ok then
    local notify = require('cmantic.utils').notify
    notify('Cmantic action evaluation failed: ' .. tostring(actions), vim.log.levels.ERROR)
    return {}
  end
  return actions or {}
end

--- Convert internal cmantic actions to Neovim's { action, ctx } format.
--- @param actions table[] cmantic action list
--- @param bufnr number
--- @return table[] items matching Neovim 0.12 code action item format
local function to_lsp_items(actions, bufnr)
  local items = {}
  for _, act in ipairs(actions) do
    if not act.disabled then
      table.insert(items, {
        action = {
          title = act.title,
          kind = act.kind,
        },
        ctx = {
          client_id = -1,
          bufnr = bufnr,
        },
        _cmantic_id = act.id,
      })
    end
  end
  return items
end

--- Format an action item for display in the picker.
--- @param item table Action item
--- @return string Display text
local function format_action(item)
  if item._cmantic_id then
    return item.action.title
  end
  local title = item.action.title:gsub('\r\n', '\\r\\n')
  return title:gsub('\n', '\\n')
end

--- Handle user selection from the merged action list.
--- @param choice table|nil Selected action item or nil
local function on_user_choice(choice)
  if not choice then return end

  if choice._cmantic_id then
    require('cmantic.code_action').execute_by_id(choice._cmantic_id)
    return
  end

  local client_id = choice.ctx and choice.ctx.client_id
  local client = vim.lsp.get_client_by_id(client_id)
  if not client then return end

  local action = choice.action
  if action.edit then
    vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
  end
  local a_cmd = action.command
  if a_cmd then
    local command = type(a_cmd) == 'table' and a_cmd or action
    client:exec_cmd(command, choice.ctx)
  end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.enable()
  if active then return end
  active = true
  original_code_action = vim.lsp.buf.code_action

  vim.lsp.buf.code_action = function(opts)
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo[bufnr].filetype

    if not SUPPORTED_FT[ft] then
      return original_code_action(opts)
    end

    local cmantic_actions = get_cmantic_actions(bufnr)

    if #cmantic_actions == 0 then
      return original_code_action(opts)
    end

    opts = opts or {}
    if not opts.context then
      opts.context = {}
    end
    if not opts.context.diagnostics then
      opts.context.diagnostics = vim.lsp.diagnostic.get_line_diagnostics(bufnr)
    end

    local params = vim.lsp.util.make_range_params()
    params.context = opts.context

    vim.lsp.buf_request_all(bufnr, 'textDocument/codeAction', params, function(results)
      local lsp_items = {}
      for _, result in pairs(results or {}) do
        for _, action in pairs(result.result or {}) do
          table.insert(lsp_items, { action = action, ctx = result.context })
        end
      end

      local cmantic_items = to_lsp_items(cmantic_actions, bufnr)

      if #lsp_items == 0 and #cmantic_items == 0 then
        vim.notify('No code actions available', vim.log.levels.INFO)
        return
      end

      local all_items = vim.list_extend(cmantic_items, lsp_items)

      vim.ui.select(all_items, {
        prompt = 'Code actions:',
        kind = 'codeaction',
        format_item = format_action,
      }, on_user_choice)
    end)
  end
end

function M.disable()
  if active then
    vim.lsp.buf.code_action = original_code_action
    active = false
  end
end

function M.is_active()
  return active
end

return M
