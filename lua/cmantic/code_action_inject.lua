--- code_action_inject.lua
--- Intercepts vim.ui.select(kind='codeaction') to inject cmantic actions
--- into the standard vim.lsp.buf.code_action() flow (<leader>ca).
---
--- Also wraps vim.lsp.buf.code_action to handle the case where the LSP
--- server returns zero results (e.g. empty header file). Neovim skips
--- vim.ui.select entirely when there are no LSP actions, so we detect
--- this via a flag and show cmantic-only actions as a fallback.

local M = {}

local original_select = vim.ui.select
local original_code_action = vim.lsp.buf.code_action
local active = false

-- Per-invocation state for coordinating between the two hooks
local _pending_cmantic = nil
local _select_was_called = false

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
  if not ok then return {} end
  return actions or {}
end

--- Convert internal cmantic actions to Neovim's { action, ctx } code-action format.
--- @param actions table[] cmantic action list
--- @param bufnr number
--- @return table[] items suitable for vim.ui.select in codeaction flow
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
          client_id = -1, -- sentinel: marks as cmantic action
          bufnr = bufnr,
        },
        _cmantic_id = act.id,
      })
    end
  end
  return items
end

--- Show cmantic-only actions via vim.ui.select (fallback when LSP has none).
--- @param actions table[] cmantic action list
local function show_cmantic_only(actions)
  local code_action = require('cmantic.code_action')
  local bufnr = vim.api.nvim_get_current_buf()
  local items = to_lsp_items(actions, bufnr)
  if #items == 0 then return end

  original_select(items, {
    kind = 'codeaction',
    prompt = 'Code Actions:',
    format_item = function(item)
      return item.action and item.action.title or tostring(item)
    end,
  }, function(choice)
    if choice and choice._cmantic_id then
      code_action.execute_by_id(choice._cmantic_id)
    end
  end)
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Start intercepting code actions
function M.enable()
  if active then return end
  active = true
  original_select = vim.ui.select
  original_code_action = vim.lsp.buf.code_action

  --------------------------------------------------------------------
  -- Hook 1: Patch vim.ui.select to merge cmantic actions when the LSP
  -- *does* provide its own actions (so vim.ui.select is actually called).
  --------------------------------------------------------------------
  vim.ui.select = function(items, opts, on_choice)
    if opts.kind ~= 'codeaction' then
      return original_select(items, opts, on_choice)
    end

    -- Mark that vim.ui.select was invoked for this code_action call
    _select_was_called = true

    if _pending_cmantic and #_pending_cmantic > 0 then
      local bufnr = vim.api.nvim_get_current_buf()
      local injected = to_lsp_items(_pending_cmantic, bufnr)
      _pending_cmantic = nil

      if #injected > 0 then
        local code_action = require('cmantic.code_action')
        local all_items = vim.list_extend(injected, items)

        return original_select(all_items, opts, function(choice)
          if not choice then return on_choice(choice) end

          if choice._cmantic_id then
            code_action.execute_by_id(choice._cmantic_id)
            return
          end

          on_choice(choice)
        end)
      end
    end

    return original_select(items, opts, on_choice)
  end

  --------------------------------------------------------------------
  -- Hook 2: Wrap vim.lsp.buf.code_action to handle the empty-LSP-results
  -- case. When clangd returns zero actions, Neovim never calls
  -- vim.ui.select, so Hook 1 never fires. We detect this with a flag
  -- and show cmantic-only actions as a fallback via vim.schedule.
  --------------------------------------------------------------------
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

    _pending_cmantic = cmantic_actions
    _select_was_called = false

    original_code_action(opts)

    -- Fallback: if vim.ui.select was never called (LSP returned empty),
    -- show cmantic-only actions.
    --
    -- vim.schedule fires on the next event-loop tick, AFTER pending I/O
    -- callbacks (including the LSP response). For local clangd the
    -- response arrives in the same tick, so this ordering is reliable.
    vim.schedule(function()
      if not _select_was_called and _pending_cmantic then
        local actions = _pending_cmantic
        _pending_cmantic = nil
        show_cmantic_only(actions)
      end
    end)
  end
end

--- Stop intercepting (for cleanup/disable)
function M.disable()
  if active then
    vim.ui.select = original_select
    vim.lsp.buf.code_action = original_code_action
    active = false
    _pending_cmantic = nil
    _select_was_called = false
  end
end

--- Check if injection is active
function M.is_active()
  return active
end

return M
