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

--- Convert internal cmantic actions to Neovim 0.12's { action, ctx } format.
--- @param actions table[] cmantic action list
--- @param bufnr number
--- @return table[] items matching Neovim's code action item format
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
--- Neovim 0.12 format: { action = { title, ... }, ctx = { client_id, ... } }
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

  -- LSP action — delegate to Neovim's own handler via original_code_action
  -- with a single pre-resolved result.
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

    -- Use Neovim's own code_action to handle LSP request + response.
    -- We intercept by wrapping vim.ui.select temporarily to merge our actions.
    local select_original = vim.ui.select
    vim.ui.select = function(items, select_opts, on_choice)
      vim.ui.select = select_original

      if select_opts.kind ~= 'codeaction' then
        return select_original(items, select_opts, on_choice)
      end

      local cmantic_items = to_lsp_items(cmantic_actions, bufnr)
      local all_items = vim.list_extend(cmantic_items, items)

      if #all_items == 0 then
        vim.notify('No code actions available', vim.log.levels.INFO)
        return
      end

      select_original(all_items, select_opts, function(choice)
        if choice and choice._cmantic_id then
          require('cmantic.code_action').execute_by_id(choice._cmantic_id)
        else
          on_choice(choice)
        end
      end)
    end

    original_code_action(opts)

    -- If LSP returned 0 actions, Neovim won't call vim.ui.select,
    -- so our interception above never fires. Show cmantic-only.
    -- We detect this by checking if vim.ui.select was restored
    -- (it gets restored inside the interception).
    vim.schedule(function()
      if vim.ui.select ~= select_original then
        -- Interception didn't fire — LSP had no actions
        vim.ui.select = select_original
        local cmantic_items = to_lsp_items(cmantic_actions, bufnr)
        if #cmantic_items > 0 then
          select_original(cmantic_items, {
            prompt = 'Code actions:',
            kind = 'codeaction',
            format_item = format_action,
          }, on_user_choice)
        end
      end
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
