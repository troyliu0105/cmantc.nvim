--- LSP Code Action Provider for cmantic.nvim
--- Ported from vscode-cmantic src/CodeActionProvider.ts
--- Determines which C-mantic actions are applicable at cursor position.

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
  SOURCE_ORGANIZE_IMPORTS = 'source.organizeImports',
}

--------------------------------------------------------------------------------
-- Setup and Registration
--------------------------------------------------------------------------------

--- Register the code action provider
--- Uses autocmd to set up per-buffer code action source
function M.setup()
  local group = vim.api.nvim_create_augroup('cmantic_code_actions', { clear = true })
  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = { 'c', 'cpp', 'objc', 'objcpp', 'cuda', 'proto' },
    callback = function(args)
      M._register_provider(args.buf)
    end,
  })

  -- Also set up for already-loaded buffers
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      local ft = vim.bo[bufnr].filetype
      if ft == 'c' or ft == 'cpp' or ft == 'objc' or ft == 'objcpp' or ft == 'cuda' or ft == 'proto' then
        M._register_provider(bufnr)
      end
    end
  end
end

--- Register buffer-specific provider state
--- @param bufnr number Buffer number
function M._register_provider(bufnr)
  -- Store a reference that this buffer has cmantic actions available
  vim.b[bufnr].cmantic_enabled = true
end

--------------------------------------------------------------------------------
-- Main Logic
--------------------------------------------------------------------------------

--- Get all applicable actions at the given position
--- @param bufnr number Buffer number
--- @param params table { range = { start = { line, character }, ['end'] = { line, character } } }
--- @return table[] Array of action tables
function M.get_applicable_actions(bufnr, params)
  local actions = {}

  -- Check if LSP client is attached
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'clangd' })
  if not clients or #clients == 0 then
    return actions
  end

  -- Get cursor position from params
  local position = params.range and params.range.start
  if not position then
    -- Fallback to current cursor position
    local cursor = vim.api.nvim_win_get_cursor(0)
    position = { line = cursor[1] - 1, character = cursor[2] }
  end

  -- Create SourceDocument
  local doc = SourceDocument.new(bufnr)

  -- Get symbol at position
  local symbol = doc:get_symbol_at_position(position)
  if not symbol then
    -- No symbol at position, check for file-level actions
    return M._get_file_level_actions(doc, bufnr)
  end

  -- Wrap as CSymbol if needed for advanced checks
  local csymbol = symbol
  if not symbol.document then
    csymbol = CSymbol.new(symbol, doc)
  end

  -- Determine applicable actions based on symbol type

  -- 1. Function declaration (not definition, not deleted, not pure virtual)
  if csymbol:is_function() and csymbol:is_function_declaration() then
    M._add_function_declaration_actions(actions, csymbol, doc, bufnr)
  end

  -- 2. Function definition
  if csymbol:is_function() and csymbol:is_function_definition() then
    M._add_function_definition_actions(actions, csymbol, doc, bufnr)
  end

  -- 3. Member variable (field/property in class/struct)
  if csymbol:is_member_variable() then
    M._add_member_variable_actions(actions, csymbol, doc, bufnr)
  end

  -- 4. Class/struct context - operator generation
  if csymbol:is_class_type() then
    M._add_class_actions(actions, csymbol, doc, bufnr)
  end

  -- 5. File-level actions (header guards, create source)
  local file_actions = M._get_file_level_actions(doc, bufnr)
  for _, action in ipairs(file_actions) do
    table.insert(actions, action)
  end

  return actions
end

--- Get file-level actions (not dependent on specific symbol)
--- @param doc table SourceDocument
--- @param bufnr number Buffer number
--- @return table[] Array of actions
function M._get_file_level_actions(doc, bufnr)
  local actions = {}

  -- Header file without header guard
  if doc:is_header() and not doc:has_header_guard() then
    table.insert(actions, {
      title = 'C-mantic: Add Header Guard',
      kind = KIND.REFACTOR_REWRITE,
      action = function()
        M._add_header_guard(doc, bufnr)
      end,
    })
  end

  -- Header file - create matching source file
  if doc:is_header() then
    local matching_uri = header_source.get_matching(doc.uri)
    if not matching_uri then
      table.insert(actions, {
        title = 'C-mantic: Create Matching Source File',
        kind = KIND.REFACTOR_REWRITE,
        action = function()
          M._create_matching_source(doc, bufnr)
        end,
      })
    end
  end

  return actions
