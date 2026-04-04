--- code_action_inject.lua
--- Replaces vim.lsp.buf.code_action for C/C++ files to merge cmantic actions
--- with LSP code actions into a single picker. No timers or deferred callbacks
--- — the merged picker opens exactly when the LSP response arrives.

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

--- Convert internal cmantic actions to Neovim's { client_id, action } tuple format.
--- @param actions table[] cmantic action list
--- @return table[] action tuples with _cmantic_id sentinel
local function to_lsp_items(actions)
  local items = {}
  for _, act in ipairs(actions) do
    if not act.disabled then
      table.insert(items, {
        -1,
        {
          title = act.title,
          kind = act.kind,
        },
        _cmantic_id = act.id,
      })
    end
  end
  return items
end

--- Apply an LSP code action (replicates Neovim's internal apply_action logic).
--- @param action table LSP CodeAction
--- @param client table LSP client
--- @param ctx table LSP request context
local function apply_lsp_action(action, client, ctx)
  if action.edit then
    vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
  end
  if action.command then
    local command = type(action.command) == 'table' and action.command or action
    local fn = client.commands[command.command] or vim.lsp.commands[command.command]
    if fn then
      local enriched_ctx = vim.deepcopy(ctx)
      enriched_ctx.client_id = client.id
      fn(command, enriched_ctx)
    else
      local params = {
        command = command.command,
        arguments = command.arguments,
        workDoneToken = command.workDoneToken,
      }
      client.request('workspace/executeCommand', params, nil, ctx.bufnr)
    end
  end
end

--- Handle user selection from the merged action list.
--- @param choice table|nil Selected action tuple or nil
--- @param ctx table LSP request context
local function on_user_choice(choice, ctx)
  if not choice then return end

  -- Cmantic action
  if choice._cmantic_id then
    require('cmantic.code_action').execute_by_id(choice._cmantic_id)
    return
  end

  -- LSP action
  local client_id = choice[1]
  local action = choice[2]
  local client = vim.lsp.get_client_by_id(client_id)

  if not action.edit
    and client
    and type(client.resolved_capabilities.code_action) == 'table'
    and client.resolved_capabilities.code_action.resolveProvider then
    client.request('codeAction/resolve', action, function(err, resolved_action)
      if err then
        vim.notify(err.code .. ': ' .. err.message, vim.log.levels.ERROR)
        return
      end
      apply_lsp_action(resolved_action, client, ctx)
    end)
  else
    apply_lsp_action(action, client, ctx)
  end
end

--- Format an action tuple for display in the picker.
--- @param item table Action tuple
--- @return string Display text
local function format_action(item)
  if item._cmantic_id then
    return item[2].title
  end
  local title = item[2].title:gsub('\r\n', '\\r\\n')
  return title:gsub('\n', '\\n')
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function M.enable()
  if active then return end
  active = true
  original_code_action = vim.lsp.buf.code_action

  vim.lsp.buf.code_action = function(context)
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo[bufnr].filetype

    if not SUPPORTED_FT[ft] then
      return original_code_action(context)
    end

    local cmantic_actions = get_cmantic_actions(bufnr)

    if #cmantic_actions == 0 then
      return original_code_action(context)
    end

    context = context or {}
    if not context.diagnostics then
      context.diagnostics = vim.lsp.diagnostic.get_line_diagnostics(bufnr)
    end
    local params = vim.lsp.util.make_range_params()
    params.context = context

    local method = 'textDocument/codeAction'
    local ctx = { bufnr = bufnr, method = method, params = params }

    vim.lsp.buf_request_all(bufnr, method, params, function(results)
      local lsp_tuples = {}
      for client_id, result in pairs(results or {}) do
        for _, action in pairs(result.result or {}) do
          table.insert(lsp_tuples, { client_id, action })
        end
      end

      local cmantic_tuples = to_lsp_items(cmantic_actions)

      if #lsp_tuples == 0 and #cmantic_tuples == 0 then
        vim.notify('No code actions available', vim.log.levels.INFO)
        return
      end

      local all_items = vim.list_extend(cmantic_tuples, lsp_tuples)

      vim.ui.select(all_items, {
        prompt = 'Code actions:',
        kind = 'codeaction',
        format_item = format_action,
      }, function(choice)
        on_user_choice(choice, ctx)
      end)
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
