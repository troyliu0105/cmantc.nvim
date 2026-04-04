--- Create Matching Source File command for cmantic.nvim
--- Ported from vscode-cmantic src/commands/createSourceFile.ts
--- Creates a new source file (.cpp/.c) from a header file (.h/.hpp)
--- with function definitions for all declarations.

local M = {}

local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')
local config = require('cmantic.config')
local utils = require('cmantic.utils')
local header_source = require('cmantic.header_source')

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Wrap a SourceSymbol as CSymbol if needed
--- @param symbol table SourceSymbol
--- @param doc table SourceDocument
--- @return table CSymbol
local function ensure_csymbol(symbol, doc)
  if symbol.document then
    return symbol
  end
  return CSymbol.new(symbol, doc)
end

--- Collect all namespace symbols from a symbol list
--- @param symbols table[] Array of SourceSymbols
--- @return table[] Array of namespace SourceSymbols
local function collect_namespaces(symbols)
  local namespaces = {}
  for _, sym in ipairs(symbols) do
    if sym:is_namespace() then
      table.insert(namespaces, sym)
    end
  end
  return namespaces
end

--- Collect all function declarations from symbols (recursive)
--- @param symbols table[] Array of SourceSymbols
--- @param doc table SourceDocument
--- @return table[] Array of CSymbols that are function declarations
local function collect_function_declarations(symbols, doc)
  local declarations = {}

  local function collect(sym_list)
    for _, symbol in ipairs(sym_list) do
      local csymbol = ensure_csymbol(symbol, doc)

      if csymbol:is_function() and csymbol:is_function_declaration() then
        -- Skip pure virtual, deleted, defaulted functions
        if not csymbol:is_pure_virtual() and not csymbol:is_deleted_or_defaulted() then
          table.insert(declarations, csymbol)
        end
      end

      -- Recurse into children (namespaces, classes)
      if symbol.children and #symbol.children > 0 then
        collect(symbol.children)
      end
    end
  end

  collect(symbols)
  return declarations
end

--- Get namespace depth for a symbol
--- @param symbol table CSymbol
--- @return number Depth (0 = no namespace, 1+ = nested)
local function get_namespace_depth(symbol)
  local scopes = symbol:scopes()
  local depth = 0
  for _, scope in ipairs(scopes) do
    if scope:is_namespace() then
      depth = depth + 1
    end
  end
  return depth
end

--- Get the innermost namespace name for a symbol
--- @param symbol table CSymbol
--- @return string|nil Namespace name or nil
local function get_innermost_namespace(symbol)
  local scopes = symbol:scopes()
  for i = #scopes, 1, -1 do
    if scopes[i]:is_namespace() then
      return scopes[i].name
    end
  end
  return nil
end

--- Build namespace opening lines
--- @param namespaces table[] Array of namespace symbols (in order)
--- @return string[] Lines for namespace openings
local function build_namespace_opens(namespaces)
  local lines = {}
  for _, ns in ipairs(namespaces) do
    table.insert(lines, 'namespace ' .. ns.name)
    table.insert(lines, '{')
  end
  return lines
end

--- Build namespace closing lines
--- @param namespaces table[] Array of namespace symbols
--- @return string[] Lines for namespace closings
local function build_namespace_closes(namespaces)
  local lines = {}
  for i = #namespaces, 1, -1 do
    table.insert(lines, '} // namespace ' .. namespaces[i].name)
  end
  return lines
end

--- Reveal the new file in the editor
--- @param bufnr number Buffer number
--- @param line number Line number (0-indexed)
local function reveal_definition(bufnr, line)
  if not config.values.reveal_new_definition then
    return
  end

  -- Switch to the target buffer if different from current
  local current_bufnr = vim.api.nvim_get_current_buf()
  if current_bufnr ~= bufnr then
    vim.api.nvim_win_set_buf(0, bufnr)
  end

  -- Set cursor to the new definition (line is 0-indexed, cursor is 1-indexed)
  vim.api.nvim_win_set_cursor(0, { line + 1, 0 })
end

--------------------------------------------------------------------------------
-- Main Functions
--------------------------------------------------------------------------------

