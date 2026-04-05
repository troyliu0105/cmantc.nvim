--- Move Definition command for cmantic.nvim
--- Ported from vscode-cmantic src/commands/moveDefinition.ts
--- Moves function definitions between header/source files and in/out of class bodies.

local M = {}

local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')
local header_source = require('cmantic.header_source')
local utils = require('cmantic.utils')
local config = require('cmantic.config')
local parse = require('cmantic.parsing')

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Clamp range end character to actual line length (LSP ranges are exclusive)
--- @param doc table SourceDocument
--- @param range table Range with start/end positions
local function clamp_range_end(doc, range)
  if range['end'] then
    local lines = doc:get_lines()
    local num_lines = #lines
    if range.start.line >= num_lines then
      range.start.line = num_lines - 1
      range.start.character = 0
    end
    if range['end'].line >= num_lines then
      range['end'].line = num_lines - 1
      range['end'].character = #(lines[num_lines] or '')
    else
      local max_col = #(lines[range['end'].line + 1] or '')
      if range['end'].character >= max_col then
        range['end'].character = max_col
      end
    end
  end
end

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

--- Get the immediate scope (class or namespace) of a symbol
--- @param csymbol table CSymbol
--- @return table|nil The immediate parent scope or nil
local function get_immediate_scope(csymbol)
  local scopes = csymbol:scopes()
  if not scopes or #scopes == 0 then
    return nil
  end
  return scopes[#scopes]
end

--- Check if a symbol's definition is inside a class body
--- @param csymbol table CSymbol
--- @return boolean
local function is_inside_class(csymbol)
  local immediate_scope = get_immediate_scope(csymbol)
  return immediate_scope and immediate_scope:is_class_type()
end

--- Get the range including preceding comments
--- @param doc table SourceDocument
--- @param csymbol table CSymbol
--- @return table Range including comments
local function get_range_with_comments(doc, csymbol)
  local true_start = csymbol:true_start()
  local range_end = csymbol.range['end']

  -- Walk backwards to find comments
  local lines = doc:get_lines()
  if not lines then
    return { start = true_start, ['end'] = range_end }
  end

  local comment_start_line = true_start.line
  local in_block_comment = false

  -- Look for consecutive comment lines above the function
  for line_idx = true_start.line - 1, 0, -1 do
    local line = lines[line_idx + 1] or ''
    local trimmed = parse.trim(line)

    if in_block_comment then
      comment_start_line = line_idx
      if trimmed:match('^/%*') then
        in_block_comment = false
      end
    elseif trimmed:match('^//') or trimmed:match('^/%*') then
      comment_start_line = line_idx
    elseif trimmed:match('%*/$') then
      comment_start_line = line_idx
      in_block_comment = true
    elseif trimmed == '' then
      if trimmed == '' and comment_start_line == line_idx + 1 then
        break
      end
      comment_start_line = line_idx
    else
      break
    end
  end

  return {
    start = { line = comment_start_line, character = 0 },
    ['end'] = range_end,
  }
end

--- Strip scope resolution prefix from definition text when moving into class
--- @param text string Definition text
--- @param scope_string string Scope string like "Class::" or "Namespace::Class::"
--- @return string Text with scope prefix removed
local function strip_scope_prefix(text, scope_string)
  if not scope_string or scope_string == '' then
    return text
  end

  -- Escape special characters in scope_string for pattern matching
  local escaped = scope_string:gsub('([%(%)%.%%%+%-%*%?%[%]%^%$])', '%%%1')

  -- Remove the scope prefix before the function name
  return text:gsub(escaped, '', 1)
end

--------------------------------------------------------------------------------
-- Main Functions
--------------------------------------------------------------------------------

--- Move function definition to matching source file
--- Algorithm:
--- 1. Get CSymbol at cursor — must be a function definition
--- 2. Check if a declaration already exists
--- 3. If no declaration exists, generate and insert declaration in header
--- 4. Get the full definition text (from true_start to end of function body)
--- 5. Strip the definition from the current file
--- 6. Find matching source file, open it
--- 7. Generate definition text with scope string
--- 8. Find smart position in source file
--- 9. Insert definition
--- 10. If config.values.always_move_comments, also move any comments above the function
function M.execute_to_source()
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

  -- Verify it's a function definition
  if not csymbol:is_function() then
    utils.notify('Symbol is not a function', 'warn')
    return
  end

  if not csymbol:is_function_definition() then
    utils.notify('Symbol is not a function definition', 'warn')
    return
  end

  -- Check if we're in a header file
  if not doc:is_header() then
    utils.notify('Can only move definition from header to source', 'warn')
    return
  end

  -- Find matching source file
  local source_uri = header_source.get_matching(doc.uri)
  if not source_uri then
    utils.notify('No matching source file found', 'error')
    return
  end

  -- Check if a declaration already exists
  local decl_location = csymbol:find_declaration()
  local declaration_exists = decl_location and decl_location.uri == doc.uri
  local decl_text = nil

  if not declaration_exists then
    decl_text = csymbol:new_function_declaration()
    if not decl_text or decl_text == '' then
      utils.notify('Failed to generate declaration', 'error')
      return
    end
  end

  local def_range = config.values.always_move_comments
      and get_range_with_comments(doc, csymbol)
    or { start = csymbol:true_start(), ['end'] = csymbol.range['end'] }

  clamp_range_end(doc, def_range)
  local def_text = doc:get_text(def_range)

  local leading_comments = ''
  if config.values.always_move_comments then
    local true_start = csymbol:true_start()
    if def_range.start.line ~= true_start.line or def_range.start.character ~= true_start.character then
      leading_comments = doc:get_text({ start = def_range.start, ['end'] = true_start })
    end
  end

  -- Open source file
  local target_bufnr = vim.uri_to_bufnr(source_uri)
  if not vim.api.nvim_buf_is_loaded(target_bufnr) then
    vim.fn.bufload(target_bufnr)
  end
  local target_doc = SourceDocument.new(target_bufnr)

  -- Find smart position for the definition
  local proposed_pos = doc:find_smart_position_for_function_definition(csymbol, target_doc)
  local insert_position = proposed_pos.position or proposed_pos

  -- Generate definition text with scope
  local scope_string = csymbol:scope_string(target_doc, insert_position, false)
  local definition_text = csymbol:format_declaration(target_doc, insert_position, scope_string, true)

  if not definition_text or definition_text == '' then
    utils.notify('Failed to generate definition', 'error')
    return
  end

  local body_text = def_text
  if leading_comments ~= '' then
    body_text = def_text:sub(#leading_comments + 1)
  end

  local formatted_brace = definition_text:find('{', 1, true)
  local original_brace = body_text:find('{', 1, true)
  if formatted_brace and original_brace then
    local formatted_end = formatted_brace - 1
    while formatted_end > 0 and definition_text:sub(formatted_end, formatted_end):match('%s') do
      formatted_end = formatted_end - 1
    end

    local original_start = original_brace
    while original_start > 1 and body_text:sub(original_start - 1, original_start - 1):match('%s') do
      original_start = original_start - 1
    end

    definition_text = leading_comments
      .. definition_text:sub(1, formatted_end)
      .. body_text:sub(original_start)
  elseif leading_comments ~= '' then
    definition_text = leading_comments .. definition_text
  end

  doc:replace_text(def_range, '')

  if not declaration_exists then
    local decl_pos = config.values.always_move_comments and def_range.start or csymbol:true_start()
    doc:insert_text(decl_pos, decl_text .. '\n')
  end

  -- Add blank line before
  target_doc:insert_text(insert_position, '\n')
  insert_position = { line = insert_position.line + 1, character = 0 }

  -- Insert the definition
  target_doc:insert_text(insert_position, definition_text)

  utils.notify('Moved definition to source file: ' .. csymbol.name, 'info')

  -- Reveal new definition
  reveal_definition(target_bufnr, insert_position.line)
end

--- Move definition into or out of class body
--- Algorithm:
--- 1. Get CSymbol at cursor
--- 2. If definition is outside class (parent is namespace or file-level):
---    - Move it INTO the class body
---    - Strip scope string prefix
---    - Find position in class (matching access specifier)
---    - Insert inline
--- 3. If definition is inside class:
---    - Move it OUT of the class body
---    - Add scope string prefix
---    - Find position after class closing brace
---    - Insert outside
function M.execute_into_or_out_of_class()
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

  -- Verify it's a function definition
  if not csymbol:is_function() then
    utils.notify('Symbol is not a function', 'warn')
    return
  end

  if not csymbol:is_function_definition() then
    utils.notify('Symbol is not a function definition', 'warn')
    return
  end

  local inside_class = is_inside_class(csymbol)

  if inside_class then
    -- Move OUT of class
    M._move_out_of_class(doc, csymbol)
  else
    -- Move INTO class
    M._move_into_class(doc, csymbol)
  end
end

--- Move definition out of class body
--- @param doc table SourceDocument
--- @param csymbol table CSymbol
function M._move_out_of_class(doc, csymbol)
  -- Get the parent class
  local parent_class = get_immediate_scope(csymbol)
  if not parent_class or not parent_class:is_class_type() then
    utils.notify('Function is not inside a class', 'warn')
    return
  end

  -- Get the definition range (including comments if configured)
  local def_range = config.values.always_move_comments
      and get_range_with_comments(doc, csymbol)
    or { start = csymbol:true_start(), ['end'] = csymbol.range['end'] }

  clamp_range_end(doc, def_range)

  -- Get the definition text
  local def_text = doc:get_text(def_range)

  -- Compute scope string
  local scope_string = csymbol:scope_string(doc, csymbol.range.start, false)

  -- Add scope prefix to the definition
  local text_with_scope = csymbol:format_declaration(doc, parent_class.range['end'], scope_string, doc:is_header())

  -- Remove the original definition
  doc:replace_text(def_range, '')

  -- Find position after class closing brace
  local class_end = parent_class.range['end']
  local insert_position = { line = class_end.line + 1, character = 0 }

  -- Insert blank line and definition
  doc:insert_text(insert_position, '\n' .. text_with_scope)

  utils.notify('Moved definition out of class: ' .. csymbol.name, 'info')

  -- Reveal new position
  reveal_definition(doc.bufnr, insert_position.line + 1)
end

--- Move definition into class body
--- @param doc table SourceDocument
--- @param csymbol table CSymbol
function M._move_into_class(doc, csymbol)
  -- Find the parent class from scopes
  local scopes = csymbol:scopes()
  local parent_class = nil

  -- Walk scopes to find the class (skipping namespaces)
  for i = #scopes, 1, -1 do
    if scopes[i]:is_class_type() then
      parent_class = scopes[i]
      break
    end
  end

  if not parent_class then
    utils.notify('No parent class found for this function', 'warn')
    return
  end

  -- Get the class definition to find proper position
  local class_location = parent_class.find_definition and parent_class:find_definition()
  if not class_location or class_location.uri ~= doc.uri then
    utils.notify('Could not find class definition in current file', 'warn')
    return
  end

  -- Get the class symbol from the document
  local class_symbol = doc:get_symbol_at_position(class_location.range.start)
  if not class_symbol then
    utils.notify('Could not find class symbol', 'warn')
    return
  end

  -- Wrap as CSymbol
  local class_csymbol = ensure_csymbol(class_symbol, doc)

  -- Get the definition range (including comments if configured)
  local def_range = config.values.always_move_comments
      and get_range_with_comments(doc, csymbol)
    or { start = csymbol:true_start(), ['end'] = csymbol.range['end'] }

  -- Get the definition text
  local def_text = doc:get_text(def_range)

  -- Compute scope string to strip it
  local scope_string = csymbol:scope_string(doc, class_location.range.start, false)

  -- Format definition without scope (for inline)
  local text_without_scope = csymbol:format_declaration(doc, class_location.range.start, '', false)

  -- Remove the original definition
  doc:replace_text(def_range, '')

  -- Find position in class for this function
  local access = utils.AccessLevel.public
  local proposed_pos = nil
  if class_csymbol.find_position_for_new_member_function then
    proposed_pos = class_csymbol:find_position_for_new_member_function(access, csymbol.name)
  end

  local insert_position
  if proposed_pos and proposed_pos.position then
    insert_position = proposed_pos.position
  else
    -- Fallback: position before class closing brace
    local class_end = class_csymbol.range['end']
    insert_position = { line = class_end.line, character = 0 }
  end

  -- Insert the definition
  doc:insert_text(insert_position, '\n' .. text_without_scope)

  utils.notify('Moved definition into class: ' .. csymbol.name, 'info')

  -- Reveal new position
  reveal_definition(doc.bufnr, insert_position.line + 1)
end

--- Execute command (default: execute_to_source)
--- @param opts table|nil Optional params with mode = 'to_source' | 'in_out_class'
function M.execute(opts)
  opts = opts or {}
  local mode = opts.mode or 'to_source'

  if mode == 'to_source' then
    M.execute_to_source()
  elseif mode == 'in_out_class' then
    M.execute_into_or_out_of_class()
  else
    utils.notify('Unknown mode: ' .. mode, 'error')
  end
end

return M
