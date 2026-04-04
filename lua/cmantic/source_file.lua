--- LSP document symbol wrapper for cmantic.nvim
--- Ported from vscode-cmantic src/SourceFile.ts

local M = {}
M.__index = M

--- Create a new SourceFile instance
--- @param uri string File URI (e.g., 'file:///path/to/file.cpp')
--- @return table SourceFile instance
function M.new(uri)
  local self = setmetatable({}, M)
  self.uri = uri
  self.symbols = nil
  return self
end

--- Fetch document symbols from LSP server (clangd preferred)
--- @return table[] Array of DocumentSymbol objects
function M:execute_source_symbol_provider()
  local bufnr = vim.uri_to_bufnr(self.uri)
  if not bufnr or bufnr == 0 then
    return {}
  end

  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  local params = {
    textDocument = vim.lsp.util.make_text_document_params(bufnr),
  }

  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'clangd' })
  if not clients or #clients == 0 then
    clients = vim.lsp.get_clients({ bufnr = bufnr })
  end

  if not clients or #clients == 0 then
    return {}
  end

  local all_symbols = {}

  for _, client in ipairs(clients) do
    local result = client:request_sync('textDocument/documentSymbol', params, 5000, bufnr)

    if result and result.result and type(result.result) == 'table' then
      for _, symbol in ipairs(result.result) do
        table.insert(all_symbols, symbol)
      end
    end
  end

  return all_symbols
end

--- Lazy-load and return document symbols
--- @return table[] Array of DocumentSymbol objects
function M:get_symbols()
  if self.symbols == nil then
    self.symbols = self:execute_source_symbol_provider()
  end
  return self.symbols
end

--- Find a symbol matching the given name and kind (recursive depth-first search)
--- @param target_name string Symbol name to match
--- @param target_kind number LSP SymbolKind to match
--- @return table|nil DocumentSymbol or nil if not found
function M:find_matching_symbol(target_name, target_kind)
  local symbols = self:get_symbols()
  if not symbols or #symbols == 0 then
    return nil
  end

  local function search_recursive(sym_list)
    for _, symbol in ipairs(sym_list) do
      if symbol.name == target_name and symbol.kind == target_kind then
        return symbol
      end

      if symbol.children and #symbol.children > 0 then
        local found = search_recursive(symbol.children)
        if found then
          return found
        end
      end
    end
    return nil
  end

  return search_recursive(symbols)
end

local function symbol_contains_position(symbol, position)
  if not symbol or not symbol.range or not position then
    return false
  end

  local start_pos = symbol.range.start
  local end_pos = symbol.range['end']

  -- Position must satisfy: start <= pos < end (inclusive start, exclusive end)
  local after_start = start_pos.line < position.line
    or (start_pos.line == position.line and start_pos.character <= position.character)

  local before_end = end_pos.line > position.line
    or (end_pos.line == position.line and end_pos.character > position.character)

  return after_start and before_end
end

--- Find the most specific (deepest) symbol at a given position
--- @param position table { line = number, character = number }
--- @return table|nil DocumentSymbol or nil if not found
function M:find_symbol_at_position(position)
  local symbols = self:get_symbols()
  if not symbols or #symbols == 0 then
    return nil
  end

  local function search_deepest(sym_list)
    for _, symbol in ipairs(sym_list) do
      if symbol_contains_position(symbol, position) then
        if symbol.children and #symbol.children > 0 then
          local child_match = search_deepest(symbol.children)
          if child_match then
            return child_match
          end
        end
        return symbol
      end
    end
    return nil
  end

  return search_deepest(symbols)
end

return M
