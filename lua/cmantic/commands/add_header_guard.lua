--- Add Header Guard command for cmantic.nvim
--- Ported from vscode-cmantic src/commands/addHeaderGuard.ts

local SourceDocument = require('cmantic.source_document')
local config = require('cmantic.config')
local utils = require('cmantic.utils')

local M = {}

function M._format_guard_name(doc)
  local path = vim.uri_to_fname(doc.uri)
  local relative_path = vim.fn.fnamemodify(path, ':.')
  local filename = utils.file_name_no_ext(path):upper()
  local ext = utils.file_extension(path):upper()
  local rel_path_token = relative_path:upper()

  local format = config.values.header_guard_format or '${FILE_NAME}_${EXT}'
  format = format:gsub('%${FILE_NAME}', filename)
  format = format:gsub('%${EXT}', ext)
  format = format:gsub('%${PATH}', rel_path_token)

  format = format:gsub('[^%w]', '_')
  format = format:gsub('_+', '_')
  format = format:gsub('^_+', ''):gsub('_+$', '')

  if format == '' then
    format = 'HEADER_GUARD'
  end

  return format
end

--- Execute Add Header Guard command
--- Algorithm:
--- 1. Ensure current buffer is a header file
--- 2. Skip if guard already exists (#ifndef/#define or #pragma once)
--- 3. Build guard content based on config.header_guard_style
--- 4. Insert at top after header comments
--- 5. For define/both styles, append matching #endif at file end
function M.execute()
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = SourceDocument.new(bufnr)

  if not doc:is_header() then
    utils.notify('Current file is not a header file', 'warn')
    return
  end

  if doc:has_header_guard() or doc:has_pragma_once() then
    utils.notify('Header guard already exists', 'info')
    return
  end

  local style = config.values.header_guard_style or 'define'
  local guard_name = M._format_guard_name(doc)
  local insert_pos = doc:position_after_header_comment()
  local insert_line = insert_pos and insert_pos:line() or 0

  local header_lines = {}

  if style == 'define' or style == 'both' then
    table.insert(header_lines, '#ifndef ' .. guard_name)
    table.insert(header_lines, '#define ' .. guard_name)
  end

  if style == 'pragma_once' or style == 'both' then
    table.insert(header_lines, '#pragma once')
  end

  if #header_lines == 0 then
    utils.notify('Invalid header_guard_style: ' .. tostring(style), 'warn')
    return
  end

  doc:insert_lines(insert_line, header_lines)
  doc:insert_lines(insert_line + #header_lines, { '' })

  if style == 'define' or style == 'both' then
    local footer_lines = {}
    local last_line_idx = doc:line_count() - 1
    if last_line_idx >= 0 and doc:get_line(last_line_idx):match('%S') then
      table.insert(footer_lines, '')
    end
    table.insert(footer_lines, '#endif // ' .. guard_name)
    doc:insert_lines(doc:line_count(), footer_lines)
  end

  utils.notify('Header guard added', 'info')
end

return M
