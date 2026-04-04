# Code Action Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix `<leader>ca` integration so cmantic actions appear alongside clangd's native actions, and align with vscode-cmantic's 19 code actions.

**Architecture:** Intercept `vim.ui.select(kind='codeaction')` to inject cmantic actions into the LSP code action menu. Rewrite `code_action.lua` with the full 19-action set including Update Signature tracking. Preserve `:Cmantic` as an independent entry point.

**Tech Stack:** Neovim 0.10+ Lua, vim.lsp API, vim.ui.select, clangd LSP

**Design Doc:** `docs/plans/2026-04-04-code-action-integration-design.md`

---

### Task 1: Create code_action_inject.lua — The vim.ui.select Interceptor

**Files:**
- Create: `lua/cmantic/code_action_inject.lua`

**Step 1: Create the inject module**

```lua
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
```

**Step 2: Verify module loads without error**

Run: `nvim --headless -c "lua local m = require('cmantic.code_action_inject'); print('inject loaded: active=' .. tostring(m.is_active()))" -c "q" 2>&1`
Expected: `inject loaded: active=false`

**Step 3: Commit**

```bash
git add lua/cmantic/code_action_inject.lua
git commit -m "feat: code_action_inject — vim.ui.select interceptor for <leader>ca"
```

---

### Task 2: Rewrite code_action.lua — Bug Fixes + New Action Data Structure

**Files:**
- Modify: `lua/cmantic/code_action.lua` (full rewrite of lines 1–487)

This is the largest task. The file will be rewritten to:
1. Fix all 6 known bugs
2. Introduce the `CmanticAction` data structure
3. Add `execute_by_id()` public API
4. Restructure action generators to return `{ id, title, kind, execute_fn, disabled?, disabled_reason? }`

**Step 1: Rewrite the header and constants section**

Replace lines 1–21 with:

```lua
--- LSP Code Action Provider for cmantic.nvim
--- Rewritten to integrate with vim.lsp.buf.code_action() via code_action_inject.lua.
--- Generates 19 code actions aligned with vscode-cmantic's CodeActionProvider.ts.

local M = {}

local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')
local header_source = require('cmantic.header_source')
local utils = require('cmantic.utils')
local config = require('cmantic.config')

-- Action kind constants (match LSP CodeActionKind)
local KIND = {
  QUICK_FIX = 'quickfix',
  REFACTOR = 'refactor',
  REFACTOR_EXTRACT = 'refactor.extract',
  REFACTOR_REWRITE = 'refactor.rewrite',
  SOURCE = 'source',
}
```

**Step 2: Rewrite setup() — keep autocmd, add signature tracking setup**

Replace lines 23–55 (setup + _register_provider) with:

```lua
--------------------------------------------------------------------------------
-- Setup and Registration
--------------------------------------------------------------------------------

--- Register the code action provider and signature tracking
function M.setup()
  local group = vim.api.nvim_create_augroup('cmantic_code_actions', { clear = true })

  -- File type detection for C/C++ buffers
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
    callback = function(args)
      vim.b[args.buf].cmantic_enabled = true
    end,
  })

  -- Set up for already-loaded buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ft = vim.bo[bufnr].filetype
      if ft == 'c' or ft == 'cpp' or ft == 'objc' or ft == 'objcpp'
        or ft == 'cuda' or ft == 'proto' then
        vim.b[bufnr].cmantic_enabled = true
      end
    end
  end

  -- Signature change tracking for Update Signature feature
  M._setup_signature_tracking()
end
```

**Step 3: Rewrite get_applicable_actions() — fix bugs + new flow**

Replace lines 57–127 with the new main function that:
- Removes `name='clangd'` filter
- Guards `doc.uri`
- Calls all 19 action generators
- Tracks current function for signature detection