end

--------------------------------------------------------------------------------
-- Action Generators
--------------------------------------------------------------------------------

--- Add actions for function declarations
--- @param actions table[] Array to append actions to
--- @param csymbol table CSymbol
--- @param doc table SourceDocument
--- @param bufnr number
function M._add_function_declaration_actions(actions, csymbol, doc, bufnr)
  -- Skip constructors, destructors, and pure virtual
  if csymbol:is_constructor() or csymbol:is_destructor() then
    return
  end
  if csymbol:is_pure_virtual() then
    return
  end

  -- Check for matching source file
  local matching_uri = header_source.get_matching(doc.uri)

  if doc:is_header() and matching_uri then
    -- Add Definition in source file
    table.insert(actions, {
      title = 'C-mantic: Add Definition in source file',
      kind = KIND.REFACTOR_REWRITE,
      action = function()
        M._add_definition_in_source(csymbol, doc, matching_uri)
      end,
    })
  end

  if doc:is_header() then
    -- Add Definition in this file (inline)
    table.insert(actions, {
      title = 'C-mantic: Add Definition in this file',
      kind = KIND.REFACTOR_REWRITE,
      action = function()
        M._add_definition_inline(csymbol, doc, bufnr)
      end,
    })
  end
end

--- Add actions for function definitions
--- @param actions table[] Array to append actions to
--- @param csymbol table CSymbol
--- @param doc table SourceDocument
--- @param bufnr number
function M._add_function_definition_actions(actions, csymbol, doc, bufnr)
  -- Skip constructors and destructors
  if csymbol:is_constructor() or csymbol:is_destructor() then
    return
  end

  -- Check for matching header file
  local matching_uri = header_source.get_matching(doc.uri)

  if doc:is_source() and matching_uri then
    -- Add Declaration in header file
    table.insert(actions, {
      title = 'C-mantic: Add Declaration',
      kind = KIND.REFACTOR_REWRITE,
      action = function()
        M._add_declaration_in_header(csymbol, doc, matching_uri)
      end,
    })
  end

  -- Check if inside a class (definition in same file as class)
  local parent = csymbol.parent
  if parent and parent:is_class_type() then
    table.insert(actions, {
      title = 'C-mantic: Add Declaration in class',
      kind = KIND.REFACTOR_REWRITE,
      action = function()
        M._add_declaration_in_class(csymbol, doc, bufnr)
      end,
    })
  end
end

--- Add actions for member variables
--- @param actions table[] Array to append actions to
--- @param csymbol table CSymbol
--- @param doc table SourceDocument
--- @param bufnr number
function M._add_member_variable_actions(actions, csymbol, doc, bufnr)
  local getter_name = csymbol:getter_name()
  local setter_name = csymbol:setter_name()
  local parent = csymbol.parent

  if not parent then
    return
  end

  -- Check if getter exists
  local has_getter = M._has_method(parent, getter_name)
  -- Check if setter exists
  local has_setter = M._has_method(parent, setter_name)

  if not has_getter then
    table.insert(actions, {
      title = 'C-mantic: Generate Getter',
      kind = KIND.REFACTOR_EXTRACT,
      action = function()
        M._generate_getter(csymbol, doc, bufnr)
      end,
    })
  end

  if not has_setter then
    table.insert(actions, {
      title = 'C-mantic: Generate Setter',
      kind = KIND.REFACTOR_EXTRACT,
      action = function()
        M._generate_setter(csymbol, doc, bufnr)
      end,
    })
  end

  if not has_getter and not has_setter then
    table.insert(actions, {
      title = 'C-mantic: Generate Getter and Setter',
      kind = KIND.REFACTOR_EXTRACT,
      action = function()
        M._generate_getter_and_setter(csymbol, doc, bufnr)
      end,
    })
  end
end

