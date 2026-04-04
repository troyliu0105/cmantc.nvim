# PROJECT KNOWLEDGE BASE

**Generated:** 2026-04-04
**Commit:** 4f02ac8
**Branch:** main

## OVERVIEW

C/C++ semantic refactoring plugin for Neovim. Port of vscode-cmantic (BigBahss/vscode-cmantic) from TypeScript to Lua. Uses clangd LSP + regex text masking (no AST).

## STRUCTURE

```
cmantic.nvim/
├── plugin/cmantic.lua          # :Cmantic user command registration
├── lua/cmantic/
│   ├── init.lua                # setup() entry, wires config + code_action
│   ├── config.lua              # 17 user-facing settings + case formatter
│   ├── parsing.lua             # Text masking engine (comments, strings, balanced brackets)
│   ├── utils.lua               # Position/range helpers, indentation, notify
│   ├── source_file.lua         # LSP documentSymbol request wrapper
│   ├── source_symbol.lua       # Normalized DocumentSymbol with clangd predicates
│   ├── c_symbol.lua            # Core engine: extends SourceSymbol with document-aware text access
│   ├── source_document.lua     # Buffer wrapper: text access, smart positioning, insertion
│   ├── header_source.lua       # 3-tier header/source file matching + cache
│   ├── code_action.lua         # Action detection + vim.ui.select dispatch
│   ├── accessor.lua            # Getter/setter text generation
│   ├── operator.lua            # Comparison/stream operator text generation
│   ├── function_signature.lua  # Signature parsing (return type, name, params, trailing)
│   ├── parameter_list.lua      # Parameter list parsing into type/name pairs
│   ├── proposed_position.lua   # Insertion point data class
│   ├── sub_symbol.lua          # Lightweight positional text reference
│   └── commands/               # Per-feature command modules (see commands/AGENTS.md)
├── docs/plans/                 # Design doc + implementation plan
└── README.md
```

## WHERE TO LOOK

| Task | Start Here | Key Collaborators |
|------|-----------|-------------------|
| Add new command | `commands/init.lua` (register) + new file in `commands/` | `source_document.lua`, `c_symbol.lua` |
| Change code generation | `c_symbol.lua` (`format_declaration`, `new_function_definition`) | `config.lua`, `parsing.lua` |
| Change smart positioning | `source_document.lua` (`find_smart_position_*`) | `proposed_position.lua` |
| Change text parsing/masking | `parsing.lua` | Used everywhere |
| Change symbol detection | `c_symbol.lua` (predicates) or `source_symbol.lua` (base predicates) | `code_action.lua` |
| Add config option | `config.lua` (add default + accessor) | Consume via `config.values.X` |
| Change header/source matching | `header_source.lua` | `config.lua` (extensions) |
| Change code action menu | `code_action.lua` (`get_applicable_actions`) | Command modules |

## ARCHITECTURE

### Inheritance Chain
```
DocumentSymbol (LSP raw)
  → SourceSymbol (normalized, clangd predicates, children sorted)
    → CSymbol (document-aware, specifier detection, formatting)
```

### Core Data Flow
```
User action → code_action.lua or :Cmantic
  → SourceDocument (buffer + LSP symbols)
    → CSymbol (at cursor position)
      → parsing.lua (mask text, extract structure)
        → SourceDocument.insert_text (apply changes)
```

### Module Dependencies (critical paths)
- `c_symbol` → `source_symbol`, `parsing`, `utils`, `config`
- `source_document` → `source_file`, `source_symbol`, `sub_symbol`, `proposed_position`, `parsing`, `config`
- `code_action` → `source_document`, `c_symbol`, `header_source`, lazy-loads all `commands.*`
- `commands/*` → `source_document`, `c_symbol`, `utils`, `config`, `header_source` (varies by feature)

## CONVENTIONS

- **Module pattern**: `local M = {}; M.__index = M; function M.new(...) setmetatable({}, M) ... end; return M`
- **Inheritance**: `setmetatable(child_module, { __index = parent_module })` — see c_symbol extends source_symbol
- **Config access**: `require('cmantic.config').values.FIELD` — never cache config values, always re-read
- **Naming**: snake_case for Lua identifiers, PascalCase for command names in registry
- **Error handling**: `utils.notify(msg, level)` for user messages, `pcall` in command dispatcher
- **Lazy loading**: Command modules loaded via `require()` inside action helpers, not at top level
- **Keyword matching**: Use `%f[%w]keyword%f[%W]` (Lua frontier patterns) for word-boundary detection
- **Buffer ops**: Use `vim.api.nvim_buf_get_text`, `nvim_buf_set_text`, `nvim_buf_get_lines` — never `vim.fn.getline`
- **LSP client**: Use `vim.lsp.get_clients` (Neovim 0.10+), NOT `get_active_clients`

## ANTI-PATTERNS (THIS PROJECT)

- **Do NOT build an AST** — use LSP symbol ranges as scaffolding + regex text masking
- **Do NOT use Lua 5.3+ features** — no bitwise ops, no `//` operator, no `goto`
- **Do NOT suppress type info** — no `as any` equivalents, no ignoring return values
- **Do NOT cache `config.values`** — user may call `setup()` again; always re-read
- **Do NOT modify symbols in-place** — CSymbol caches (_parsable_text, _access_specifiers) are fine, but don't mutate range/name

## KNOWN ISSUES

- `commands/init.lua` dispatcher mutates `cmd.execute` after first call (pcall reassignment) — safe for single invocations but be aware
- `header_source.lua` caches matches per-session; call `clear_cache()` if files move externally
- `parsing.lua` raw string matching uses manual scanning (Lua lacks backreferences) — edge cases with unusual delimiters possible

## COMMANDS

```bash
# No build step required — pure Lua plugin
# Test manually with :Cmantic <command> on C/C++ files with clangd attached
```
