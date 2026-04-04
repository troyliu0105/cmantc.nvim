--- Add/Amend Header Guard command for cmantic.nvim
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

--- Extract existing guard name from header guard directives
--- @param doc table SourceDocument
--- @return string|nil Existing guard name or nil
function M._get_existing_guard_name(doc)
  local directives = doc:get_header_guard_directives()
  for _, directive in ipairs(directives) do
    local text = directive:text()
    local name = text:match('^%s*#%s*ifndef%s+([%w_]+)')
    if name then
      return name
    end
  end
  return nil
end

--- Execute Amend Header Guard command
--- Replaces existing guard name with the correct one based on current filename
--- @param doc table SourceDocument
--- @param new_guard string New guard name
function M._amend_guard(doc, new_guard)
  local old_guard = M._get_existing_guard_name(doc)
  if not old_guard then
    utils.notify('Could not find existing guard name to amend', 'warn')
    return
  end

  if old_guard == new_guard then
    utils.notify('Header guard is already correct', 'info')
    return
  end

  local directives = doc:get_header_guard_directives()
  for _, directive in ipairs(directives) do
    local text = directive:text()
    local new_text = text:gsub(old_guard, new_guard, 1)
    if new_text ~= text then
      doc:replace_text(directive.range, new_text)
    end
  end

  utils.notify('Header guard amended: ' .. old_guard .. ' → ' .. new_guard, 'info')
end

--- Execute Add Header Guard command
--- Algorithm:
--- 1. Ensure current buffer is a header file
--- 2. If guard already exists → amend (update guard name to match current filename)
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

  local guard_name = M._format_guard_name(doc)

  -- If guard already exists, amend it
  if doc:has_header_guard() then
    M._amend_guard(doc, guard_name)
    return
  end

  if doc:has_pragma_once() then
    utils.notify('Header uses #pragma once (nothing to amend)', 'info')
    return
  end

  local style = config.values.header_guard_style or 'define'
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
