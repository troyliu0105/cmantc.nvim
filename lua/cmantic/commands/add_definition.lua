--- Add Definition command for cmantic.nvim
--- Ported from vscode-cmantic src/commands/addDefinition.ts
--- Generates function definitions from declarations.

local M = {}

local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')
local header_source = require('cmantic.header_source')
local utils = require('cmantic.utils')
local config = require('cmantic.config')

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Get cursor position as LSP position
--- @return table { line = number, character = number }
local function get_cursor_position()
  local cursor = vim.api.nvim_win_get_cursor(0)
  return { line = cursor[1] - 1, character = cursor[2] }
end

--- Wrap a SourceSymbol as CSymbol if needed
--- @param symbol table SourceSymbol
--- @param doc table SourceDocument
--- @return table CSymbol
local function ensure_csymbol(symbol, doc)
  if symbol.document then
    return symbol
  end
  return CSymbol.new(symbol, doc)
end

--- Add blank lines before insertion if needed
--- @param target_doc table SourceDocument
--- @param position table Position
--- @param num_lines number Number of blank lines to add
local function add_blank_lines_before(target_doc, position, num_lines)
  if num_lines <= 0 then
    return
  end
  local blank_text = string.rep('\n', num_lines)
  target_doc:insert_text(position, blank_text)
end

--- Add blank lines after insertion if needed
--- @param target_doc table SourceDocument
--- @param position table Position
--- @param num_lines number Number of blank lines to add
local function add_blank_lines_after(target_doc, position, num_lines)
  if num_lines <= 0 then
    return
  end
  local blank_text = string.rep('\n', num_lines)
  target_doc:insert_text(position, blank_text)
end

--- Reveal the new definition in the editor
--- @param target_bufnr number Target buffer number
--- @param line number Line number (0-indexed)
local function reveal_definition(target_bufnr, line)
  if not config.values.reveal_new_definition then
    return
  end

  -- Switch to the target buffer if different from current
  local current_bufnr = vim.api.nvim_get_current_buf()
  if current_bufnr ~= target_bufnr then
    vim.api.nvim_win_set_buf(0, target_bufnr)
  end

  -- Set cursor to the new definition (line is 0-indexed, cursor is 1-indexed)
  vim.api.nvim_win_set_cursor(0, { line + 1, 0 })
end

--------------------------------------------------------------------------------
-- Main Functions
--------------------------------------------------------------------------------

--- Add definition in matching source file
--- Algorithm:
--- 1. Get current buffer, create SourceDocument
--- 2. Get CSymbol at cursor position
--- 3. Verify it's a function declaration
--- 4. Find matching source file
--- 5. Open source file, create SourceDocument
--- 6. Find smart position for definition
--- 7. Generate and insert definition
--- 8. Optionally reveal new definition
function M.execute_in_source()
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = SourceDocument.new(bufnr)
  local position = get_cursor_position()

  -- Get symbol at cursor
  local symbol = doc:get_symbol_at_position(position)
  if not symbol then
    utils.notify('No symbol found at cursor position', 'warn')
    return
  end

  -- Wrap as CSymbol
  local csymbol = ensure_csymbol(symbol, doc)

  -- Verify it's a function declaration
  if not csymbol:is_function() then
    utils.notify('Symbol is not a function', 'warn')
    return
  end

  if not csymbol:is_function_declaration() then
    utils.notify('Symbol is not a function declaration', 'warn')
    return
  end

  -- Skip pure virtual and deleted/defaulted functions
  if csymbol:is_pure_virtual() then
    utils.notify('Cannot add definition for pure virtual function', 'warn')
    return
  end

  if csymbol:is_deleted_or_defaulted() then
    utils.notify('Cannot add definition for deleted/defaulted function', 'warn')
    return
  end

  -- Find matching source file
  local matching_uri = header_source.get_matching(doc.uri)
  if not matching_uri then
    utils.notify('No matching source file found', 'error')
    return
  end

  -- Open source file and create SourceDocument
  local target_bufnr = vim.uri_to_bufnr(matching_uri)
  if not vim.api.nvim_buf_is_loaded(target_bufnr) then
    vim.fn.bufload(target_bufnr)
  end
  local target_doc = SourceDocument.new(target_bufnr)

  -- Find smart position for the definition
  local proposed_pos = doc:find_smart_position_for_function_definition(csymbol, target_doc)
  local insert_position = proposed_pos.position or proposed_pos

  -- Generate definition text
  local definition_text = csymbol:new_function_definition(target_doc, insert_position)
  if not definition_text or definition_text == '' then
    utils.notify('Failed to generate definition', 'error')
    return
  end

  -- Add blank line before if needed
  local blank_before = proposed_pos.options and proposed_pos.options.blank_lines_before or 1
  if blank_before > 0 then
    add_blank_lines_before(target_doc, insert_position, blank_before)
    -- Adjust position after adding blank lines
    insert_position = { line = insert_position.line + blank_before, character = 0 }
  end

  -- Insert the definition
  target_doc:insert_text(insert_position, definition_text)

  -- Add blank line after if needed
  local blank_after = proposed_pos.options and proposed_pos.options.blank_lines_after or 1
  if blank_after > 0 then
    -- Calculate end position of inserted text
    local lines = vim.split(definition_text, '\n')
    local end_line = insert_position.line + #lines - 1
    add_blank_lines_after(target_doc, { line = end_line + 1, character = 0 }, blank_after)
  end

  utils.notify('Added definition for: ' .. csymbol.name, 'info')

  -- Reveal new definition
  reveal_definition(target_bufnr, insert_position.line)