```lua
--------------------------------------------------------------------------------
-- Signature Tracking State
--------------------------------------------------------------------------------

M._tracked_function = nil      -- CSymbol at cursor during last evaluation
M._previous_signature = nil    -- FunctionSignature before change
M._signature_changed = false   -- whether signature change was detected

--------------------------------------------------------------------------------
-- Main Logic
--------------------------------------------------------------------------------

--- Get all applicable actions at the given position
--- @param bufnr number Buffer number
--- @param params table { range = { start = { line, character }, ['end'] = { line, character } } }
--- @return CmanticAction[] Array of action tables
function M.get_applicable_actions(bufnr, params)
  local actions = {}

  -- Get cursor position from params or current cursor
  local position = params and params.range and params.range.start
  if not position then
    local cursor = vim.api.nvim_win_get_cursor(0)
    position = { line = cursor[1] - 1, character = cursor[2] }
  end

  -- Create SourceDocument — guard against nil uri
  local doc = SourceDocument.new(bufnr)
  if not doc.uri then
    return actions
  end

  -- Check if any LSP client is attached (not just clangd)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local has_lsp = #clients > 0

  -- Get symbol at position (may be nil for empty files / no LSP)
  local symbol = nil
  if has_lsp then
    symbol = doc:get_symbol_at_position(position)
  end

  local csymbol = nil
  if symbol then
    csymbol = symbol.document and symbol or CSymbol.new(symbol, doc)
  end

  if csymbol then
    -- Refactor: Add Definition (includes Constructor variant)
    if csymbol:is_function() and csymbol:is_function_declaration() then
      M._add_definition_actions(actions, csymbol, doc)
    end

    -- Refactor: Add Declaration + Move Definition
    if csymbol:is_function() and csymbol:is_function_definition() then
      M._add_declaration_actions(actions, csymbol, doc)
      M._add_move_definition_actions(actions, csymbol, doc)
    end

    -- Refactor: Getters/Setters
    if csymbol:is_member_variable() then
      M._add_getter_setter_actions(actions, csymbol, doc)
    end

    -- Refactor: Operators (class/struct or parent is class)
    if csymbol:is_class_type() or (csymbol.parent and csymbol.parent:is_class_type()) then
      M._add_operator_actions(actions, csymbol, doc)
    end

    -- QuickFix: Update Signature
    M._add_update_signature_actions(actions, csymbol, doc)
  end

  -- Source Actions (always checked, regardless of symbol)
  M._add_source_actions(actions, doc)

  -- Bulk: Add Definitions (header files only)
  if doc:is_header() then
    M._add_bulk_definitions_action(actions, doc)
  end

  -- Track current function for signature change detection
  M._track_current_function(csymbol)

  return actions
end
```

**Step 4: Rewrite action generators**

Replace lines 129–328 with the new action generator functions. Each returns `CmanticAction` objects. Key changes:
- Constructor no longer skipped — uses dynamic title
- Move Definition added (2 variants)
- Source actions include AmendHeaderGuard + AddInclude
- Operators work on class/struct or parent class

