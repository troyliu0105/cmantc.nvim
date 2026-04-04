local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')
local FunctionSignature = require('cmantic.function_signature')
local utils = require('cmantic.utils')

local M = {}

function M.execute()
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = SourceDocument.new(bufnr)
  local cursor = vim.api.nvim_win_get_cursor(0)
  local position = { line = cursor[1] - 1, character = cursor[2] }

  local symbol = doc:get_symbol_at_position(position)
  if not symbol then
    utils.notify('No symbol at cursor', vim.log.levels.WARN)
    return
  end

  local csymbol = symbol.document and symbol or CSymbol.new(symbol, doc)
  if not csymbol:is_function() then
    utils.notify('Cursor is not on a function', vim.log.levels.WARN)
    return
  end

  local counterpart_location
  local updating_declaration = false

  if csymbol:is_function_definition() then
    counterpart_location = csymbol:find_declaration()
    updating_declaration = true
  elseif csymbol:is_function_declaration() then
    counterpart_location = csymbol:find_definition()
  end

  if not counterpart_location or not counterpart_location.uri then
    utils.notify('Could not find matching declaration/definition', vim.log.levels.WARN)
    return
  end

  local counterpart_bufnr = vim.uri_to_bufnr(counterpart_location.uri)
  if not vim.api.nvim_buf_is_loaded(counterpart_bufnr) then
    vim.fn.bufload(counterpart_bufnr)
  end

  local counterpart_doc = SourceDocument.new(counterpart_bufnr)
  local counterpart_symbol = counterpart_doc:get_symbol_at_position(counterpart_location.range.start)
  if not counterpart_symbol then
    utils.notify('Could not locate counterpart symbol', vim.log.levels.WARN)
    return
  end

  local counterpart_csym = counterpart_symbol.document and counterpart_symbol or CSymbol.new(counterpart_symbol, counterpart_doc)

  local current_sig = FunctionSignature.new(csymbol:text())
  local counterpart_sig = FunctionSignature.new(counterpart_csym:text())
  if current_sig:equals(counterpart_sig) then
    utils.notify('Signatures are already synchronized', vim.log.levels.INFO)
    return
  end

  local new_text = ''
  if updating_declaration then
    new_text = csymbol:new_function_declaration()
  else
    new_text = csymbol:new_function_definition(counterpart_doc, counterpart_location.range.start)
  end

  if new_text == '' then
    utils.notify('Could not generate updated signature', vim.log.levels.WARN)
    return
  end

  local replace_range
  if updating_declaration then
    local end_pos = counterpart_csym.range['end']
    if counterpart_csym.declaration_end then
      end_pos = counterpart_csym:declaration_end()
    end
    replace_range = {
      start = counterpart_csym:true_start(),
      ['end'] = end_pos,
    }
  else
    replace_range = {
      start = counterpart_csym:true_start(),
      ['end'] = counterpart_csym.range['end'],
    }
  end

  counterpart_doc:replace_text(replace_range, new_text)
  utils.notify('Signature updated in matching file', vim.log.levels.INFO)
end

return M
