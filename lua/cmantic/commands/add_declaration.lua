--- Add Declaration command for cmantic.nvim
--- Ported from vscode-cmantic src/commands/addDeclaration.ts
--- Generates function declarations from function definitions.

local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')
local header_source = require('cmantic.header_source')
local config = require('cmantic.config')
local utils = require('cmantic.utils')

local M = {}

--- Add declaration from a function definition
--- Algorithm:
--- 1. Get current buffer, create SourceDocument
--- 2. Get cursor position, find CSymbol at cursor
--- 3. Verify it's a function definition
--- 4. If the function is inside a class (parent is class type):
---    - The declaration is already inline — notify user and return
--- 5. Find matching header file via header_source.get_matching(uri)
--- 6. If no match, notify and return
--- 7. Open header file, create SourceDocument for it
--- 8. Find the parent class in the header file
--- 9. Determine access specifier (prompt user if needed: public/protected/private)
--- 10. Find smart position in header
--- 11. Generate declaration text via csymbol:new_function_declaration()
--- 12. Insert declaration at found position
--- 13. If config.values.reveal_new_definition, jump to new declaration
function M.execute()
  local bufnr = vim.api.nvim_get_current_buf()
  local source_doc = SourceDocument.new(bufnr)

  local cursor = vim.api.nvim_win_get_cursor(0)
  local position = { line = cursor[1] - 1, character = cursor[2] }

  local raw_symbol = source_doc:get_symbol_at_position(position)
  if not raw_symbol then
    utils.notify('No symbol found at cursor position', 'warn')
    return
  end

  local csymbol = CSymbol.new(raw_symbol, source_doc)

  if not csymbol:is_function_definition() then
    utils.notify('Cursor is not on a function definition', 'warn')
    return
  end

  local parent = csymbol.parent
  if parent and parent:is_class_type() then
    utils.notify('Function is already defined inside class (inline)', 'info')
    return
  end

  local uri = vim.uri_from_bufnr(bufnr)
  local header_uri = header_source.get_matching(uri)

  if not header_uri then
    utils.notify('No matching header file found', 'warn')
    return
  end

  local target_doc = SourceDocument.open(header_uri)

  local parent_class = nil
  local scopes = csymbol:scopes()

  for _, scope in ipairs(scopes) do
    if scope:is_class_type() then
      parent_class = target_doc:find_matching_symbol(scope)
      break
    end
  end

  local is_member_function = parent_class ~= nil

  if is_member_function then
    local access_levels = { 'public', 'protected', 'private' }
    vim.ui.select(access_levels, {
      prompt = 'Select access specifier:',
    }, function(choice)
      if choice then
        M._insert_declaration(csymbol, source_doc, target_doc, parent_class, choice)
      end
    end)
  else
    M._insert_declaration(csymbol, source_doc, target_doc, nil, nil)
  end
end

--- Insert the declaration at the calculated position
--- @param csymbol table CSymbol (the function definition)
--- @param source_doc table SourceDocument (source file)
--- @param target_doc table SourceDocument (header file)
--- @param parent_class table|nil Parent class CSymbol in header
--- @param access string|nil Access level (public/protected/private)
function M._insert_declaration(csymbol, source_doc, target_doc, parent_class, access)
  local proposed_pos = source_doc:find_smart_position_for_function_declaration(
    csymbol,
    target_doc,
    parent_class,
    access
  )

  if not proposed_pos then
    utils.notify('Could not find position for declaration', 'warn')
    return
  end

  local declaration_text = csymbol:new_function_declaration()

  if not declaration_text or declaration_text == '' then
    utils.notify('Could not generate declaration text', 'warn')
    return
  end

  local insert_line = proposed_pos:line()

  local indent = ''
  if proposed_pos.options.indent then
    indent = utils.indentation(target_doc.bufnr)
    if type(proposed_pos.options.indent) == 'number' then
      indent = string.rep(indent, proposed_pos.options.indent)
    end
  end

  local blank_before = proposed_pos.options.blank_lines_before or 1
  local blank_after = proposed_pos.options.blank_lines_after or 1

  local lines_to_insert = {}

  for _ = 1, blank_before do
    table.insert(lines_to_insert, '')
  end

  local decl_lines = vim.split(declaration_text, '\n')
  for _, line in ipairs(decl_lines) do
    table.insert(lines_to_insert, indent .. line)
  end

  for _ = 1, blank_after do
    table.insert(lines_to_insert, '')
  end

  target_doc:insert_lines(insert_line, lines_to_insert)

  if config.values.reveal_new_definition then
    local fname = vim.uri_to_fname(target_doc.uri)
    vim.cmd.edit(fname)
    vim.api.nvim_win_set_cursor(0, { insert_line + blank_before + 1, #indent })
  end

  utils.notify('Declaration added', 'info')
end

return M
