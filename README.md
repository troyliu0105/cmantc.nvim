# cmantic.nvim

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

C/C++ semantic refactoring and code generation for Neovim. Powered by clangd.

cmantic.nvim is a port of [vscode-cmantic](https://github.com/BigBahss/vscode-cmantic) by Tyler Dennis, rewritten from scratch for Neovim's Lua ecosystem.

## Features

- **Add Definition** -- Generate a function definition from a declaration, placed in the matching source file
- **Add Declaration** -- Generate a function declaration from a definition, placed in the matching header file
- **Move Definition** -- Move function definitions between header and source, or in and out of class bodies
- **Update Signature** -- Synchronize function signatures between declaration and definition
- **Generate Getters/Setters** -- Auto-generate `get`/`set` accessor methods for class member variables
- **Generate Operators** -- Generate comparison and stream operators (`==`, `!=`, `<`, `>`, `<=`, `>=`, `<<`) with member-wise comparison
- **Switch Header/Source** -- Jump between matching header and source files
- **Create Matching Source** -- Generate a `.cpp` from a `.h` with function definition stubs
- **Add Header Guard** -- Insert `#ifndef`/`#define` guards or `#pragma once`
- **Add Include** -- Insert `#include` directives with automatic system/project grouping

## Requirements

- Neovim 0.12+
- [clangd](https://clangd.llvm.org/) (must be configured as your LSP server for C/C++ files)

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  'troyliu0105/cmantc.nvim',
  ft = { 'c', 'cpp', 'h', 'hpp' },
  config = function()
    require('cmantic').setup()
  end,
}
```

### Manual

Clone the repository and add it to your runtime path:

```vim
packadd! cmantic.nvim
```

Then call `require('cmantic').setup()` in your init configuration.

## Configuration

All options have sensible defaults. Call `setup()` with a table to override only what you need.

```lua
require('cmantic').setup({
  -- File extension associations
  header_extensions = { 'h', 'hpp', 'hh', 'hxx' },
  source_extensions = { 'c', 'cpp', 'cc', 'cxx' },

  -- Brace placement for function bodies
  c_curly_brace_function = 'new_line',               -- 'new_line' | 'same_line'
  cpp_curly_brace_function = 'new_line_for_ctors',    -- 'new_line' | 'new_line_for_ctors' | 'same_line'
  cpp_curly_brace_namespace = 'auto',                 -- 'auto' | 'new_line' | 'same_line'

  -- Naming convention for generated accessor names
  case_style = 'camelCase',                           -- 'camelCase' | 'snake_case' | 'PascalCase'

  -- Code generation behavior
  generate_namespaces = true,
  bool_getter_is_prefix = false,
  getter_definition_location = 'inline',              -- 'inline' | 'below_class' | 'source_file'
  setter_definition_location = 'inline',              -- 'inline' | 'below_class' | 'source_file'
  resolve_types = false,
  braced_initialization = false,
  use_explicit_this_pointer = false,
  friend_comparison_operators = false,

  -- Header guard style
  header_guard_style = 'define',                      -- 'define' | 'pragma_once' | 'both'
  header_guard_format = '${FILE_NAME}_${EXT}',

  -- UX
  reveal_new_definition = true,
  always_move_comments = true,
  alert_level = 'info',                               -- 'error' | 'warn' | 'info'
})
```

## Commands

All commands are available as `:Cmantic <command>`. Place your cursor on a symbol (function, class member, etc.) before invoking.

| Command | Description |
|---|---|
| `:Cmantic AddDefinition` | Generate function definition in source file |
| `:Cmantic AddDeclaration` | Generate function declaration in header file |
| `:Cmantic MoveDefinition` | Move definition between header/source or in/out of class |
| `:Cmantic UpdateSignature` | Sync signature between declaration and definition |
| `:Cmantic GenerateGetterSetter` | Generate getter and setter for member variable |
| `:Cmantic GenerateOperators` | Generate comparison and stream operators |
| `:Cmantic SwitchHeaderSource` | Jump to matching header or source file |
| `:Cmantic CreateSourceFile` | Create matching source file with definition stubs |
| `:Cmantic AddHeaderGuard` | Insert header guard (`#ifndef`/`#define` or `#pragma once`) |
| `:Cmantic AddInclude` | Insert `#include` directive |

You can also call commands from Lua:

```lua
vim.keymap.set('n', '<leader>cd', function()
  require('cmantic').add_definition()
end, { desc = 'Add definition' })
```

## How it works

cmantic.nvim combines clangd's LSP symbols with text-based parsing. The plugin uses clangd to locate declarations, definitions, and document symbols. It then applies regex-based text masking to isolate source code from comments, strings, and preprocessor directives. This masked text is parsed for bracket matching, access specifier detection, and scope resolution.

The approach avoids building a full AST. Instead, it relies on LSP-provided symbol ranges as structural scaffolding, with lightweight parsing to fill in the details that LSP doesn't provide (template statements, access specifiers, exact insertion points).

## Credits

Ported from [vscode-cmantic](https://github.com/BigBahss/vscode-cmantic) by Tyler Dennis. The original extension is written in TypeScript for VSCode. This project rewrites the core logic in Lua, adapted to Neovim's LSP client and buffer API.

## Disclaimer

This project was generated by AI. While it aims to faithfully port the vscode-cmantic functionality to Neovim, it may contain bugs, inaccuracies, or incomplete implementations. Use at your own risk. The author assumes no responsibility for any issues arising from the use of this software.

## License

[MIT](LICENSE)