```lua
--------------------------------------------------------------------------------
-- Refactor Action Generators
--------------------------------------------------------------------------------

--- Add Definition actions (includes Constructor variant)
--- @param actions CmanticAction[]
--- @param csymbol table CSymbol (must be function declaration)
--- @param doc table SourceDocument
function M._add_definition_actions(actions, csymbol, doc)
  if csymbol:is_pure_virtual() then return end

  local is_ctor = csymbol:is_constructor()
  local is_dtor = csymbol:is_destructor()
  if is_dtor then return end  -- destructors not supported

  local prefix = is_ctor and 'Generate Constructor' or 'Add Definition'
  local matching_uri = header_source.get_matching(doc.uri)

  if doc:is_header() and matching_uri then
    table.insert(actions, {
      id = 'addDefinitionMatching',
      title = prefix .. ' in matching source file',
      kind = KIND.REFACTOR_REWRITE,
      execute_fn = function()
        require('cmantic.commands.add_definition').execute_in_source()
      end,
    })
  end

  if doc:is_header() then
    table.insert(actions, {
      id = 'addDefinitionInline',
      title = prefix .. ' in this file',
      kind = KIND.REFACTOR_REWRITE,
      execute_fn = function()
        require('cmantic.commands.add_definition').execute_in_current()
      end,
    })
  end
end

--- Add Declaration actions
--- @param actions CmanticAction[]
--- @param csymbol table CSymbol (must be function definition)
--- @param doc table SourceDocument
function M._add_declaration_actions(actions, csymbol, doc)
  if csymbol:is_constructor() or csymbol:is_destructor() then return end

  local matching_uri = header_source.get_matching(doc.uri)

  if doc:is_source() and matching_uri then
    table.insert(actions, {
      id = 'addDeclaration',
      title = 'Add Declaration in matching header file',
      kind = KIND.REFACTOR_REWRITE,
      execute_fn = function()
        require('cmantic.commands.add_declaration').execute()
      end,
    })
  end

  -- Check if inside a class (definition in same file as class)
  local parent = csymbol.parent
  if parent and parent:is_class_type() then
    local parent_name = parent.name or 'class'
    local parent_kind = 'class'  -- TODO: detect struct vs class
    table.insert(actions, {
      id = 'addDeclarationInClass',
      title = 'Add Declaration in ' .. parent_kind .. ' "' .. parent_name .. '"',
      kind = KIND.REFACTOR_REWRITE,
      execute_fn = function()
        require('cmantic.commands.add_declaration').execute()
      end,
    })
  end
end

--- Move Definition actions
--- @param actions CmanticAction[]
--- @param csymbol table CSymbol (must be function definition)
--- @param doc table SourceDocument
function M._add_move_definition_actions(actions, csymbol, doc)
  if csymbol:is_constructor() or csymbol:is_destructor() then return end

  -- Move to matching source file
  local matching_uri = header_source.get_matching(doc.uri)
  if matching_uri then
    table.insert(actions, {
      id = 'moveDefinitionToSource',
      title = 'Move Definition to matching source file',
      kind = KIND.REFACTOR_REWRITE,
      execute_fn = function()
        require('cmantic.commands.move_definition').execute({ mode = 'to_source' })
      end,
    })
  end

  -- Move into/out of class body (C++ only, only for member functions)
  local parent = csymbol.parent
  if parent then
    if parent:is_class_type() then
      -- Definition is inside class → offer move below class
      local parent_kind = 'class'  -- TODO: detect struct
      table.insert(actions, {
        id = 'moveDefinitionInOutOfClass',
        title = 'Move Definition below ' .. parent_kind .. ' body',
        kind = KIND.REFACTOR_REWRITE,
        execute_fn = function()
          require('cmantic.commands.move_definition').execute({ mode = 'in_out_class' })
        end,
      })
    end
  end
end

--- Getter/Setter actions
--- @param actions CmanticAction[]
--- @param csymbol table CSymbol (must be member variable)
--- @param doc table SourceDocument
function M._add_getter_setter_actions(actions, csymbol, doc)
  local getter_name = csymbol:getter_name()
  local setter_name = csymbol:setter_name()
  local parent = csymbol.parent
  if not parent then return end

  local has_getter = M._has_method(parent, getter_name)
  local has_setter = M._has_method(parent, setter_name)
  local var_name = csymbol.name or 'member'

  if not has_getter then
    table.insert(actions, {
      id = 'generateGetter',
      title = 'Generate Getter for "' .. var_name .. '"',
      kind = KIND.REFACTOR_EXTRACT,
      execute_fn = function()
        require('cmantic.commands.generate_getter_setter').execute({ mode = 'getter' })
      end,
    })
  end

  if not has_setter then
    table.insert(actions, {
      id = 'generateSetter',
      title = 'Generate Setter for "' .. var_name .. '"',
      kind = KIND.REFACTOR_EXTRACT,
      execute_fn = function()
        require('cmantic.commands.generate_getter_setter').execute({ mode = 'setter' })
      end,
    })
  end

  if not has_getter and not has_setter then
    table.insert(actions, {
      id = 'generateGetterSetter',
      title = 'Generate Getter and Setter for "' .. var_name .. '"',
      kind = KIND.REFACTOR_EXTRACT,
      execute_fn = function()
        require('cmantic.commands.generate_getter_setter').execute({ mode = 'both' })
      end,
    })
  end
end

--- Operator generation actions
--- @param actions CmanticAction[]
--- @param csymbol table CSymbol (class/struct or member of class)
--- @param doc table SourceDocument
function M._add_operator_actions(actions, csymbol, doc)
  -- Resolve the class symbol: either this symbol or its parent
  local class_symbol = csymbol
  if not csymbol:is_class_type() then
    if csymbol.parent and csymbol.parent:is_class_type() then
      class_symbol = csymbol.parent
    else
      return
    end
  end

  local class_name = class_symbol.name or 'class'

  table.insert(actions, {
    id = 'generateEqualityOperators',
    title = 'Generate Equality Operators for "' .. class_name .. '"',
    kind = KIND.REFACTOR_EXTRACT,
    execute_fn = function()
      require('cmantic.commands.generate_operators').execute({ mode = 'equality' })
    end,
  })

  table.insert(actions, {
    id = 'generateRelationalOperators',
    title = 'Generate Relational Operators for "' .. class_name .. '"',
    kind = KIND.REFACTOR_EXTRACT,
    execute_fn = function()
      require('cmantic.commands.generate_operators').execute({ mode = 'relational' })
    end,
  })

  table.insert(actions, {
    id = 'generateStreamOperator',
    title = 'Generate Stream Output Operator for "' .. class_name .. '"',
    kind = KIND.REFACTOR_EXTRACT,
    execute_fn = function()
      require('cmantic.commands.generate_operators').execute({ mode = 'stream' })
    end,
  })
end
```

