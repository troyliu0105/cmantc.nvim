local config = require('cmantic.config')

local M = {}

function M.setup(opts)
  config.merge(opts or {})
end

return M
