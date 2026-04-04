local M = {}

M.commands = {
  SwitchHeaderSource = 'cmantic.commands.switch_header_source',
  AddDeclaration = 'cmantic.commands.add_declaration',
  AddDefinition = 'cmantic.commands.add_definition',
  MoveDefinition = 'cmantic.commands.move_definition',
  AddInclude = 'cmantic.commands.add_include',
  GenerateOperators = 'cmantic.commands.generate_operators',
  GenerateGetterSetter = 'cmantic.commands.generate_getter_setter',
  UpdateSignature = 'cmantic.commands.update_signature',
  CreateSourceFile = 'cmantic.commands.create_source_file',
  AddHeaderGuard = 'cmantic.commands.add_header_guard',
}

function M.execute(name, opts)
  local module_path = M.commands[name]
  if not module_path then
    vim.notify('[C-mantic] Unknown command: ' .. name, vim.log.levels.WARN)
    return
  end
  local ok, cmd = pcall(require, module_path)
  if not ok then
    vim.notify('[C-mantic] Failed to load command: ' .. name .. '\n' .. cmd, vim.log.levels.ERROR)
    return
  end
  ok, cmd.execute = pcall(cmd.execute, opts)
  if not ok then
    vim.notify('[C-mantic] Error in ' .. name .. ': ' .. cmd.execute, vim.log.levels.ERROR)
  end
end

return M
