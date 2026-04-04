--- code_action_inject.lua
--- Intercepts vim.ui.select(kind='codeaction') to inject cmantic actions
--- into the standard vim.lsp.buf.code_action() flow (<leader>ca).

local M = {}

local original_select = vim.ui.select
local active = false

--- Start intercepting vim.ui.select for code actions
function M.enable()
  if active then return end
  active = true
  original_select = vim.ui.select

  vim.ui.select = function(items, opts, on_choice)
    -- Only intercept code action selections
    if opts.kind ~= 'codeaction' then
      return original_select(items, opts, on_choice)
    end

    -- Check if current buffer is C/C++
    local bufnr = vim.api.nvim_get_current_buf()
    local ft = vim.bo[bufnr].filetype
    local supported_ft = { c = true, cpp = true, objc = true, objcpp = true, cuda = true, proto = true }
    if not supported_ft[ft] then
      return original_select(items, opts, on_choice)
    end

    -- Get current cursor position
    local cursor = vim.api.nvim_win_get_cursor(0)
    local position = { line = cursor[1] - 1, character = cursor[2] }

    -- Build cmantic actions
    local code_action = require('cmantic.code_action')
    local ok, cmantic_actions = pcall(code_action.get_applicable_actions, bufnr, {
      range = { start = position, ['end'] = position }
    })
    if not ok or not cmantic_actions or #cmantic_actions == 0 then
      return original_select(items, opts, on_choice)
    end

    -- Convert cmantic actions to the { action, ctx } format used by
    -- Neovim's internal on_code_action_results (see buf.lua:734)
    local injected = {}
    for _, act in ipairs(cmantic_actions) do
      if not act.disabled then
        table.insert(injected, {
          action = {
            title = act.title,
            kind = act.kind,
          },
          ctx = {
            client_id = -1,  -- sentinel: marks as cmantic action
            bufnr = bufnr,
          },
          _cmantic_id = act.id,
        })
      end
    end

    if #injected == 0 then
      return original_select(items, opts, on_choice)
    end

    -- Merge: cmantic actions first (QuickFix/preferred naturally sort to top)
    local all_items = vim.list_extend(injected, items)

    return original_select(all_items, opts, function(choice)
      if not choice then return on_choice(choice) end

      if choice._cmantic_id then
        -- cmantic action: execute directly
        code_action.execute_by_id(choice._cmantic_id)
        return
      end

      -- LSP action: delegate to original on_choice
      on_choice(choice)
    end)
  end
end

--- Stop intercepting (for cleanup/disable)
function M.disable()
  if active then
    vim.ui.select = original_select
    active = false
  end
end

--- Check if injection is active
function M.is_active()
  return active
end

return M
