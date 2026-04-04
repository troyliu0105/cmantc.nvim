--- Document with smart positioning for cmantic.nvim
--- Ported from vscode-cmantic src/SourceDocument.ts
---
--- Provides buffer access, text manipulation, and intelligent positioning
--- for inserting function definitions, declarations, and includes.

local M = {}
M.__index = M

local config = require('cmantic.config')
local utils = require('cmantic.utils')
local parse = require('cmantic.parsing')
local SourceFile = require('cmantic.source_file')
local SourceSymbol = require('cmantic.source_symbol')
local SubSymbol = require('cmantic.sub_symbol')
local ProposedPosition = require('cmantic.proposed_position')

-- Preprocessor directive pattern
local re_preprocessor_directive = '^%s*#.*%S%s*$'

--------------------------------------------------------------------------------
-- Constructor
--------------------------------------------------------------------------------

--- Create a new SourceDocument instance
--- @param bufnr number Buffer number
--- @return table SourceDocument instance
function M.new(bufnr)
  local self = setmetatable({}, M)
  self.bufnr = bufnr
  self.uri = vim.uri_from_bufnr(bufnr)
  self.symbols = nil -- Lazy-loaded CSymbols
  self._lines = nil -- Lazy-loaded line cache
  self._preprocessor_directives = nil
  self._conditionals = nil
  self._included_files = nil
  self._header_guard_directives = nil
  self._proposed_definitions = {} -- Maps position key to location
  return self
end

--- Open a SourceDocument from a URI
--- @param uri string File URI
--- @return table SourceDocument instance
function M.open(uri)
  local bufnr = vim.uri_to_bufnr(uri)
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end
  return M.new(bufnr)
end

--------------------------------------------------------------------------------
-- Text Access
--------------------------------------------------------------------------------

--- Get text from buffer, optionally within a range
--- @param range table|nil Optional range { start = { line, character }, ['end'] = { line, character } }
--- @return string Text content
function M:get_text(range)
  if range then
    local start_line = range.start.line
    local start_char = range.start.character
    local end_line = range['end'].line
    local end_char = range['end'].character
    local lines = vim.api.nvim_buf_get_text(self.bufnr, start_line, start_char, end_line, end_char, {})
    return table.concat(lines, '\n')
  else
    -- Return entire buffer text
    local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
    return table.concat(lines, '\n')
  end
end

--- Get a single line from the buffer
--- @param line_nr number Line number (0-indexed)
--- @return string Line text
function M:get_line(line_nr)
  local lines = vim.api.nvim_buf_get_lines(self.bufnr, line_nr, line_nr + 1, false)
  return lines[1] or ''
end

--- Get all lines from the buffer
--- @return string[] Array of lines (1-indexed)
function M:get_lines()
  return vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
end

--- Get line count
--- @return number Number of lines
function M:line_count()
  return vim.api.nvim_buf_line_count(self.bufnr)
end

--- Convert LSP position to byte offset
--- @param position table { line = number, character = number }
--- @return number Byte offset
function M:offset_at(position)
  local line_offset = vim.api.nvim_buf_get_offset(self.bufnr, position.line)
  if line_offset < 0 then
    return 0
  end
  return line_offset + position.character
end

