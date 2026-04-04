--- Normalized DocumentSymbol wrapper for cmantic.nvim
--- Ported from vscode-cmantic src/SourceSymbol.ts
--- Provides clangd-specific normalization and type predicates for LSP symbols.

local M = {}
M.__index = M

--- LSP SymbolKind constants
local SymbolKind = {
  File = 1,
  Module = 2,
  Namespace = 3,
  Package = 4,
  Class = 5,
  Method = 6,
  Property = 7,
  Field = 8,
  Constructor = 9,
  Enum = 10,
  Interface = 11,
  Function = 12,
  Variable = 13,
  Constant = 14,
  String = 15,
  Number = 16,
  Boolean = 17,
  Array = 18,
  Object = 19,
  Key = 20,
  Null = 21,
  EnumMember = 22,
  Struct = 23,
  Event = 24,
  Operator = 25,
  TypeParameter = 26,
}

--- Expose SymbolKind for external use
M.SymbolKind = SymbolKind

--- Strip scope resolution prefix from name (e.g., "Class::method" -> "method")
--- @param name string Symbol name potentially containing ::
--- @return string Name with scope prefix removed
local function strip_scope_resolution(name)
  if not name then
    return ''
  end
  -- Find the last :: and take what's after it
  local last_colon = name:reverse():find('::')
  if last_colon then
    -- Convert reversed position back to forward position
    local pos = #name - last_colon - 1
    return name:sub(pos + 1)
  end
  return name
end

--- Sort children by range start position
--- @param children table[] Array of symbols with range.start
local function sort_children_by_range(children)
  if not children or #children == 0 then
    return
  end
  table.sort(children, function(a, b)
    if not a.range or not b.range then
      return false
    end
    local a_start = a.range.start
    local b_start = b.range.start
    if a_start.line ~= b_start.line then
      return a_start.line < b_start.line
    end
    return a_start.character < b_start.character
  end)
end

--- Create a new SourceSymbol instance
--- @param symbol table Raw LSP DocumentSymbol
--- @param uri string File URI
--- @param parent table|nil Parent SourceSymbol or nil for root
--- @return table SourceSymbol instance
function M.new(symbol, uri, parent)
  local self = setmetatable({}, M)

  self.uri = uri
  self.parent = parent
  self.children = {}

  -- clangd normalization: clean names in .name, signatures in .detail
  local raw_name = symbol.name or ''
  self.name = strip_scope_resolution(raw_name)
  self.detail = symbol.detail or ''
  self.kind = symbol.kind
  self.range = symbol.range
  self.selection_range = symbol.selectionRange

  -- Process children recursively
  if symbol.children and #symbol.children > 0 then
    -- Sort children by range start position
    local sorted_children = vim.deepcopy(symbol.children)
    sort_children_by_range(sorted_children)

    for _, child in ipairs(sorted_children) do
      table.insert(self.children, M.new(child, uri, self))
    end
  end

  return self
end

--- Check if symbol is a function (Function, Method, Constructor, or Operator)
--- @return boolean
function M:is_function()
  return self.kind == SymbolKind.Function
    or self.kind == SymbolKind.Method
    or self.kind == SymbolKind.Constructor
    or self.kind == SymbolKind.Operator
end

--- Check if symbol is a class type (Class or Struct)
--- @return boolean
function M:is_class_type()
  return self.kind == SymbolKind.Class or self.kind == SymbolKind.Struct
end

--- Check if symbol is a class
--- @return boolean
function M:is_class()
  return self.kind == SymbolKind.Class
end

--- Check if symbol is a struct
--- @return boolean
function M:is_struct()
  return self.kind == SymbolKind.Struct
end

--- Check if symbol is a namespace
--- @return boolean
function M:is_namespace()
  return self.kind == SymbolKind.Namespace
end

--- Check if symbol is an enum
--- @return boolean
function M:is_enum()
  return self.kind == SymbolKind.Enum
end

--- Check if symbol is an enum member
--- @return boolean
function M:is_enum_member()
  return self.kind == SymbolKind.EnumMember
end

--- Check if symbol is a member variable (field/property inside a class/struct)
--- @return boolean
function M:is_member_variable()
  if not self.parent then
    return false
  end
  if not self.parent:is_class_type() then
    return false
  end
  return self.kind == SymbolKind.Field or self.kind == SymbolKind.Property
