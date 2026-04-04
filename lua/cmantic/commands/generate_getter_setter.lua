--- Generate getter/setter command for cmantic.nvim
--- Ported from vscode-cmantic src/commands/generateGetterSetter.ts

local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')
local accessor = require('cmantic.accessor')
local config = require('cmantic.config')
local utils = require('cmantic.utils')

local M = {}

local DefinitionLocation = {
  inline = 'inline',
  below_class = 'below_class',
  source_file = 'source_file',
}

--- Execute the generate getter/setter command
--- @param opts table|nil { mode = 'getter' | 'setter' | 'both' }
function M.execute(opts)
  opts = opts or {}
  local mode = opts.mode or 'both'

  local bufnr = vim.api.nvim_get_current_buf()
  local doc = SourceDocument.new(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local position = { line = cursor[1] - 1, character = cursor[2] }

  local symbol = doc:get_symbol_at_position(position)
  if not symbol then
    utils.notify('No symbol found at cursor', vim.log.levels.WARN)
    return
  end

  local csymbol = CSymbol.new(symbol, doc)
  if not csymbol:is_member_variable() then
    utils.notify('Cursor is not on a member variable', vim.log.levels.WARN)
    return
  end

  local parent = csymbol.parent
  if not parent or not parent:is_class_type() then
    utils.notify('Member variable must be inside a class/struct', vim.log.levels.WARN)
    return
  end

  local access = utils.AccessLevel.public
  local pos_info = parent.find_position_for_new_member_function
    and parent:find_position_for_new_member_function(access, csymbol.name)

  if not pos_info or not pos_info.position then
    utils.notify('Could not find position for accessor', vim.log.levels.WARN)
    return
  end

  local insert_pos = pos_info.position
  local scope = M._build_scope_string(csymbol)
  local indent = M._get_indent(bufnr)

  local lines = {}

  if mode == 'getter' or mode == 'both' then
    local g = accessor.create_getter(csymbol)
    local loc = config.values.getter_definition_location

    if loc == DefinitionLocation.inline then
      table.insert(lines, accessor.format_getter_declaration(g))
    else
      table.insert(lines, accessor.format_getter_definition(g, scope, indent))
    end
  end

  if mode == 'setter' or mode == 'both' then
    local s = accessor.create_setter(csymbol)
    local loc = config.values.setter_definition_location

    if loc == DefinitionLocation.inline then
      table.insert(lines, accessor.format_setter_declaration(s))
    else
      table.insert(lines, accessor.format_setter_definition(s, scope, indent))
    end
  end

  if #lines == 0 then
    return
  end

  local text = '\n' .. table.concat(lines, '\n') .. '\n'
  doc:insert_text(insert_pos, text)

  if config.values.reveal_new_definition then
    local new_line = insert_pos.line + 1
    vim.api.nvim_win_set_cursor(0, { new_line + 1, 0 })
  end
end

--- Build scope string for definition (e.g., "Namespace::Class::")
--- @param csymbol table CSymbol
--- @return string Scope string
function M._build_scope_string(csymbol)
  local scopes = csymbol:scopes()
  local parts = {}

  for _, scope in ipairs(scopes) do
    if scope:is_class_type() or scope:is_namespace() then
      table.insert(parts, scope.name .. '::')
    end
  end

  return table.concat(parts)
end

--- Get indentation string for the buffer
--- @param bufnr number Buffer number
--- @return string Indentation string
function M._get_indent(bufnr)
  return utils.indentation(bufnr)
end

return M
