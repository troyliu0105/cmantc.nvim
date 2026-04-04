--- Generate operators command for cmantic.nvim
--- Ported from vscode-cmantic src/commands/generateOperators.ts

local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')
local operator = require('cmantic.operator')
local utils = require('cmantic.utils')
local config = require('cmantic.config')

local M = {}

local AccessLevel = utils.AccessLevel

--- Get member variables from a class that can be used as operands
--- @param class_csymbol table CSymbol for the class
--- @return table[] Array of CSymbol member variables
local function get_operands(class_csymbol)
  local operands = {}
  if not class_csymbol.children then
    return operands
  end

  for _, child in ipairs(class_csymbol.children) do
    if child:is_member_variable() then
      -- Skip static members
      if not child:is_static() then
        table.insert(operands, child)
      end
    end
  end

  return operands
end

--- Find the insertion position for operator declarations in a class
--- @param class_csymbol table CSymbol for the class
--- @return table Position { line, character }
local function find_insertion_position(class_csymbol)
  local pos = class_csymbol:find_position_for_new_member_function(AccessLevel.public)
  if pos and pos.position then
    return pos.position
  end

  return class_csymbol.range['end']
end

--- Generate equality operators (==, !=)
--- @param bufnr number Buffer number
--- @param doc table SourceDocument
--- @param class_csymbol table CSymbol for the class
--- @param operands table[] Array of member variables
local function generate_equality(bufnr, doc, class_csymbol, operands)
  local result = operator.create_equal(class_csymbol, operands)

  local pos = find_insertion_position(class_csymbol)
  local lines = {}

  table.insert(lines, '')
  table.insert(lines, '  // Equality operators')
  table.insert(lines, '  ' .. result.equal.declaration)
  table.insert(lines, '  ' .. result.not_equal.declaration)

  local text = table.concat(lines, '\n')
  doc:insert_text(pos, text)

  utils.notify('Generated == and != operators', 'info')
end

--- Generate relational operators (<, >, <=, >=)
--- @param bufnr number Buffer number
--- @param doc table SourceDocument
--- @param class_csymbol table CSymbol for the class
--- @param operands table[] Array of member variables
local function generate_relational(bufnr, doc, class_csymbol, operands)
  local result = operator.create_relational(class_csymbol, operands)

  local pos = find_insertion_position(class_csymbol)
  local lines = {}

  table.insert(lines, '')
  table.insert(lines, '  // Relational operators')
  table.insert(lines, '  ' .. result.less.declaration)
  table.insert(lines, '  ' .. result.greater.declaration)
  table.insert(lines, '  ' .. result.less_equal.declaration)
  table.insert(lines, '  ' .. result.greater_equal.declaration)

  local text = table.concat(lines, '\n')
  doc:insert_text(pos, text)

  utils.notify('Generated <, >, <=, >= operators', 'info')
end

--- Generate stream output operator (<<)
--- @param bufnr number Buffer number
--- @param doc table SourceDocument
--- @param class_csymbol table CSymbol for the class
--- @param operands table[] Array of member variables
local function generate_stream(bufnr, doc, class_csymbol, operands)
  local result = operator.create_stream_output(class_csymbol, operands)

  local pos = find_insertion_position(class_csymbol)
  local lines = {}

  table.insert(lines, '')
  table.insert(lines, '  // Stream output operator')
  table.insert(lines, '  ' .. result.declaration)

  local text = table.concat(lines, '\n')
  doc:insert_text(pos, text)

  utils.notify('Generated << operator', 'info')
end

--- Main execute function
--- @param opts table|nil { mode = 'equality' | 'relational' | 'stream' }
function M.execute(opts)
  opts = opts or {}
  local mode = opts.mode or 'equality'

  local bufnr = vim.api.nvim_get_current_buf()
  local doc = SourceDocument.new(bufnr)

  local cursor = vim.api.nvim_win_get_cursor(0)
  local position = { line = cursor[1] - 1, character = cursor[2] }

  local symbol = doc:get_symbol_at_position(position)
  if not symbol then
    utils.notify('No symbol at cursor position', vim.log.levels.WARN)
    return
  end

  local csymbol = CSymbol.new(symbol, doc)

  local parent_class

  if csymbol:is_class_type() then
    parent_class = csymbol
  elseif csymbol:is_member_variable() then
    if csymbol.parent then
      parent_class = CSymbol.new(csymbol.parent, doc)
    end
  else
    utils.notify('Cursor must be on a class, struct, or member variable', vim.log.levels.WARN)
    return
  end

  if not parent_class then
    utils.notify('Could not determine parent class', vim.log.levels.WARN)
    return
  end

  local operands = get_operands(parent_class)

  if #operands == 0 then
    utils.notify('No non-static member variables found for comparison', vim.log.levels.WARN)
    return
  end

  if mode == 'equality' then
    generate_equality(bufnr, doc, parent_class, operands)
  elseif mode == 'relational' then
    generate_relational(bufnr, doc, parent_class, operands)
  elseif mode == 'stream' then
    generate_stream(bufnr, doc, parent_class, operands)
  else
    utils.notify('Unknown mode: ' .. mode .. '. Use: equality, relational, or stream', vim.log.levels.WARN)
  end
end

return M
