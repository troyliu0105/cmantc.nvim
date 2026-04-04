local config = require('cmantic.config')
local code_action = require('cmantic.code_action')

local M = {}

function M.setup(opts)
  config.merge(opts or {})
  code_action.setup()
end

-- Expose code_action module for direct use
M.code_action = code_action

-- Convenience command to show actions at cursor
function M.show_actions()
  code_action.show_actions(0, nil)
end

return M