end

--- Add definition in current file (inline)
--- Same as execute_in_source but inserts in current file.
--- Useful for template functions or single-file development.
function M.execute_in_current()
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = SourceDocument.new(bufnr)
  local position = get_cursor_position()

  -- Get symbol at cursor
  local symbol = doc:get_symbol_at_position(position)
  if not symbol then
    utils.notify('No symbol found at cursor position', 'warn')
    return
  end

  -- Wrap as CSymbol
  local csymbol = ensure_csymbol(symbol, doc)

  -- Verify it's a function declaration
  if not csymbol:is_function() then
    utils.notify('Symbol is not a function', 'warn')
    return
  end

  if not csymbol:is_function_declaration() then
    utils.notify('Symbol is not a function declaration', 'warn')
    return
  end

  -- Skip pure virtual and deleted/defaulted functions
  if csymbol:is_pure_virtual() then
    utils.notify('Cannot add definition for pure virtual function', 'warn')
    return
  end

  if csymbol:is_deleted_or_defaulted() then
    utils.notify('Cannot add definition for deleted/defaulted function', 'warn')
    return
  end

  -- Find smart position in current file
  local proposed_pos = doc:find_smart_position_for_function_definition(csymbol, doc)
  local insert_position = proposed_pos.position or proposed_pos

  -- Generate definition text (with inline keyword for headers)
  local definition_text = csymbol:new_function_definition(doc, insert_position)
  if not definition_text or definition_text == '' then
    utils.notify('Failed to generate definition', 'error')
    return
  end

  -- Add blank line before if needed
  local blank_before = proposed_pos.options and proposed_pos.options.blank_lines_before or 1
  if blank_before > 0 then
    add_blank_lines_before(doc, insert_position, blank_before)
    -- Adjust position after adding blank lines
    insert_position = { line = insert_position.line + blank_before, character = 0 }
  end

  -- Insert the definition
  doc:insert_text(insert_position, definition_text)

  -- Add blank line after if needed
  local blank_after = proposed_pos.options and proposed_pos.options.blank_lines_after or 1
  if blank_after > 0 then
    -- Calculate end position of inserted text
    local lines = vim.split(definition_text, '\n')
    local end_line = insert_position.line + #lines - 1
    add_blank_lines_after(doc, { line = end_line + 1, character = 0 }, blank_after)
  end

  utils.notify('Added inline definition for: ' .. csymbol.name, 'info')

  -- Reveal new definition
  reveal_definition(bufnr, insert_position.line)
end