--- Add actions for class/struct symbols
--- @param actions table[] Array to append actions to
--- @param csymbol table CSymbol
--- @param doc table SourceDocument
--- @param bufnr number
function M._add_class_actions(actions, csymbol, doc, bufnr)
  -- Generate Equality Operators (==, !=)
  table.insert(actions, {
    title = 'C-mantic: Generate Equality Operators',
    kind = KIND.REFACTOR_EXTRACT,
    action = function()
      M._generate_equality_operators(csymbol, doc, bufnr)
    end,
  })

  -- Generate Relational Operators (<, >, <=, >=)
  table.insert(actions, {
    title = 'C-mantic: Generate Relational Operators',
    kind = KIND.REFACTOR_EXTRACT,
    action = function()
      M._generate_relational_operators(csymbol, doc, bufnr)
    end,
  })

  -- Generate Stream Output Operator (<<)
  table.insert(actions, {
    title = 'C-mantic: Generate Stream Output Operator',
    kind = KIND.REFACTOR_EXTRACT,
    action = function()
      M._generate_stream_operator(csymbol, doc, bufnr)
    end,
  })
end

--------------------------------------------------------------------------------
-- Action Implementations (Stubs - to be implemented in separate modules)
--------------------------------------------------------------------------------

function M._add_definition_in_source(csymbol, doc, source_uri)
  local add_def = require('cmantic.commands.add_definition')
  add_def.execute_in_source()
end

function M._add_definition_inline(csymbol, doc, bufnr)
  local add_def = require('cmantic.commands.add_definition')
  add_def.execute_in_current()
end

function M._add_declaration_in_header(csymbol, doc, header_uri)
  local add_decl = require('cmantic.commands.add_declaration')
  add_decl.execute()
end

function M._add_declaration_in_class(csymbol, doc, bufnr)
  local add_decl = require('cmantic.commands.add_declaration')
  add_decl.execute()
end

function M._generate_getter(csymbol, doc, bufnr)
  local gen = require('cmantic.commands.generate_getter_setter')
  gen.execute({ mode = 'getter' })
end

function M._generate_setter(csymbol, doc, bufnr)
  local gen = require('cmantic.commands.generate_getter_setter')
  gen.execute({ mode = 'setter' })
end

function M._generate_getter_and_setter(csymbol, doc, bufnr)
  local gen = require('cmantic.commands.generate_getter_setter')
  gen.execute({ mode = 'both' })
end

function M._generate_equality_operators(csymbol, doc, bufnr)
  local gen = require('cmantic.commands.generate_operators')
  gen.execute({ mode = 'equality' })
end

function M._generate_relational_operators(csymbol, doc, bufnr)
  local gen = require('cmantic.commands.generate_operators')
  gen.execute({ mode = 'relational' })
end

function M._generate_stream_operator(csymbol, doc, bufnr)
  local gen = require('cmantic.commands.generate_operators')
  gen.execute({ mode = 'stream' })
end

function M._add_header_guard(doc, bufnr)
  local cmd = require('cmantic.commands.add_header_guard')
  cmd.execute()
end

function M._create_matching_source(doc, bufnr)
  local cmd = require('cmantic.commands.create_source_file')
  cmd.execute()
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

--- Execute a code action
--- @param action table Action table with action callback
function M.execute_action(action)
  if action and action.action then
    action.action()
  end
end

--- Show applicable actions to user via vim.ui.select
--- @param bufnr number Buffer number
--- @param params table|nil Optional params with range
function M.show_actions(bufnr, params)
  bufnr = bufnr or 0
  params = params or {
    range = {
      start = { line = 0, character = 0 },
      ['end'] = { line = 0, character = 0 },
    },
  }

  local actions = M.get_applicable_actions(bufnr, params)

  if #actions == 0 then
    utils.notify('No C-mantic actions available at cursor position', 'info')
    return
  end

  local titles = {}
  for _, action in ipairs(actions) do
    table.insert(titles, action.title)
  end

  vim.ui.select(titles, {
    prompt = 'C-mantic Actions:',
  }, function(choice, idx)
    if choice and idx then
      M.execute_action(actions[idx])
    end
  end)
end

--- Get actions for LSP integration (returns LSP-compatible format)
--- @param bufnr number Buffer number
--- @param params table LSP CodeActionParams
--- @return table[] Array of LSP CodeActions
function M.get_lsp_actions(bufnr, params)
  local actions = M.get_applicable_actions(bufnr, params)
  local lsp_actions = {}

  for _, action in ipairs(actions) do
    table.insert(lsp_actions, {
      title = action.title,
      kind = action.kind,
      command = {
        title = action.title,
        command = 'cmantic.executeAction',
        arguments = { action },
      },
    })
  end

  return lsp_actions
end

-- Expose KIND constants
M.KIND = KIND

return M
