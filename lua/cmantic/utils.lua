--- Shared utility functions for cmantic.nvim
--- Ported from vscode-cmantic src/utility.ts

local M = {}

-- Access level enum
M.AccessLevel = {
  public = 'public',
  protected = 'protected',
  private = 'private',
}

--- Check if a position is within a range (exclusive of start/end boundaries)
--- @param range table { start = { line = number, character = number }, ['end'] = { line = number, character = number } }
--- @param position table { line = number, character = number }
--- @return boolean
function M.contains_exclusive(range, position)
  if not range or not position or not range.start or not range['end'] then
    return false
  end

  local start_pos = range.start
  local end_pos = range['end']

  -- Position must be after start
  if position.line < start_pos.line then
    return false
  end
  if position.line == start_pos.line and position.character <= start_pos.character then
    return false
  end

  -- Position must be before end
  if position.line > end_pos.line then
    return false
  end
  if position.line == end_pos.line and position.character >= end_pos.character then
    return false
  end

  return true
end

--- Comparator for sorting DocumentSymbols by range start position
--- @param a table DocumentSymbol with range.start
--- @param b table DocumentSymbol with range.start
--- @return boolean true if a should come before b
function M.sort_by_range(a, b)
  if not a or not b or not a.range or not b.range then
    return false
  end

  local a_start = a.range.start
  local b_start = b.range.start

  if a_start.line ~= b_start.line then
    return a_start.line < b_start.line
  end

  return a_start.character < b_start.character
end

--- Get end-of-line string for buffer
--- @param bufnr number Buffer number
--- @return string '\r\n' for dos, '\r' for mac, '\n' for unix
function M.end_of_line(bufnr)
  local fileformat = vim.bo[bufnr].fileformat
  if fileformat == 'dos' then
    return '\r\n'
  elseif fileformat == 'mac' then
    return '\r'
  else
    return '\n'
  end
end

--- Get indentation string based on buffer settings
--- @param bufnr number Buffer number
--- @return string Spaces or tab character
function M.indentation(bufnr)
  if vim.bo[bufnr].expandtab then
    local shiftwidth = vim.bo[bufnr].shiftwidth
    if shiftwidth <= 0 then
      shiftwidth = vim.bo[bufnr].tabstop
    end
    return string.rep(' ', shiftwidth)
  else
    return '\t'
  end
end

--- Check if two arrays share any element
--- @param a table First array
--- @param b table Second array
--- @return boolean true if any element is in both arrays
function M.arrays_intersect(a, b)
  if not a or not b or #a == 0 or #b == 0 then
    return false
  end

  -- Build lookup table from first array
  local lookup = {}
  for _, v in ipairs(a) do
    lookup[v] = true
  end

  -- Check if any element from b is in lookup
  for _, v in ipairs(b) do
    if lookup[v] then
      return true
    end
  end

  return false
end

--- Check if two arrays have identical elements in same order
--- @param a table First array
--- @param b table Second array
--- @return boolean true if arrays are equal
function M.arrays_equal(a, b)
  if a == b then
    return true
  end

  if not a or not b then
    return false
  end

  if #a ~= #b then
    return false
  end

  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end

  return true
end

--- Get file extension without the dot
--- @param path string File path
--- @return string Extension without dot (e.g., 'lua' for 'file.lua')
function M.file_extension(path)
  return vim.fn.fnamemodify(path, ':e')
end

--- Get filename without extension
--- @param path string File path
--- @return string Filename without extension
function M.file_name_no_ext(path)
  return vim.fn.fnamemodify(path, ':t:r')
end

--- Notify with alert level filtering
--- @param msg string Message to display
--- @param level string|nil 'error', 'warn', or 'info' (default: 'info')
function M.notify(msg, level)
  level = level or 'info'

  local ok, config = pcall(require, 'cmantic.config')
  if not ok then
    vim.notify('[C-mantic] ' .. msg, vim.log.levels.INFO)
    return
  end

  local alert_level = config.values.alert_level or 'info'

  -- Map level strings to numeric values for comparison
  local level_map = {
    error = 1,
    warn = 2,
    info = 3,
  }

  -- Map level strings to vim.log.levels
  local vim_level_map = {
    error = vim.log.levels.ERROR,
    warn = vim.log.levels.WARN,
    info = vim.log.levels.INFO,
  }

  -- Only notify if message level <= configured level
  local msg_level = level_map[level] or 3
  local configured_level = level_map[alert_level] or 3

  if msg_level <= configured_level then
    vim.notify('[C-mantic] ' .. msg, vim_level_map[level] or vim.log.levels.INFO)
  end
end

--- Check if two LSP positions are equal
--- @param a table { line = number, character = number }
--- @param b table { line = number, character = number }
--- @return boolean
function M.position_equal(a, b)
  if not a or not b then
    return a == b
  end
  return a.line == b.line and a.character == b.character
end

--- Check if two LSP ranges are equal
--- @param a table Range with start and end positions
--- @param b table Range with start and end positions
--- @return boolean
function M.range_equal(a, b)
  if not a or not b then
    return a == b
  end
  return M.position_equal(a.start, b.start) and M.position_equal(a['end'], b['end'])
end

--- Check if position a is before position b
--- @param a table { line = number, character = number }
--- @param b table { line = number, character = number }
--- @return boolean true if a comes before b
function M.position_before(a, b)
  if not a or not b then
    return false
  end

  if a.line ~= b.line then
    return a.line < b.line
  end

  return a.character < b.character
end

--- Create a position table
--- @param line number Line number (0-indexed)
--- @param character number Character offset (0-indexed)
--- @return table { line = number, character = number }
function M.make_position(line, character)
  return { line = line, character = character }
end

--- Create a range table
--- @param start_line number Start line (0-indexed)
--- @param start_char number Start character (0-indexed)
--- @param end_line number End line (0-indexed)
--- @param end_char number End character (0-indexed)
--- @return table { start = { line, character }, ['end'] = { line, character } }
function M.make_range(start_line, start_char, end_line, end_char)
  return {
    start = { line = start_line, character = start_char },
    ['end'] = { line = end_line, character = end_char },
  }
end

return M