--- Add multiple definitions (batch mode)
--- 1. Get all function declarations that don't have definitions
--- 2. Present list to user via vim.ui.select
--- 3. Generate and insert selected definitions
function M.execute_batch()
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = SourceDocument.new(bufnr)

  -- Check if we're in a header file
  if not doc:is_header() then
    utils.notify('Batch mode only works in header files', 'warn')
    return
  end

  -- Find matching source file
  local matching_uri = header_source.get_matching(doc.uri)
  if not matching_uri then
    utils.notify('No matching source file found', 'error')
    return
  end

  -- Get all symbols
  local symbols = doc:get_c_symbols()
  if not symbols or #symbols == 0 then
    utils.notify('No symbols found in document', 'warn')
    return
  end

  -- Collect all function declarations without definitions
  local declarations = {}
  local function collect_declarations(sym_list)
    for _, symbol in ipairs(sym_list) do
      local csymbol = ensure_csymbol(symbol, doc)

      if csymbol:is_function() and csymbol:is_function_declaration() then
        -- Skip pure virtual, deleted, defaulted
        if not csymbol:is_pure_virtual() and not csymbol:is_deleted_or_defaulted() then
          -- Check if definition already exists
          local def = csymbol:find_definition()
          if not def or def.uri ~= matching_uri then
            table.insert(declarations, csymbol)
          end
        end
      end

      -- Recurse into children
      if symbol.children and #symbol.children > 0 then
        collect_declarations(symbol.children)
      end
    end
  end

  collect_declarations(symbols)

  if #declarations == 0 then
    utils.notify('No function declarations without definitions found', 'info')
    return
  end

  -- Present list to user
  local items = {}
  for i, csymbol in ipairs(declarations) do
    table.insert(items, {
      idx = i,
      name = csymbol.name,
      detail = csymbol.detail or '',
      display = csymbol.name .. (csymbol.detail or ''),
    })
  end

  vim.ui.select(items, {
    prompt = 'Select function to add definition:',
    format_item = function(item)
      return item.display
    end,
  }, function(choice)
    if not choice then
      return
    end

    local csymbol = declarations[choice.idx]
    if not csymbol then
      return
    end

    -- Open source file and create SourceDocument
    local target_bufnr = vim.uri_to_bufnr(matching_uri)
    if not vim.api.nvim_buf_is_loaded(target_bufnr) then
      vim.fn.bufload(target_bufnr)
    end
    local target_doc = SourceDocument.new(target_bufnr)

    -- Find smart position for the definition
    local proposed_pos = doc:find_smart_position_for_function_definition(csymbol, target_doc)
    local insert_position = proposed_pos.position or proposed_pos

    -- Generate definition text
    local definition_text = csymbol:new_function_definition(target_doc, insert_position)
    if not definition_text or definition_text == '' then
      utils.notify('Failed to generate definition', 'error')
      return
    end

    -- Add blank line before if needed
    local blank_before = proposed_pos.options and proposed_pos.options.blank_lines_before or 1
    if blank_before > 0 then
      add_blank_lines_before(target_doc, insert_position, blank_before)
      insert_position = { line = insert_position.line + blank_before, character = 0 }
    end

    -- Insert the definition
    target_doc:insert_text(insert_position, definition_text)

    -- Add blank line after if needed
    local blank_after = proposed_pos.options and proposed_pos.options.blank_lines_after or 1
    if blank_after > 0 then
      local lines = vim.split(definition_text, '\n')
      local end_line = insert_position.line + #lines - 1
      add_blank_lines_after(target_doc, { line = end_line + 1, character = 0 }, blank_after)
    end

    utils.notify('Added definition for: ' .. csymbol.name, 'info')

    -- Reveal new definition
    reveal_definition(target_bufnr, insert_position.line)
  end)
end

--- Execute command (default: execute_in_source)
--- @param opts table|nil Optional params with mode = 'source' | 'current' | 'batch'
function M.execute(opts)
  opts = opts or {}
  local mode = opts.mode or 'source'

  if mode == 'source' then
    M.execute_in_source()
  elseif mode == 'current' then
    M.execute_in_current()
  elseif mode == 'batch' then
    M.execute_batch()
  else
    utils.notify('Unknown mode: ' .. mode, 'error')
  end
end

return M
