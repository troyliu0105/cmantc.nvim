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
  local cmd_module = require('cmantic.commands')
  local args = opts.args and opts.args:match('^%S+') or ''
  if args == '' then
    require('cmantic').show_actions()
  else
    cmd_module.execute(args)
  end
end

vim.api.nvim_create_user_command('Cmantic', run, {
  nargs = '?',
  complete = complete,
  desc = 'C-mantic: C/C++ code generation',
})