**Step 5: Add Source Actions (including new AmendHeaderGuard + AddInclude)**

```lua
--------------------------------------------------------------------------------
-- Source Action Generators
--------------------------------------------------------------------------------

--- Source actions (file-level, not dependent on specific symbol)
--- @param actions CmanticAction[]
--- @param doc table SourceDocument
function M._add_source_actions(actions, doc)
  if not doc.uri then return end

  -- Header Guard
  if doc:is_header() then
    if not doc:has_header_guard() then
      table.insert(actions, {
        id = 'addHeaderGuard',
        title = 'Add Header Guard',
        kind = KIND.SOURCE,
        execute_fn = function()
          require('cmantic.commands.add_header_guard').execute()
        end,
      })
    else
      -- Guard exists but may not match config style → Amend
      -- For now, always offer AmendHeaderGuard if guard exists
      -- TODO: check if guard matches config header_guard_style
      table.insert(actions, {
        id = 'amendHeaderGuard',
        title = 'Amend Header Guard',
        kind = KIND.SOURCE,
        execute_fn = function()
          require('cmantic.commands.add_header_guard').execute()
        end,
      })
    end
  end

  -- Add Include (always available for C/C++ files)
  table.insert(actions, {
    id = 'addInclude',
    title = 'Add Include',
    kind = KIND.SOURCE,
    execute_fn = function()
      require('cmantic.commands.add_include').execute()
    end,
  })

  -- Create Matching Source File
  if doc:is_header() then
    local matching_uri = header_source.get_matching(doc.uri)
    if not matching_uri then
      table.insert(actions, {
        id = 'createMatchingSourceFile',
        title = 'Create Matching Source File',
        kind = KIND.SOURCE,
        execute_fn = function()
          require('cmantic.commands.create_source_file').execute()
        end,
      })
    end
  end
end

--- Bulk Add Definitions action
--- @param actions CmanticAction[]
--- @param doc table SourceDocument
function M._add_bulk_definitions_action(actions, doc)
  -- Only offer if we can potentially find declarations without definitions
  table.insert(actions, {
    id = 'addDefinitionsBulk',
    title = 'Add Definitions...',
    kind = KIND.REFACTOR_REWRITE,
    execute_fn = function()
      require('cmantic.commands.add_definition').execute_batch()
    end,
  })
end
```

**Step 6: Add Update Signature Actions + Tracking**

