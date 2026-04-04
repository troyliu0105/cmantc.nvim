local parse = require('cmantic.parsing')

local M = {}
function M.new(text)
  local self = {}
  self.raw = text or ''
  self.masked = parse.mask_non_source_text(self.raw)

  self.return_type = M._extract_return_type(self.masked)
  self.name = M._extract_name(self.masked)
  self.parameters = M._extract_parameters(self.raw)
  self.trailing = M._extract_trailing(self.masked)

  setmetatable(self, { __index = M })
  return self
end

function M._extract_return_type(masked)
  local before_paren = masked:match('^(.*)%(')
  if not before_paren then
    return ''
  end

  before_paren = parse.trim(before_paren)
  if before_paren == '' then
    return ''
  end

  local func_token = before_paren:match('(%S+)%s*$')
  if not func_token then
    return ''
  end

  local type_start = before_paren:find(func_token, 1, true)
  if type_start and type_start > 1 then
    return parse.trim(before_paren:sub(1, type_start - 1))
  end
  return ''
end

function M._extract_name(masked)
  local before_paren = masked:match('^(.*)%(')
  if not before_paren then
    return ''
  end

  before_paren = parse.trim(before_paren)
  if before_paren == '' then
    return ''
  end

  local name = before_paren:match('(%S+)%s*$')
  if not name then
    return ''
  end

  local short = name:match('::([%w_~]+)$')
  if short then
    return short
  end
  return name
end

function M._extract_parameters(text)
  if not text or text == '' then
    return ''
  end

  local start = text:find('%(')
  if not start then
    return ''
  end

  local depth = 1
  local i = start + 1
  while i <= #text and depth > 0 do
    local c = text:sub(i, i)
    if c == '(' then
      depth = depth + 1
    elseif c == ')' then
      depth = depth - 1
    end
    i = i + 1
  end

  return parse.trim(text:sub(start + 1, i - 2))
end

function M._extract_trailing(masked)
  local after = masked:match('%)(.*)')
  if not after then
    return ''
  end
  return parse.trim(after)
end

function M:equals(other)
  if not other then
    return false
  end
  return self.name == other.name
    and parse.strip_default_values(self.parameters) == parse.strip_default_values(other.parameters)
    and self.return_type == other.return_type
    and self.trailing == other.trailing
end

function M.from_symbol(csymbol, doc)
  local text = doc:get_text(csymbol.range)
  return M.new(text)
end

return M
