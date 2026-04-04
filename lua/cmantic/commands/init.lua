local M = {}

M.commands = {
  SwitchHeaderSource = 'cmantic.commands.switch_header_source',
  AddDeclaration = 'cmantic.commands.add_declaration',
  AddDefinition = 'cmantic.commands.add_definition',
  MoveDefinition = 'cmantic.commands.move_definition',
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