```lua
--------------------------------------------------------------------------------
-- QuickFix: Update Signature
--------------------------------------------------------------------------------

--- Set up autocmd to detect signature changes
function M._setup_signature_tracking()
  local group = vim.api.nvim_create_augroup('cmantic_signature_track', { clear = true })
  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChangedP' }, {
    group = group,
    pattern = { '*.h', '*.hpp', '*.hh', '*.hxx', '*.c', '*.cpp', '*.cc', '*.cxx' },
    callback = function()
      M._check_signature_change()
    end,
  })
end

--- Track current function after each action evaluation
--- @param csymbol table|nil CSymbol at cursor position
function M._track_current_function(csymbol)
  if not csymbol or not csymbol:is_function() then
    return
  end
  M._tracked_function = {
    range = csymbol.range,
    name = csymbol.name,
  }
  -- Store baseline signature text
  local bufnr = vim.api.nvim_get_current_buf()
  local lines = vim.api.nvim_buf_get_text(
    bufnr,
    csymbol.range.start.line,
    csymbol.range.start.character,
    csymbol.range['end'].line,
    csymbol.range['end'].character,
    {}
  )
  M._baseline_signature_text = table.concat(lines, '\n')
end

--- Check if the tracked function's signature changed
function M._check_signature_change()
  if not M._tracked_function then return end

  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1] - 1
  local tracked = M._tracked_function

  -- Check if cursor is still within tracked function range
  if cursor_line < tracked.range.start.line or cursor_line > tracked.range['end'].line then
    return
  end

  -- Re-read the function text
  local ok, lines = pcall(vim.api.nvim_buf_get_text,
    bufnr,
    tracked.range.start.line,
    tracked.range.start.character,
    tracked.range['end'].line,
    tracked.range['end'].character,
    {}
  )
  if not ok then return end

  local current_text = table.concat(lines, '\n')

  -- Compare signatures (first line containing the function name)
  if current_text ~= M._baseline_signature_text then
    -- Parse and compare signatures
    local FunctionSignature = require('cmantic.function_signature')
    local old_sig = FunctionSignature.new(M._baseline_signature_text)
    local new_sig = FunctionSignature.new(current_text)

    -- Only mark as changed if name is the same but params or return type differ
    if old_sig.name == new_sig.name and not old_sig:equals(new_sig) then
      M._signature_changed = true
      M._previous_signature = old_sig
    end
  end
end

--- Add Update Signature actions if signature change detected
--- @param actions CmanticAction[]
--- @param csymbol table CSymbol
--- @param doc table SourceDocument
function M._add_update_signature_actions(actions, csymbol, doc)
  if not M._signature_changed then return end
  if not csymbol:is_function() then return end

  if csymbol:is_function_declaration() then
    table.insert(actions, {
      id = 'updateFunctionDefinition',
      title = 'Update Function Definition',
      kind = KIND.QUICK_FIX,
      is_preferred = true,
      execute_fn = function()
        M._signature_changed = false
        M._previous_signature = nil
        require('cmantic.commands.update_signature').execute()
      end,
    })
  elseif csymbol:is_function_definition() then
    table.insert(actions, {
      id = 'updateFunctionDeclaration',
      title = 'Update Function Declaration',
      kind = KIND.QUICK_FIX,
      is_preferred = true,
      execute_fn = function()
        M._signature_changed = false
        M._previous_signature = nil
        require('cmantic.commands.update_signature').execute()
      end,
    })
  end
end
```

**Step 7: Rewrite Public API — execute_by_id, show_actions, helpers**

Replace lines 394–487 with:

