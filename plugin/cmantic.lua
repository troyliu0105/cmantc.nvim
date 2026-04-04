local commands = {
  'AddDefinition',
  'AddDeclaration',
  'SwitchHeaderSource',
  'MoveDefinition',
  'GenerateGetterSetter',
  'GenerateOperators',
  'CreateSourceFile',
  'AddHeaderGuard',
  'AddInclude',
  'UpdateSignature',
}

local function complete(arg_lead, cmdline, cursor_pos)
  local matches = {}
  for _, cmd in ipairs(commands) do
    if cmd:lower():find(arg_lead:lower(), 1, true) then
      table.insert(matches, cmd)
    end
  end
  return matches
end

local function run(opts)
  vim.notify('Cmantic: commands not yet implemented', vim.log.levels.INFO)
end

vim.api.nvim_create_user_command('Cmantic', run, {
  nargs = '?',
  complete = complete,
  desc = 'C-mantic: C/C++ code generation',
})