--- Execute the Create Source File command
--- Algorithm:
--- 1. Get current buffer — must be a header file
--- 2. Check if matching source file already exists
--- 3. Get file info (path, name, extension, directory)
--- 4. Build source file content with:
---    a. Include directive
---    b. Namespace wrappers (if configured)
---    c. Function definitions for all declarations
--- 5. Write the file
--- 6. Open it in Neovim
function M.execute()
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = SourceDocument.new(bufnr)

  -- Verify it's a header file
  if not doc:is_header() then
    utils.notify('Current file is not a header file', 'warn')
    return
  end

  -- Check if matching source file already exists
  local uri = vim.uri_from_bufnr(bufnr)
  local existing = header_source.get_matching(uri)
  if existing and vim.fn.filereadable(vim.uri_to_fname(existing)) == 1 then
    utils.notify('Matching source file already exists: ' .. vim.uri_to_fname(existing), 'warn')
    return
  end

  -- Get file info
  local header_path = vim.uri_to_fname(uri)
  local header_name = utils.file_name_no_ext(header_path)
  local header_ext = utils.file_extension(header_path)
  local header_dir = vim.fn.fnamemodify(header_path, ':h')

  -- Determine target extension (prefer .cpp, then first from config)
  local source_exts = config.source_extensions()
  local target_ext = source_exts[1] or 'cpp'

  -- Build target path: same directory as header
  local target_path = header_dir .. '/' .. header_name .. '.' .. target_ext

  -- Get header include path (just the filename)
  local include_path = header_name .. '.' .. header_ext

  -- Build source file content
  local lines = {}

  -- Include directive
  table.insert(lines, '#include "' .. include_path .. '"')
  table.insert(lines, '')

  -- Get symbols from header
  local symbols = doc:get_c_symbols()

  -- Find all namespace blocks
  local namespaces = collect_namespaces(symbols)

  -- Find all function declarations
  local declarations = collect_function_declarations(symbols, doc)

  if #declarations == 0 then
    utils.notify('No function declarations found in header', 'info')
    -- Still create the file with just the include
  end

  -- Generate namespace wrappers if configured
  if config.values.generate_namespaces and #namespaces > 0 then
    local ns_opens = build_namespace_opens(namespaces)
    for _, line in ipairs(ns_opens) do
      table.insert(lines, line)
    end
    table.insert(lines, '')
  end

  -- Generate function definitions
  for _, decl in ipairs(declarations) do
    -- Generate definition text
    local def = decl:new_function_definition(doc, nil)
    if def and def ~= '' then
      -- Add each line of the definition
      for line in def:gmatch('[^\n]+') do
        table.insert(lines, line)
      end
      table.insert(lines, '')
    end
  end

  -- Close namespaces
  if config.values.generate_namespaces and #namespaces > 0 then
    -- Remove trailing empty line if present
    if lines[#lines] == '' then
      table.remove(lines)
    end
    table.insert(lines, '')

    local ns_closes = build_namespace_closes(namespaces)
    for _, line in ipairs(ns_closes) do
      table.insert(lines, line)
    end
  end

  -- Ensure file ends with newline
  if lines[#lines] ~= '' then
    table.insert(lines, '')
  end

  -- Write the file
  local content = table.concat(lines, '\n')
  local f, err = io.open(target_path, 'w')
  if not f then
    utils.notify('Failed to create file: ' .. target_path .. ' (' .. (err or 'unknown error') .. ')', 'error')
    return
  end
  f:write(content)
  f:close()

  -- Open the new file
  vim.cmd.edit(target_path)

  -- Get the new buffer number
  local new_bufnr = vim.api.nvim_get_current_buf()

  utils.notify('Created source file: ' .. target_path, 'info')

  -- Reveal first definition if there are any
  if #declarations > 0 then
    -- Find the line with the first definition (after include and namespace opens)
    local first_def_line = 2 -- Start after include + blank line
    if config.values.generate_namespaces and #namespaces > 0 then
      first_def_line = first_def_line + #namespaces * 2 + 1 -- namespace opens + blank line
    end
    reveal_definition(new_bufnr, first_def_line)
  end
end

return M