```lua
--------------------------------------------------------------------------------
-- Helper Methods
--------------------------------------------------------------------------------

--- Check if a class/struct has a method with the given name
--- @param class_symbol table Class or Struct SourceSymbol
--- @param method_name string Method name to check for
--- @return boolean
function M._has_method(class_symbol, method_name)
  if not class_symbol.children then
    return false
  end
  for _, child in ipairs(class_symbol.children) do
    if child:is_function() and child.name == method_name then
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Execute a code action by its ID
--- @param action_id string The action identifier (e.g., 'addDefinitionMatching')
function M.execute_by_id(action_id)
  -- We need to regenerate actions at current cursor to find the matching one
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local params = {
    range = {
      start = { line = cursor[1] - 1, character = cursor[2] },
      ['end'] = { line = cursor[1] - 1, character = cursor[2] },
    },
  }

  local actions = M.get_applicable_actions(bufnr, params)
  for _, action in ipairs(actions) do
    if action.id == action_id and action.execute_fn then
      action.execute_fn()
      return
    end
  end

  utils.notify('Cmantic action not found: ' .. action_id, vim.log.levels.WARN)
end

--- Execute a code action (legacy API for :Cmantic show_actions)
--- @param action CmanticAction Action table with execute_fn
function M.execute_action(action)
  if action and action.execute_fn then
    action.execute_fn()
  end
end

--- Show applicable actions to user via vim.ui.select
--- @param bufnr number Buffer number
--- @param params table|nil Optional params with range
function M.show_actions(bufnr, params)
  bufnr = bufnr or 0
  -- FIX: Use current cursor position when no params provided
  if not params then
    local cursor = vim.api.nvim_win_get_cursor(0)
    params = {
      range = {
        start = { line = cursor[1] - 1, character = cursor[2] },
        ['end'] = { line = cursor[1] - 1, character = cursor[2] },
      },
    }
  end

  local actions = M.get_applicable_actions(bufnr, params)

  if #actions == 0 then
    utils.notify('No C-mantic actions available at cursor position', 'info')
    return
  end

  local titles = {}
  for _, action in ipairs(actions) do
    if action.disabled then
      table.insert(titles, action.title .. ' (disabled: ' .. (action.disabled_reason or '') .. ')')
    else
      table.insert(titles, action.title)
    end
  end

  vim.ui.select(titles, {
    prompt = 'C-mantic Actions:',
  }, function(choice, idx)
    if choice and idx then
      M.execute_action(actions[idx])
    end
  end)
end

-- Expose KIND constants
M.KIND = KIND

return M
```

**Step 8: Verify module loads**

Run: `nvim --headless -c "lua local m = require('cmantic.code_action'); print('code_action loaded, KIND=' .. vim.inspect(m.KIND))" -c "q" 2>&1`
Expected: Table with QUICK_FIX, REFACTOR, etc.

**Step 9: Commit**

```bash
git add lua/cmantic/code_action.lua
git commit -m "feat: rewrite code_action — 19 actions, bug fixes, Update Signature tracking"
```

---

### Task 3: Update init.lua — Wire Inject Module

**Files:**
- Modify: `lua/cmantic/init.lua`

**Step 1: Update init.lua to enable inject**

Replace entire file with:

```lua
local config = require('cmantic.config')
local code_action = require('cmantic.code_action')
local inject = require('cmantic.code_action_inject')

local M = {}

function M.setup(opts)
  config.merge(opts or {})
  code_action.setup()
  inject.enable()
end

-- Expose code_action module for direct use
M.code_action = code_action

-- Convenience command to show actions at cursor (independent of <leader>ca)
function M.show_actions()
  code_action.show_actions(0)
end

return M
```

**Step 2: Verify**

Run: `nvim --headless +"lua require('cmantic').setup()" -c "lua print('setup ok')" -c "q" 2>&1`
Expected: `setup ok`

**Step 3: Commit**

```bash
git add lua/cmantic/init.lua
git commit -m "feat: wire code_action_inject into setup — enables <leader>ca integration"
```

---

### Task 4: Add FunctionSignature.equals() Method

**Files:**
- Modify: `lua/cmantic/function_signature.lua`

**Step 1: Read current file to understand structure**

Read `lua/cmantic/function_signature.lua` fully to understand the `FunctionSignature` class.

**Step 2: Add `equals` and `from_symbol` methods**

Add these methods to the `FunctionSignature` class (before the `return M`):

```lua
--- Compare this signature with another for equality
--- @param other table Another FunctionSignature
--- @return boolean
function M:equals(other)
  if not other then return false end
  return self.return_type == other.return_type
    and self.name == other.name
    and self.params == other.params
    and self.trailing == other.trailing
end

--- Create a FunctionSignature from a CSymbol and its document
--- @param csymbol table CSymbol
--- @param doc table SourceDocument
--- @return table FunctionSignature
function M.from_symbol(csymbol, doc)
  local text = doc:get_text(csymbol.range)
  return M.new(text)
end
```

