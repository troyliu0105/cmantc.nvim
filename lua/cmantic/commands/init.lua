local M = {}

M.commands = {
  SwitchHeaderSource = 'cmantic.commands.switch_header_source',
}

function M.execute(name, opts)
  local module_path = M.commands[name]
  if not module_path then
    vim.notify('[C-mantic] Unknown command: ' .. name, vim.log.levels.WARN)
    return
  end
  local cmd = require(module_path)
  cmd.execute(opts)
end

return M
