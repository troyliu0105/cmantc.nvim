--- Accessor (getter/setter) generation for cmantic.nvim
--- Ported from vscode-cmantic src/Accessor.ts

local M = {}

local parse = require('cmantic.parsing')
local config = require('cmantic.config')

--- Create a getter for a member variable
--- @param member_var table CSymbol for a member variable
--- @return table { name, return_type, parameter, body, qualifier }
function M.create_getter(member_var)
  local name = member_var:getter_name()
  local return_type = M._extract_type(member_var)
  local qualifier = member_var:is_static() and '' or ' const'

  local body
  if config.values.use_explicit_this_pointer and not member_var:is_static() then
    body = 'return this->' .. member_var.name .. ';'
  else
    body = 'return ' .. member_var.name .. ';'
  end

  return {
    name = name,
    return_type = return_type,
    parameter = '',
    body = body,
    qualifier = qualifier,
  }
end

--- Create a setter for a member variable
--- @param member_var table CSymbol for a member variable
--- @return table { name, return_type, parameter, body, qualifier }
function M.create_setter(member_var)
  local name = member_var:setter_name()
  local return_type = 'void'
  local base = member_var:base_name()
  local param_name = M._safe_param_name(base)
  local raw_type = M._extract_type(member_var)
  local param_type

  if member_var:is_pointer() then
    param_type = raw_type
  elseif parse.matches_primitive_type(raw_type) then
    param_type = raw_type
  else
    param_type = 'const ' .. raw_type .. '&'
  end

  local body
  if config.values.use_explicit_this_pointer then
    body = 'this->' .. member_var.name .. ' = ' .. param_name .. ';'
  else
    body = member_var.name .. ' = ' .. param_name .. ';'
  end

  return {
    name = name,
    return_type = return_type,
    parameter = param_type .. ' ' .. param_name,
    body = body,
    qualifier = '',
  }
end

--- Extract the type from the member variable's parsable leading text
--- @param member_var table CSymbol for a member variable
--- @return string Type string
function M._extract_type(member_var)
  local leading = member_var:parsable_leading_text()
  local specifiers = { 'static', 'mutable', 'constexpr', 'inline', 'register', 'volatile', 'extern', 'thread_local' }

  for _, spec in ipairs(specifiers) do
    local pattern = '%f[%w]' .. spec .. '%f[%W]%s*'
    leading = leading:gsub(pattern, '')
  end

  return parse.normalize_whitespace(leading)
end

--- Generate a safe parameter name (avoid C++ keywords)
--- @param base string Base name
--- @return string Safe parameter name
function M._safe_param_name(base)
  local keywords = {
    'alignas', 'alignof', 'and', 'and_eq', 'asm', 'auto', 'bitand', 'bitor',
    'bool', 'break', 'case', 'catch', 'char', 'char8_t', 'char16_t', 'char32_t',
    'class', 'compl', 'concept', 'const', 'consteval', 'constexpr', 'const_cast',
    'continue', 'co_await', 'co_return', 'co_yield', 'decltype', 'default', 'delete',
    'do', 'double', 'dynamic_cast', 'else', 'enum', 'explicit', 'export', 'extern',
    'false', 'float', 'for', 'friend', 'goto', 'if', 'inline', 'int', 'long',
    'mutable', 'namespace', 'new', 'noexcept', 'not', 'not_eq', 'nullptr',
    'operator', 'or', 'or_eq', 'private', 'protected', 'public', 'register',
    'reinterpret_cast', 'requires', 'return', 'short', 'signed', 'sizeof',
    'static', 'static_assert', 'static_cast', 'struct', 'switch', 'template',
    'this', 'thread_local', 'throw', 'true', 'try', 'typedef', 'typeid', 'typename',
    'union', 'unsigned', 'using', 'virtual', 'void', 'volatile', 'wchar_t', 'while',
    'xor', 'xor_eq',
  }

  local keyword_set = {}
  for _, kw in ipairs(keywords) do
    keyword_set[kw] = true
  end

  if keyword_set[base] then
    return base .. '_'
  end

  return base
end

--- Format getter as declaration string
--- @param getter table Getter table from create_getter
--- @param scope string|nil Optional scope prefix (e.g., "Class::")
--- @return string Declaration string
function M.format_getter_declaration(getter, scope)
  scope = scope or ''
  return getter.return_type .. ' ' .. scope .. getter.name .. '()' .. getter.qualifier .. ';'
end

--- Format setter as declaration string
--- @param setter table Setter table from create_setter
--- @param scope string|nil Optional scope prefix (e.g., "Class::")
--- @return string Declaration string
function M.format_setter_declaration(setter, scope)
  scope = scope or ''
  return setter.return_type .. ' ' .. scope .. setter.name .. '(' .. setter.parameter .. ');'
end

--- Format getter as definition string
--- @param getter table Getter table from create_getter
--- @param scope string|nil Optional scope prefix (e.g., "Class::")
--- @param indent string|nil Optional indentation for body
--- @return string Definition string
function M.format_getter_definition(getter, scope, indent)
  scope = scope or ''
  indent = indent or ''
  return getter.return_type .. ' ' .. scope .. getter.name .. '()' .. getter.qualifier
    .. '\n' .. indent .. '{\n'
    .. indent .. '  ' .. getter.body .. '\n'
    .. indent .. '}'
end

--- Format setter as definition string
--- @param setter table Setter table from create_setter
--- @param scope string|nil Optional scope prefix (e.g., "Class::")
--- @param indent string|nil Optional indentation for body
--- @return string Definition string
function M.format_setter_definition(setter, scope, indent)
  scope = scope or ''
  indent = indent or ''
  return setter.return_type .. ' ' .. scope .. setter.name .. '(' .. setter.parameter .. ')'
    .. '\n' .. indent .. '{\n'
    .. indent .. '  ' .. setter.body .. '\n'
    .. indent .. '}'
end

return M