--- Convert byte offset to LSP position
--- @param offset number Byte offset
--- @return table { line = number, character = number }
function M:position_at_offset(offset)
  if offset < 0 then
    return { line = 0, character = 0 }
  end

  local line_count = self:line_count()
  local current_offset = 0

  for line = 0, line_count - 1 do
    local line_start = vim.api.nvim_buf_get_offset(self.bufnr, line)
    if line_start < 0 then
      line_start = current_offset
    end
    local line_text = self:get_line(line)
    local line_length = #line_text + 1 -- +1 for newline

    if line_start + line_length > offset then
      return { line = line, character = offset - line_start }
    end

    current_offset = line_start + line_length
  end

  -- Return last position if offset is beyond content
  local last_line = line_count - 1
  if last_line < 0 then
    last_line = 0
  end
  local last_text = self:get_line(last_line)
  return { line = last_line, character = #last_text }
end

--- Get end of line string for this buffer
--- @return string '\r\n' for dos, '\r' for mac, '\n' for unix
function M:end_of_line()
  return utils.end_of_line(self.bufnr)
end

--- Get indentation string for this buffer
--- @return string Spaces or tab character
function M:indentation()
  return utils.indentation(self.bufnr)
end

--------------------------------------------------------------------------------
-- File Type Detection
--------------------------------------------------------------------------------

--- Get file extension without the dot
--- @return string Extension (e.g., 'cpp', 'h')
function M:file_extension()
  local fname = vim.uri_to_fname(self.uri)
  return vim.fn.fnamemodify(fname, ':e')
end

--- Check if this is a header file
--- @return boolean
function M:is_header()
  local ext = self:file_extension()
  local header_exts = config.header_extensions()
  for _, header_ext in ipairs(header_exts) do
    if ext == header_ext then
      return true
    end
  end
  return false
end

--- Check if this is a source file
--- @return boolean
function M:is_source()
  local ext = self:file_extension()
  local source_exts = config.source_extensions()
  for _, source_ext in ipairs(source_exts) do
    if ext == source_ext then
      return true
    end
  end
  return false
end

--------------------------------------------------------------------------------
-- Symbol Access
--------------------------------------------------------------------------------

--- Lazy-load CSymbols from LSP
--- @return table[] Array of CSymbol instances
function M:get_c_symbols()
  if self.symbols == nil then
    local sf = SourceFile.new(self.uri)
    local raw_symbols = sf:get_symbols()
    self.symbols = {}

    for _, symbol in ipairs(raw_symbols) do
      -- Create SourceSymbol first, then CSymbol will wrap it
      local source_sym = SourceSymbol.new(symbol, self.uri, nil)
      -- We'll store SourceSymbols here; CSymbol wrapping happens when needed
      table.insert(self.symbols, source_sym)
    end
  end
  return self.symbols
end

--- Get a symbol at a specific position
--- @param position table { line = number, character = number }
--- @return table|nil SourceSymbol or nil
function M:get_symbol_at_position(position)
  local symbols = self:get_c_symbols()
  if not symbols or #symbols == 0 then
    return nil
  end

  local function search_deepest(sym_list)
    for _, symbol in ipairs(sym_list) do
      if self:symbol_contains_position(symbol, position) then
        if symbol.children and #symbol.children > 0 then
          local child_match = search_deepest(symbol.children)
          if child_match then
            return child_match
          end
        end
        return symbol
      end
    end
    return nil
  end

  return search_deepest(symbols)
end

--- Check if a symbol contains a position
--- @param symbol table SourceSymbol
--- @param position table { line = number, character = number }
--- @return boolean
function M:symbol_contains_position(symbol, position)
  if not symbol or not symbol.range or not position then
    return false
  end

  local start_pos = symbol.range.start
  local end_pos = symbol.range['end']

  -- Position must satisfy: start <= pos < end (inclusive start, exclusive end)
  local after_start = start_pos.line < position.line
    or (start_pos.line == position.line and start_pos.character <= position.character)

  local before_end = end_pos.line > position.line
    or (end_pos.line == position.line and end_pos.character > position.character)

  return after_start and before_end
end

--- Find a matching symbol in this document
--- @param target table SourceSymbol to match
--- @return table|nil Matching symbol or nil
function M:find_matching_symbol(target)
  local symbols = self:get_c_symbols()
  if not symbols or #symbols == 0 then
    return nil
  end

  local function search_recursive(sym_list)
    for _, symbol in ipairs(sym_list) do
      if symbol.name == target.name and symbol.kind == target.kind then
        return symbol
      end

      if symbol.children and #symbol.children > 0 then
        local found = search_recursive(symbol.children)
        if found then
          return found
        end
      end
    end
    return nil
  end

  return search_recursive(symbols)
end

--------------------------------------------------------------------------------
-- Preprocessor Analysis
--------------------------------------------------------------------------------

--- Get all preprocessor directives as SubSymbols
--- @return table[] Array of SubSymbol instances
function M:get_preprocessor_directives()
  if self._preprocessor_directives then
    return self._preprocessor_directives
  end

  self._preprocessor_directives = {}
  local text = self:get_text()
  local masked_text = parse.mask_non_source_text(text)

  -- Find all preprocessor directives
  local i = 1
  while i <= #masked_text do
    -- Check for # at start of line (after whitespace)
    local line_start = i
    while i <= #masked_text and masked_text:sub(i, i):match('%s') and masked_text:sub(i, i) ~= '\n' do
      i = i + 1
    end

    if i <= #masked_text and masked_text:sub(i, i) == '#' then
      -- Found potential preprocessor directive
      local directive_start = i
      -- Find end of line
      while i <= #masked_text and masked_text:sub(i, i) ~= '\n' do
        i = i + 1
      end
      local directive_end = i

      local range = {
        start = self:position_at_offset(directive_start - 1), -- Lua is 1-indexed
        ['end'] = self:position_at_offset(directive_end - 1),
      }

      table.insert(self._preprocessor_directives, SubSymbol.new(self, range))
    end

    -- Move to next line
    while i <= #masked_text and masked_text:sub(i, i) ~= '\n' do
      i = i + 1
    end
    if i <= #masked_text then
      i = i + 1 -- skip newline
    end
  end

  return self._preprocessor_directives
end

--- Get list of included files
--- @return string[] Array of included filenames
function M:get_included_files()
  if self._included_files then
    return self._included_files
  end

  self._included_files = {}
  local directives = self:get_preprocessor_directives()

  for _, directive in ipairs(directives) do
    local text = directive:text()
    -- Match #include <file> or #include "file"
    local file = text:match('^%s*#%s*include%s*[<"]([^>"]+)[>"]')
    if file then
      table.insert(self._included_files, file)
    end
  end

  return self._included_files
end

--------------------------------------------------------------------------------
-- Header Guard Analysis
--------------------------------------------------------------------------------

--- Get header guard directives
--- @return table[] Array of SubSymbol instances
function M:get_header_guard_directives()
  if self._header_guard_directives then
    return self._header_guard_directives
  end

  self._header_guard_directives = {}
  if not self:is_header() then
    return self._header_guard_directives
  end

  local directives = self:get_preprocessor_directives()

  for i = 1, #directives do
    local text = directives[i]:text()

    -- Check for #pragma once
    if text:match('^%s*#%s*pragma%s+once') then
      table.insert(self._header_guard_directives, directives[i])
    end

    -- Check for #ifndef / #define pair
    local guard_name = text:match('^%s*#%s*ifndef%s+([%w_]+)')
    if guard_name and i < #directives then
      local next_text = directives[i + 1]:text()
      local define_pattern = '^%s*#%s*define%s+' .. guard_name .. '%s*$'
      if next_text:match(define_pattern) then
        table.insert(self._header_guard_directives, directives[i])
        table.insert(self._header_guard_directives, directives[i + 1])
        -- Find matching #endif (simplified: look for last #endif)
        for j = #directives, i + 2, -1 do
          if directives[j]:text():match('^%s*#%s*endif') then
            table.insert(self._header_guard_directives, directives[j])
            break
          end
        end
        break
      end
    end
  end

  return self._header_guard_directives
end

--- Check if file has header guard
--- @return boolean
function M:has_header_guard()
  return #self:get_header_guard_directives() > 0
end

--- Check if file has pragma once
--- @return boolean
function M:has_pragma_once()
  local directives = self:get_header_guard_directives()
  for _, directive in ipairs(directives) do
    if directive:text():match('^%s*#%s*pragma%s+once') then
      return true
    end
  end
  return false
end

--- Get position after header guard
--- @return table|nil Position or nil
function M:position_after_header_guard()
  local directives = self:get_header_guard_directives()
  for i = #directives, 1, -1 do
    if not directives[i]:text():match('^%s*#%s*endif') then
      return { line = directives[i].range.start.line + 1, character = 0 }
    end
  end
  return nil
end

--- Get position after header comment
--- @return table ProposedPosition
function M:position_after_header_comment()
  local text = self:get_text()
  local masked_text = parse.mask_comments(text)
  local offset = masked_text:find('%S')

  if offset then
    -- Return position before first non-comment text
    local pos = self:position_at_offset(offset - 1)
    return ProposedPosition.new(pos, { before = true })
  end

  -- Return position after header comment when there is no non-comment text
  local trimmed = text:gsub('%s*$', '')
  local end_offset = #trimmed
  return ProposedPosition.new(self:position_at_offset(end_offset), {
    after = end_offset ~= 0,
  })
end

--------------------------------------------------------------------------------
-- Smart Positioning for Includes
--------------------------------------------------------------------------------

--- Find positions for new includes
--- @param before_pos table|nil Optional position to search before
--- @return table { system = position, project = position }
function M:find_position_for_new_include(before_pos)
  local system_include_line = nil
  local project_include_line = nil
  local directives = self:get_preprocessor_directives()

  for _, directive in ipairs(directives) do
    -- Check if we should stop at before_pos
    if before_pos then
      local dir_end = directive.range['end']
      if utils.position_before(before_pos, dir_end) then
        break
      end
    end

    local text = directive:text()
    if text:match('^%s*#%s*include%s*<.+>') then
      system_include_line = directive.range.start.line
    elseif text:match('^%s*#%s*include%s*".+"') then
      project_include_line = directive.range.start.line
    end
  end

  -- If no system include found, use project include position
  if system_include_line == nil then
    system_include_line = project_include_line
  end

  -- If no project include found, use system include position
  if project_include_line == nil then
    project_include_line = system_include_line
  end

  -- If neither found, position after header guard or header comment
  if system_include_line == nil or project_include_line == nil then
    local position = self:position_after_header_guard()
    if not position then
      position = self:position_after_header_comment()
    end
    return { system = position, project = position }
  end

  return {
    system = { line = system_include_line + 1, character = 0 },
    project = { line = project_include_line + 1, character = 0 },
  }
end

--------------------------------------------------------------------------------
-- Smart Positioning for Functions
--------------------------------------------------------------------------------

--- Find smart position for function definition
--- Algorithm:
--- 1. Get declaration's parent class/namespace scopes
--- 2. Find sibling functions (other functions with same parent)
--- 3. For each sibling, check if it has a definition in target_doc
--- 4. If found: position after that sibling's definition
--- 5. If no sibling match: find matching namespace block in target_doc
--- 6. Fallback: after last symbol in target_doc
---
--- @param declaration table CSymbol (declaration)
--- @param target_doc table|nil Target SourceDocument (defaults to self)
--- @return table ProposedPosition
function M:find_smart_position_for_function_definition(declaration, target_doc)
  -- Ensure symbols are loaded
  self:get_c_symbols()

  if not target_doc then
    target_doc = self
  end

  target_doc:get_c_symbols()

  if not target_doc.symbols or #target_doc.symbols == 0 then
    return self:position_after_last_non_empty_line(target_doc)
  end

  -- Find sibling functions
  local sibling_functions = self:get_sibling_functions(declaration)
  local declaration_index = self:index_of_symbol(declaration, sibling_functions)

  if declaration_index < 1 then
    -- Declaration not found in siblings, fall back
    return self:position_after_last_symbol(target_doc, target_doc.symbols)
  end

  local before = {}
  local after = {}

  -- Get functions before declaration (in reverse order for searching)
  for i = declaration_index - 1, 1, -1 do
    table.insert(before, sibling_functions[i])
  end

  -- Get functions after declaration
  for i = declaration_index + 1, #sibling_functions do
    table.insert(after, sibling_functions[i])
  end

  -- Try to find position relative to siblings
  local position = self:find_position_relative_to_siblings(
    declaration, before, after, target_doc, true, nil
  )

  if position then
    return position
  end

  -- If a sibling definition couldn't be found, look for a position in a parent namespace
  local namespace_pos = self:find_position_in_parent_namespace(declaration, target_doc)
  if namespace_pos then
    return namespace_pos
  end

  -- If all else fails then return a position after the last symbol
  return self:position_after_last_symbol(target_doc, target_doc.symbols)
end

--- Find smart position for function declaration
--- @param definition table CSymbol (definition)
--- @param target_doc table|nil Target SourceDocument (defaults to self)
--- @param parent_class table|nil Parent class CSymbol
--- @param access string|nil Access level (public, protected, private)
--- @return table ProposedPosition
function M:find_smart_position_for_function_declaration(definition, target_doc, parent_class, access)
  -- Ensure symbols are loaded
  self:get_c_symbols()

  if not target_doc then
    target_doc = self
  end

  target_doc:get_c_symbols()

  if not target_doc.symbols or #target_doc.symbols == 0 then
    return self:position_after_last_non_empty_line(target_doc)
  end

  -- If access specified, try to find position in member function section
  if access then
    local member_pos = self:find_position_for_member_function(definition, target_doc, parent_class, access)
    if member_pos then
      return member_pos
    end
  end

  -- Find sibling functions
  local sibling_functions = self:get_sibling_functions(definition)
  local definition_index = self:index_of_symbol(definition, sibling_functions)

  if definition_index >= 1 then
    local before = {}
    local after = {}

    -- Get functions before definition (in reverse order)
    for i = definition_index - 1, 1, -1 do
      table.insert(before, sibling_functions[i])
    end

    -- Get functions after definition
    for i = definition_index + 1, #sibling_functions do
      table.insert(after, sibling_functions[i])
    end

    -- Try to find position relative to siblings
    local position = self:find_position_relative_to_siblings(
      definition, before, after, target_doc, false, parent_class
    )

    if position then
      return position
    end
  end

  -- If access not specified yet, try to find position in member function section
  if not access then
    local member_pos = self:find_position_for_member_function(definition, target_doc, parent_class, nil)
    if member_pos then
      return member_pos
    end
  end

  -- If a sibling declaration couldn't be found, look for a position in a parent namespace
  local namespace_pos = self:find_position_in_parent_namespace(definition, target_doc)
  if namespace_pos then
    return namespace_pos
  end

  -- If all else fails then return a position after the last symbol
  return self:position_after_last_symbol(target_doc, target_doc.symbols)
end

--------------------------------------------------------------------------------
-- Helper Methods for Smart Positioning
--------------------------------------------------------------------------------

--- Get sibling functions (functions with same parent)
--- @param symbol table CSymbol
--- @return table[] Array of sibling SourceSymbols
function M:get_sibling_functions(symbol)
  local parent_children = symbol.parent and symbol.parent.children or self.symbols
  local siblings = {}

  for _, sibling in ipairs(parent_children) do
    if sibling:is_function() then
      table.insert(siblings, sibling)
    end
  end

  return siblings
end

--- Find index of symbol in siblings array
--- @param symbol table SourceSymbol
--- @param siblings table[] Array of SourceSymbols
--- @return number Index (1-based) or 0 if not found
function M:index_of_symbol(symbol, siblings)
  local target_start = symbol.selection_range and symbol.selection_range.start
  if not target_start then
    return 0
  end

  for i, sibling in ipairs(siblings) do
    if sibling.selection_range and sibling.selection_range.start then
      local sibling_start = sibling.selection_range.start
      if sibling_start.line == target_start.line
        and sibling_start.character == target_start.character then
        return i
      end
    end
  end

  return 0
end

--- Find position relative to sibling functions
--- @param anchor_symbol table CSymbol
--- @param before table[] Sibling functions before (in reverse order)
--- @param after table[] Sibling functions after
--- @param target_doc table Target SourceDocument
--- @param find_definition boolean If true, find definition; else find declaration
--- @param parent_class table|nil Parent class CSymbol
--- @return table|nil ProposedPosition or nil
function M:find_position_relative_to_siblings(anchor_symbol, before, after, target_doc, find_definition, parent_class)
  local anchor_scopes = anchor_symbol.scopes and anchor_symbol:scopes() or {}

  -- Check siblings before (up to 5)
  local checked_count = 0
  for _, sibling in ipairs(before) do
    if checked_count >= 5 then
      break
    end

    local is_decl_or_def = false
    if find_definition then
      is_decl_or_def = sibling.is_function_declaration and sibling:is_function_declaration()
    else
      is_decl_or_def = sibling.is_function_definition and sibling:is_function_definition()
    end

    if is_decl_or_def then
      checked_count = checked_count + 1

      local location = nil
      if find_definition then
        location = sibling.find_definition and sibling:find_definition()
      else
        location = sibling.find_declaration and sibling:find_declaration()
      end

      if location and location.uri == target_doc.uri then
        local linked_symbol = target_doc:get_symbol_at_position(location.range.start)

        if linked_symbol and not linked_symbol:is_class_type() then
          -- Check if scopes intersect
          local linked_scopes = linked_symbol.scopes and linked_symbol:scopes() or {}
          if not self:scopes_intersect(linked_scopes, anchor_scopes) then
            -- Continue to next sibling
          else
            -- Found a match, position after this symbol
            local end_pos = linked_symbol.range and linked_symbol.range['end']
            if end_pos then
              return ProposedPosition.new(
                { line = end_pos.line, character = 0 },
                { relative_to = linked_symbol.range, after = true }
              )
            end
          end
        end
      end
    end
  end

  -- Check siblings after (up to 5)
  checked_count = 0
  for _, sibling in ipairs(after) do
    if checked_count >= 5 then
      break
    end

    local is_decl_or_def = false
    if find_definition then
      is_decl_or_def = sibling.is_function_declaration and sibling:is_function_declaration()
    else
      is_decl_or_def = sibling.is_function_definition and sibling:is_function_definition()
    end

    if is_decl_or_def then
      checked_count = checked_count + 1

      local location = nil
      if find_definition then
        location = sibling.find_definition and sibling:find_definition()
      else
        location = sibling.find_declaration and sibling:find_declaration()
      end

      if location and location.uri == target_doc.uri then
        local linked_symbol = target_doc:get_symbol_at_position(location.range.start)

        if linked_symbol and not linked_symbol:is_class_type() then
          local linked_scopes = linked_symbol.scopes and linked_symbol:scopes() or {}
          if not self:scopes_intersect(linked_scopes, anchor_scopes) then
            -- Continue to next sibling
          else
            -- Found a match, position before this symbol
            local start_pos = linked_symbol.range and linked_symbol.range.start
            if start_pos then
              return ProposedPosition.new(
                { line = start_pos.line, character = 0 },
                { relative_to = linked_symbol.range, before = true }
              )
            end
          end
        end
      end
    end
  end

  return nil
end

--- Check if two scope arrays share any common scope
--- @param scopes_a table[] First scope array
--- @param scopes_b table[] Second scope array
--- @return boolean true if they intersect
function M:scopes_intersect(scopes_a, scopes_b)
  if not scopes_a or not scopes_b or #scopes_a == 0 or #scopes_b == 0 then
    return true -- Empty scopes are compatible
  end

  for _, scope_a in ipairs(scopes_a) do
    for _, scope_b in ipairs(scopes_b) do
      if scope_a.name == scope_b.name and scope_a.kind == scope_b.kind then
        return true
      end
    end
  end

  return false
end

--- Find position for member function in class
--- @param symbol table CSymbol
--- @param target_doc table Target SourceDocument
--- @param parent_class table|nil Parent class CSymbol
--- @param access string|nil Access level
--- @return table|nil ProposedPosition or nil
function M:find_position_for_member_function(symbol, target_doc, parent_class, access)
  if not access then
    access = utils.AccessLevel.public
  end

  if parent_class and parent_class.find_position_for_new_member_function then
    return parent_class:find_position_for_new_member_function(access)
  end

  -- Try to find parent class via immediate scope
  local immediate_scope = symbol.immediate_scope and symbol:immediate_scope()
  if immediate_scope then
    local parent_class_location = immediate_scope.find_definition and immediate_scope:find_definition()
    if parent_class_location and parent_class_location.uri == self.uri then
      local found_class = self:get_symbol_at_position(parent_class_location.range.start)
      if found_class and found_class:is_class_type() and found_class.find_position_for_new_member_function then
        return found_class:find_position_for_new_member_function(access)
      end
    end
  end

  return nil
end

--- Find position in parent namespace
--- @param symbol table CSymbol
--- @param target_doc table Target SourceDocument
--- @return table|nil ProposedPosition or nil
function M:find_position_in_parent_namespace(symbol, target_doc)
  local scopes = symbol.scopes and symbol:scopes() or {}

  -- Walk scopes in reverse (from innermost to outermost)
  for i = #scopes, 1, -1 do
    local scope = scopes[i]

    if scope:is_namespace() then
      local target_namespace = target_doc:find_matching_symbol(scope)

      if target_namespace then
        if not target_namespace.children or #target_namespace.children == 0 then
          -- Empty namespace, position at body start
          local body_start = target_namespace.body_start and target_namespace:body_start()
          if body_start then
            return ProposedPosition.new(body_start, { after = true, indent = true })
          end
        else
          -- Position after last child
          local last_child = target_namespace.children[#target_namespace.children]
          local end_pos = last_child.range and last_child.range['end']
          if end_pos then
            return ProposedPosition.new(
              { line = end_pos.line, character = 0 },
              { relative_to = last_child.range, after = true }
            )
          end
        end
      end
    end
  end

  return nil
end

--------------------------------------------------------------------------------
-- Position Helpers
--------------------------------------------------------------------------------

--- Get position after last symbol
--- @param doc table SourceDocument
--- @param symbols table[] Array of symbols
--- @return table ProposedPosition
function M:position_after_last_symbol(doc, symbols)
  if symbols and #symbols > 0 then
    local last_symbol = symbols[#symbols]
    local end_pos = last_symbol.range and last_symbol.range['end']
    if end_pos then
      return ProposedPosition.new(
        { line = end_pos.line, character = 0 },
        { relative_to = last_symbol.range, after = true }
      )
    end
  end
  return self:position_after_last_non_empty_line(doc)
end

--- Get position after last non-empty line
--- @param doc table SourceDocument
--- @return table ProposedPosition
function M:position_after_last_non_empty_line(doc)
  local line_count = doc:line_count()
  local last_non_empty = line_count - 1

  -- Find last non-empty line
  for line = line_count - 1, 0, -1 do
    local text = doc:get_line(line)
    if text:match('%S') then
      last_non_empty = line
      break
    end
  end

  -- Position after last non-empty line
  return ProposedPosition.new(
    { line = last_non_empty + 1, character = 0 },
    { after = last_non_empty < line_count - 1 }
  )
end

--------------------------------------------------------------------------------
-- Text Manipulation
--------------------------------------------------------------------------------

--- Insert text at position
--- @param position table { line = number, character = number }
--- @param text string Text to insert
function M:insert_text(position, text)
  local lines = vim.split(text, '\n')
  vim.api.nvim_buf_set_text(
    self.bufnr,
    position.line,
    position.character,
    position.line,
    position.character,
    lines
  )
end

--- Replace text in range
--- @param range table { start = { line, character }, ['end'] = { line, character } }
--- @param text string New text
function M:replace_text(range, text)
  local lines = vim.split(text, '\n')
  vim.api.nvim_buf_set_text(
    self.bufnr,
    range.start.line,
    range.start.character,
    range['end'].line,
    range['end'].character,
    lines
  )
end

--- Insert lines at a given line number
--- @param line_nr number Line number (0-indexed)
--- @param lines string[] Array of lines to insert
function M:insert_lines(line_nr, lines)
  vim.api.nvim_buf_set_lines(self.bufnr, line_nr, line_nr, false, lines)
end

return M
