# commands/ — Per-Feature Command Modules

## OVERVIEW

Each file implements one `:Cmantic` command. All export `M.execute(opts)` (some add `execute_in_source`, `execute_in_current`, etc.).

## WHERE TO LOOK

| Command | File | Key Dependencies |
|---------|------|-----------------|
| AddDefinition | `add_definition.lua` | `source_document`, `c_symbol`, `header_source` |
| AddDeclaration | `add_declaration.lua` | `source_document`, `c_symbol`, `header_source` |
| MoveDefinition | `move_definition.lua` | `source_document`, `c_symbol`, `header_source` |
| GenerateGetterSetter | `generate_getter_setter.lua` | `source_document`, `c_symbol`, `accessor` |
| GenerateOperators | `generate_operators.lua` | `source_document`, `c_symbol`, `operator` |
| UpdateSignature | `update_signature.lua` | `source_document`, `c_symbol`, `function_signature`, `header_source` |
| CreateSourceFile | `create_source_file.lua` | `source_document`, `c_symbol`, `header_source` |
| SwitchHeaderSource | `switch_header_source.lua` | `header_source` (clangd fallback) |
| AddHeaderGuard | `add_header_guard.lua` | `source_document` |
| AddInclude | `add_include.lua` | `source_document` |

## CONVENTIONS

- All commands start by getting cursor position → `SourceDocument.new(bufnr)` → `doc:get_symbol_at_position(pos)`
- Wrap symbol as CSymbol when type predicates or formatting needed: `CSymbol.new(symbol, doc)`
- Error out early with `utils.notify(msg, vim.log.levels.WARN)` if preconditions fail
- Respect `config.values.reveal_new_definition` for cursor jumping after insertion
- Register new commands in both `init.lua` (registry table) AND `plugin/cmantic.lua` (completion list)

## DISPATCHER

`init.lua` routes `M.execute(name)` → `pcall(require, module_path)` → `pcall(cmd.execute, opts)`. Note: the second pcall reassigns `cmd.execute` — safe for single calls per session but don't rely on `cmd.execute` being a function afterward.
