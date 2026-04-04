local M = {}
M.__index = M

function M.new(document, range, selection_range)
  local self = setmetatable({}, M)
  self.document = document
  self.range = range
  self.selection_range = selection_range or range
  self.name = ''
  if document and range then
    self.name = document:get_text(range) or ''
  end
  return self
end

function M:text()
  if not self.document or not self.range then
    return ''
  end
  return self.document:get_text(self.range)
end

return M
