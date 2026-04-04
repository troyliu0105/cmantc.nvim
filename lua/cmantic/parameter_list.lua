local parse = require('cmantic.parsing')

local M = {}

function M.new(text)
  local self = {}
  self.raw = text or ''
  self.params = M._parse(self.raw)
  return setmetatable(self, { __index = M })
end

function M._parse(text)
  if not text or text == '' then
    return {}
  end

  local masked = parse.mask_non_source_text(text)
  masked = parse.mask_parentheses(masked, false)
  masked = parse.mask_angle_brackets(masked, false)
  masked = parse.mask_braces(masked, false)

  local params = {}
  local start = 1
  for i = 1, #masked do
    if masked:sub(i, i) == ',' then
      local param = parse.trim(text:sub(start, i - 1))
      if param ~= '' then
        table.insert(params, M._parse_param(param))
      end
      start = i + 1
    end
  end

  local last = parse.trim(text:sub(start))
  if last ~= '' then
    table.insert(params, M._parse_param(last))
  end

  return params
end

function M._parse_param(text)
  local masked = parse.mask_non_source_text(text)
  masked = parse.mask_angle_brackets(masked, false)

  local full_text = parse.trim(text)
  local eq_pos = masked:find('=', 1, true)
  if eq_pos then
    text = parse.trim(text:sub(1, eq_pos - 1))
    masked = masked:sub(1, eq_pos - 1)
  end

  local name = masked:match('([%w_]+)%s*$') or ''
  local type_text = ''
  if name ~= '' then
    local name_start = masked:find(name .. '%s*$')
    if name_start and name_start > 1 then
      type_text = parse.trim(text:sub(1, name_start - 1))
    end
  end

  if type_text == '' and name == '' then
    type_text = parse.trim(text)
  end

  return {
    full_text = full_text,
    type = type_text,
    name = name,
  }
end

function M:count()
  return #self.params
end

function M:names()
  local names = {}
  for _, p in ipairs(self.params) do
    table.insert(names, p.name)
  end
  return names
end

function M:types()
  local types = {}
  for _, p in ipairs(self.params) do
    table.insert(types, p.type)
  end
  return types
end

return M