**Step 3: Verify**

Run: `nvim --headless -c "lua local FS = require('cmantic.function_signature'); local a = FS.new('void foo(int x)'); local b = FS.new('void foo(int x)'); print('equals: ' .. tostring(a:equals(b)))" -c "q" 2>&1`
Expected: `equals: true`

**Step 4: Commit**

```bash
git add lua/cmantic/function_signature.lua
git commit -m "feat: FunctionSignature.equals() and from_symbol() for Update Signature tracking"
```

---

### Task 5: Remove get_lsp_actions() — No Longer Needed

**Files:**
- Modify: `lua/cmantic/code_action.lua`

**Step 1: Verify get_lsp_actions is not called anywhere**

Search codebase for `get_lsp_actions` — it should only be defined in `code_action.lua` and not called from anywhere else.

**Step 2: Remove the function**

Delete the `M.get_lsp_actions` function (it was lines 465-482 in the old version). The new inject module handles LSP integration directly.

**Step 3: Verify module still loads**

Run: `nvim --headless -c "lua require('cmantic.code_action')" -c "q" 2>&1`

**Step 4: Commit**

```bash
git add lua/cmantic/code_action.lua
git commit -m "refactor: remove unused get_lsp_actions — inject module handles LSP integration"
```

---

### Task 6: Manual Integration Test

**This task requires manual testing with a real Neovim instance and clangd.**

**Test 1: Empty header file**
1. Open Neovim: `nvim test.h`
2. Type nothing (empty file)
3. Press `<leader>ca`
4. Expected: See "Add Header Guard", "Add Include", "Create Matching Source File", "Add Definitions..." among the actions (mixed with clangd's own actions)

**Test 2: Function declaration**
1. Create `test.h` with a class and a function declaration:
   ```cpp
   #pragma once
   class Foo {
   public:
     void doSomething(int x);
   };
   ```
2. Place cursor on `doSomething`
3. Press `<leader>ca`
4. Expected: See "Add Definition in matching source file" and "Add Definition in this file"

**Test 3: Member variable**
1. Add a member variable to the class:
   ```cpp
   int value_;
   ```
2. Place cursor on `value_`
3. Press `<leader>ca`
4. Expected: See "Generate Getter for "value_"", "Generate Setter for "value_"", "Generate Getter and Setter for "value_""

**Test 4: Class name**
1. Place cursor on `Foo` (class name)
2. Press `<leader>ca`
3. Expected: See "Generate Equality Operators for "Foo"", "Generate Relational Operators for "Foo"", "Generate Stream Output Operator for "Foo""

**Test 5: :Cmantic independent entry**
1. Press `:Cmantic` (no args)
2. Expected: See same actions as `<leader>ca` but in a separate vim.ui.select prompt with "C-mantic Actions:" header

**Test 6: Direct command still works**
1. Run `:Cmantic AddHeaderGuard`
2. Expected: Header guard added to file

**Step: Final commit if any fixes needed**

```bash
git add -A
git commit -m "fix: integration test fixes for code action injection"
```

---

### Task 7: Update AGENTS.md — Reflect New Architecture

**Files:**
- Modify: `AGENTS.md`

**Step 1: Update the WHERE TO LOOK table**

Add entry for `code_action_inject.lua`:

```
| Hook into <leader>ca | `code_action_inject.lua` | `code_action.lua` |
```

**Step 2: Update ARCHITECTURE section**

Add `code_action_inject` to the data flow:

```
User action → code_action.lua or :Cmantic
  → code_action_inject.lua (intercepts vim.ui.select for <leader>ca)
  → SourceDocument (buffer + LSP symbols)
    → CSymbol (at cursor position)
      → parsing.lua (mask text, extract structure)
        → SourceDocument.insert_text (apply changes)
```

**Step 3: Update KNOWN ISSUES**

Remove or update items about code action not appearing in `<leader>ca`.

**Step 4: Commit**

```bash
git add AGENTS.md
git commit -m "docs: update AGENTS.md for code action injection architecture"
```
