local M = {}

local cache = {}

local function find_matching(uri)
  local path = vim.uri_to_fname(uri)
  local ext = vim.fn.fnamemodify(path, ':e')
  local name = vim.fn.fnamemodify(path, ':t:r')
  local dir = vim.fn.fnamemodify(path, ':h')
  local config = require('cmantic.config')

  local is_header = vim.tbl_contains(config.header_extensions(), ext)
  local target_exts = is_header and config.source_extensions() or config.header_extensions()

  -- 1. Same directory
  for _, target_ext in ipairs(target_exts) do
    local match = dir .. '/' .. name .. '.' .. target_ext
    if vim.fn.filereadable(match) == 1 then
      return vim.uri_from_fname(match)
    end
  end

  -- 2. Adjacent directories
  local parent = vim.fn.fnamemodify(dir, ':h')
  local adjacent_dirs = {
    parent .. '/src',
    parent .. '/include',
    parent .. '/Source',
    parent .. '/Include',
  }
  for _, target_ext in ipairs(target_exts) do
    for _, search_dir in ipairs(adjacent_dirs) do
      local match = search_dir .. '/' .. name .. '.' .. target_ext
      if vim.fn.filereadable(match) == 1 then
        return vim.uri_from_fname(match)
      end
    end
  end

  -- 3. Workspace-wide glob
  local root = dir
  for _ = 1, 10 do
    if vim.fn.isdirectory(root .. '/.git') == 1
      or vim.fn.filereadable(root .. '/CMakeLists.txt') == 1
      or vim.fn.filereadable(root .. '/Makefile') == 1 then
      break
    end
    local up = vim.fn.fnamemodify(root, ':h')
    if up == root then
      break
    end
    root = up
  end

  for _, target_ext in ipairs(target_exts) do
    local pattern = root .. '/**/' .. name .. '.' .. target_ext
    local matches = vim.fn.glob(pattern, false, true)
    if #matches > 0 then
      table.sort(matches, function(a, b)
        return #a < #b
      end)
      return vim.uri_from_fname(matches[1])
    end
  end

  return nil
end

function M.get_matching(uri)
  if not uri then
    return nil
  end
  if not cache[uri] then
    cache[uri] = find_matching(uri)
  end
  return cache[uri]
end

function M.clear_cache()
  cache = {}
end

return M