end

--- Check if symbol is a variable (including member variables)
--- @return boolean
function M:is_variable()
  return self.kind == SymbolKind.Variable or self:is_member_variable()
end

--- Check if symbol is a constructor
--- @return boolean
function M:is_constructor()
  if not self.parent then
    return false
  end
  if not self.parent:is_class_type() then
    return false
  end
  -- Either the kind is Constructor, or name matches parent name
  if self.kind == SymbolKind.Constructor then
    return true
  end
  return self.name == self.parent.name
end

--- Check if symbol is a destructor
--- @return boolean
function M:is_destructor()
  return self.name:sub(1, 1) == '~'
end

--- Check if symbol is anonymous
--- @return boolean
function M:is_anonymous()
  return self.name:find('anonymous') ~= nil
end

--- Check if symbol is static (based on detail field)
--- @return boolean
function M:is_static()
  -- Check detail for static keyword with word boundary
  -- This is a simple approach without document access
  if not self.detail then
    return false
  end
  -- Match "static" as a word (followed by space or at end/start)
  return self.detail:match('^static%s') ~= nil
    or self.detail:match('%sstatic%s') ~= nil
    or self.detail:match('%sstatic$') ~= nil
end

--- Get base name with common private member prefixes stripped
--- Strips: leading/trailing underscores, m_ prefix, s_ prefix
--- @return string Cleaned base name
function M:base_name()
  local name = self.name

  -- Strip leading underscores
  name = name:gsub('^_+', '')
  -- Strip trailing underscores
  name = name:gsub('_+$', '')

  -- Strip m_ prefix (common for member variables)
  name = name:gsub('^m_', '')

  -- Strip s_ prefix (common for static members)
  name = name:gsub('^s_', '')

  return name
end

--- Get all ancestor scopes in top-down order
--- @return table[] Array of parent SourceSymbols
function M:scopes()
  local scopes = {}

  local function collect_ancestors(symbol)
    if symbol.parent then
      collect_ancestors(symbol.parent)
      table.insert(scopes, symbol.parent)
    end
  end

  collect_ancestors(self)
  return scopes
end

--- Find definition via LSP textDocument/definition
--- @return table|nil Location result or nil
function M:find_definition()
  local bufnr = vim.uri_to_bufnr(self.uri)
  if not bufnr or bufnr == 0 then
    return nil
  end

  -- Ensure buffer is loaded
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  local params = {
    textDocument = { uri = self.uri },
    position = self.selection_range.start,
  }

  -- Try clangd clients
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'clangd' })
  if not clients or #clients == 0 then
    return nil
  end

  for _, client in ipairs(clients) do
    local result = client:request_sync('textDocument/definition', params, 5000, bufnr)
    if result and result.result then
      -- result can be Location, Location[], or LocationLink[]
      if type(result.result) == 'table' then
        if result.result.uri then
          -- Single Location
          return result.result
        elseif #result.result > 0 then
          -- Array of locations, return first
          return result.result[1]
        end
      end
    end
  end

  return nil
end

--- Find declaration via LSP textDocument/declaration
--- @return table|nil Location result or nil
function M:find_declaration()
  local bufnr = vim.uri_to_bufnr(self.uri)
  if not bufnr or bufnr == 0 then
    return nil
  end

  -- Ensure buffer is loaded
  if not vim.api.nvim_buf_is_loaded(bufnr) then
    vim.fn.bufload(bufnr)
  end

  local params = {
    textDocument = { uri = self.uri },
    position = self.selection_range.start,
  }

  -- Try clangd clients
  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'clangd' })
  if not clients or #clients == 0 then
    return nil
  end

  for _, client in ipairs(clients) do
    local result = client:request_sync('textDocument/declaration', params, 5000, bufnr)
    if result and result.result then
      -- result can be Location, Location[], or LocationLink[]
      if type(result.result) == 'table' then
        if result.result.uri then
          -- Single Location
          return result.result
        elseif #result.result > 0 then
          -- Array of locations, return first
          return result.result[1]
        end
      end
    end
  end

  return nil
end

return M
