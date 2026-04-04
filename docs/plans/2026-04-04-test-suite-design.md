# Test Suite Design

**Date:** 2026-04-04
**Decision:** plenary.nvim unified framework, three-layer test structure

## Architecture

All tests use plenary.nvim `test_harness`. Three layers with increasing scope:

### Layer 1: Unit Tests (`tests/unit/`)

Headless Neovim, no external dependencies. Test pure-logic modules:

| Module                 | Key Tests                                                                  |
| ---------------------- | -------------------------------------------------------------------------- |
| `parsing`              | mask_comments, mask_quotes, mask_raw_strings, mask_non_source_text, mask_balanced, strip_default_values, normalize_whitespace, is_blank, trim, matches_primitive_type |
| `function_signature`   | return type extraction, name extraction (including scope resolution), parameter extraction, trailing text, equals comparison |
| `source_symbol`        | is_function, is_class_type, is_member_variable, is_constructor, is_destructor, base_name, scopes, strip_scope_resolution |
| `config`               | format_to_case_style (camelCase/snake_case/PascalCase), merge behavior     |
| `utils`                | contains_exclusive, position_equal, range_equal, position_before, arrays_equal, arrays_intersect |

### Layer 2: Integration Tests (`tests/integration/`)

Headless Neovim with mock buffer/LSP data. Test modules that need document context:

| Module              | Key Tests                                                                 |
| ------------------- | ------------------------------------------------------------------------- |
| `source_document`   | is_header/is_source detection, header guard detection (add/amend/existing), preprocessor directive parsing, symbol_contains_position, get_symbol_at_position |
| `c_symbol`          | is_function_declaration, is_function_definition, is_virtual, is_inline, is_static, is_const, template_statements, format_declaration, getter/setter names |
| `code_action`       | get_applicable_actions returns correct actions per context (empty header, guarded header, class member, function decl/def) |
| `header_guard`      | _format_guard_name, _amend_guard (rename guard), execute (add new guard)  |

Mocking strategy: create real Neovim buffers via `vim.api.nvim_buf_set_lines`, inject mock LSP DocumentSymbol tables directly.

### Layer 3: E2E Smoke Tests (`tests/e2e/`)

Headless Neovim + real clangd. 4-6 core flows:

1. Add header guard to empty header → verify `#ifndef/#define/#endif` inserted
2. Add definition from header declaration → verify definition appears in source
3. Generate getter/setter from class member → verify methods generated
4. Amend header guard after rename → verify guard name updated
5. No actions on non-C/C++ files → verify empty result

## Directory Structure

```
tests/
├── minimal_init.lua              — headless Neovim bootstrap
├── helpers.lua                   — shared test helpers (create_buffer, mock_symbols, etc.)
├── unit/
│   ├── parsing_spec.lua
│   ├── function_signature_spec.lua
│   ├── source_symbol_spec.lua
│   ├── config_spec.lua
│   └── utils_spec.lua
├── integration/
│   ├── source_document_spec.lua
│   ├── c_symbol_spec.lua
│   ├── code_action_spec.lua
│   └── header_guard_spec.lua
├── e2e/
│   └── smoke_spec.lua
└── fixtures/
    ├── c++/
    │   ├── empty_header.h
    │   ├── guarded_header.h
    │   ├── class_with_members.hpp
    │   ├── class_with_methods.hpp
    │   ├── function_decls.hpp         — free function declarations
    │   ├── function_defs.cpp          — matching definitions
    │   ├── template_class.hpp
    │   ├── namespaced.hpp
    │   └── namespaced.cpp
    └── rename/
        ├── renamed_header.h           — header with wrong guard name
        └── ...
```

## Fixture Design

Each fixture is a minimal but realistic C/C++ file:

- **empty_header.h** — completely empty, for header guard creation
- **guarded_header.h** — has `#ifndef GUARDED_HEADER_H\n#define GUARDED_HEADER_H\n...#endif`, for amend/re-detection
- **class_with_members.hpp** — class with `int x; std::string name; bool active;` etc.
- **class_with_methods.hpp** — class with declared methods (some defined inline, some not)
- **function_decls.hpp / function_defs.cpp** — matching header/source pair for definition/declaration tests
- **template_class.hpp** — `template<typename T> class Foo { ... }` for template handling
- **namespaced.hpp / namespaced.cpp** — code inside `namespace X { }` blocks

## Test Runner

```bash
# All tests
make test

# Or directly:
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/"

# Unit only
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/unit/"

# E2E (requires clangd)
E2E=1 nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/e2e/"
```

## Dependencies

- **plenary.nvim** — test framework (dev dependency only)
- **clangd** — e2e smoke tests only, CI can skip these
