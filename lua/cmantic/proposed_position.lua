local M = {}
M.__index = M

function M.new(position, opts)
  local self = setmetatable({}, M)
  self.position = position  -- { line = number, character = number }
  self.options = opts or {}
  -- options table can contain:
  --   relative_to: another position for relative placement
  --   before: boolean - place before relative_to
  --   after: boolean - place after relative_to
  --   next_to: boolean - place next to relative_to
  --   indent: number|boolean - indentation level or true for auto
  --   blank_lines_before: number - blank lines to insert before
  --   blank_lines_after: number - blank lines to insert after
  return self
end

function M:line()
  return self.position and self.position.line or 0
end

function M:character()
  return self.position and self.position.character or 0
end

function M:to_position()
  return {
    line = self:line(),
    character = self:character(),
  }
end

return M
