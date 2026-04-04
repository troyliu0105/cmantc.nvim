local M = {}

--- Create a Neovim buffer with the given lines and filetype
--- @param lines string[] Buffer lines
--- @param ft string|nil Filetype (default 'cpp')
--- @return number bufnr
function M.create_buffer(lines, ft)
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = ft or 'cpp'
  return bufnr
end

--- Create a mock LSP DocumentSymbol table
--- @param opts table { name, kind, range, selection_range, children, detail }
--- @return table Mock DocumentSymbol
function M.mock_symbol(opts)
  return {
    name = opts.name or 'test',
    kind = opts.kind or 12,
    range = opts.range or {
      start = opts.range_start or { line = opts.start_line or 0, character = opts.start_char or 0 },
      ['end'] = opts.range_end or { line = opts.end_line or 0, character = opts.end_char or 10 },
    },
    selectionRange = opts.selection_range or {
      start = opts.selection_start or { line = opts.sel_start_line or opts.start_line or 0, character = opts.sel_start_char or opts.start_char or 0 },
      ['end'] = opts.selection_end or { line = opts.sel_end_line or opts.end_line or 0, character = opts.sel_end_char or opts.end_char or 10 },
    },
    children = opts.children or {},
    detail = opts.detail or '',
  }
end

--- Create a SourceDocument from lines
--- @param lines string[] Buffer content
--- @param ft string|nil Filetype
--- @return table SourceDocument
function M.create_source_document(lines, ft)
  local bufnr = M.create_buffer(lines, ft)
  local SourceDocument = require('cmantic.source_document')
  return SourceDocument.new(bufnr)
end

--- Read a fixture file and return its lines
--- @param name string Fixture path relative to tests/fixtures/
--- @return string[] Lines
function M.read_fixture(name)
  local path = vim.fn.fnamemodify(vim.loop.cwd(), ':p') .. 'tests/fixtures/' .. name
  local contents = vim.fn.readfile(path)
  return contents
end

--- Create a buffer from a fixture file
--- @param name string Fixture path relative to tests/fixtures/
--- @param ft string|nil Filetype (auto-detected from extension if nil)
--- @return number bufnr
function M.create_buffer_from_fixture(name, ft)
  local lines = M.read_fixture(name)
  if not ft then
    local ext = name:match('%.(%w+)$')
    local ft_map = { h = 'c', hpp = 'cpp', hh = 'cpp', hxx = 'cpp', c = 'c', cpp = 'cpp', cc = 'cpp', cxx = 'cpp' }
    ft = ft_map[ext] or 'cpp'
  end
  return M.create_buffer(lines, ft)
end

return M
