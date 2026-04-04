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
