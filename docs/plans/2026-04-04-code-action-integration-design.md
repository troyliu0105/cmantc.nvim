# Code Action Integration Design

**Date:** 2026-04-04
**Status:** Approved
**Scope:** Fix `<leader>ca` integration + align with vscode-cmantic's 19 code actions

## Problem Statement

cmantic.nvim 的 code action 无法出现在 `<leader>ca`（`vim.lsp.buf.code_action()`）中。用户只能通过 `:Cmantic <command>` 触发。此外，多个 action 缺失、cursor 位置硬编码、空文件不安全等问题导致插件使用体验不佳。

### 6 个已知 Gap

| # | Gap | 影响 |
|---|-----|------|
| 1 | `setup()` 只设了 `vim.b.cmantic_enabled`，没注册到 LSP pipeline | `<leader>ca` 完全看不到 cmantic 动作 |
| 2 | `get_lsp_actions()` 返回 Lua 闭包 + 不存在的 `cmantic.executeAction` command | 即使接入也无法执行 |
| 3 | `show_actions()` 硬编码 cursor 为 `{0,0}` | `:Cmantic` 在非文件顶部位置判断错误 |
| 4 | `get_applicable_actions()` 仅匹配 `name='clangd'` | 用 ccls/cpptools 的用户无法使用 |
| 5 | 缺少 MoveDefinition/AddInclude/SwitchHeaderSource/UpdateSignature 的 action | 19 个命令中只暴露了部分 |
| 6 | `_get_file_level_actions()` 无 `doc.uri` 安全检查 | 空/未保存文件会 crash |

## Approach: vim.ui.select Interception

### Why This Approach

`vim.lsp.buf.code_action()` 的内部流程：

```
1. 获取所有支持 textDocument/codeAction 的 LSP client
2. 向每个 client 发送 buf_request_all
3. 收集所有结果到 results[client_id] 表
4. 聚合后通过 vim.ui.select(kind='codeaction') 展示
```

关键发现：它 **不使用** `vim.lsp.handlers['textDocument/codeAction']`，所以覆盖 handler 无效。

我们选择拦截 `vim.ui.select(kind='codeaction')`，在展示前注入 cmantic 的动作：

```
<leader>ca
  → vim.lsp.buf.code_action()
    → clangd 返回原生 actions
    → on_code_action_results() 聚合
    → vim.ui.select(kind='codeaction')
      → inject.lua 拦截 ← cmantic actions 注入
      → 用户选择
        → cmantic action: 直接调用 Lua callback
        → LSP action: 走原生 apply_action 逻辑
```

### Alternatives Considered

| 方案 | 优点 | 缺点 | 结论 |
|------|------|------|------|
| A: 虚拟 LSP Client (none-ls 模式) | 协议层面完美 | 需管理虚拟 client 生命周期，工程量大 | 过重 |
| B: 仅 vim.ui.select 拦截 | 简单 | 不修复 cursor/空文件/LSP 过滤等 bug | 不够 |
| **C: 混合方案** | 覆盖所有 gap + 保留双入口 | vim.ui.select 依赖 kind 参数 (0.9+ 已支持) | **选用** |

## File Changes

### New Files

| File | Responsibility |
|------|---------------|
| `lua/cmantic/code_action_inject.lua` | vim.ui.select 拦截器，将 cmantic 动作注入 `<leader>ca` 列表 |

### Modified Files

| File | Change |
|------|--------|
| `lua/cmantic/code_action.lua` | 重写：19 个 action 生成器、修复 cursor/LSP 过滤/空文件 bug、Update Signature 跟踪 |
| `lua/cmantic/init.lua` | 接入 inject 模块、修复 show_actions cursor |

### Unchanged Files

| File | Reason |
|------|--------|
| `plugin/cmantic.lua` | `:Cmantic` 命令注册保持不变 |
| `lua/cmantic/commands/*` | 命令执行逻辑不变 |

## Architecture

### Dual-Entry System

```
Entry Point 1: <leader>ca (LSP code action)
  vim.lsp.buf.code_action()
    → clangd returns native actions
    → on_code_action_results() aggregates
    → vim.ui.select(kind='codeaction')
      → code_action_inject.lua intercepts
      → cmantic actions prepended (enabled only)
      → user selects
        → cmantic: execute_by_id(action_id)
        → LSP: original on_choice(choice)

Entry Point 2: :Cmantic (no args)
  → show_actions()
    → get_applicable_actions(bufnr, {cursor position})
    → vim.ui.select(prompt='C-mantic Actions:')
    → user selects → execute_action()

Entry Point 3: :Cmantic <command>
  → commands/init.lua → cmd.execute()
  (unchanged)
```

### Action Data Structure

```lua
---@class CmanticAction
---@field id string              -- unique identifier: 'addDefinitionMatching', 'addHeaderGuard', etc.
---@field title string           -- display title (may include dynamic content: class name, file path)
---@field kind string            -- LSP CodeActionKind: 'refactor.rewrite', 'source', 'quickfix'
---@field is_preferred? boolean  -- preferred action (QuickFix promotion)
---@field execute_fn function    -- execution callback: function()
---@field disabled? boolean      -- whether this action is disabled
---@field disabled_reason? string -- reason for disabled state (diagnostic text)
```

### Action ID Naming

IDs use lowercase camelCase, prefixed by category:
- Refactor: `addDefinitionMatching`, `moveDefinitionToSource`, `generateGetter`, etc.
- Source: `addHeaderGuard`, `amendHeaderGuard`, `addInclude`, `createMatchingSourceFile`
- QuickFix: `updateFunctionDefinition`, `updateFunctionDeclaration`

## Design Details

### 1. code_action_inject.lua

The core bridge that injects cmantic actions into the LSP code action menu.

**Key design decisions:**

1. **`client_id = -1` sentinel**: Marks cmantic actions in the `{action, ctx}` format used by Neovim's internal `on_code_action_results`. Won't conflict with real LSP clients.

2. **Only intercept `kind='codeaction'`**: Doesn't affect other `vim.ui.select` calls (telescope picker, dressing.nvim input, etc.).

3. **cmantic actions prepended**: QuickFix/preferred actions sort to the front, matching vscode-cmantic's lightbulb behavior.

4. **disabled actions excluded**: Neovim's `vim.ui.select` has no native disabled-item support. Disabled actions are omitted from the injected list (their `disabled_reason` is logged at trace level for debugging).

5. **`enable()`/`disable()` lifecycle**: `enable()` called in `setup()`. Function wrapping chain is naturally compatible with other plugins that also wrap `vim.ui.select`.

```lua
-- Pseudocode
function M.enable()
  local original_select = vim.ui.select
  vim.ui.select = function(items, opts, on_choice)
    if opts.kind ~= 'codeaction' then
      return original_select(items, opts, on_choice)
    end
    -- check filetype, build cmantic actions, inject, merge
    -- on choice: if _cmantic_id → execute_by_id, else → original on_choice
  end
end
```

### 2. code_action.lua Rewrite

#### 2a. Bug Fixes

| Bug | Fix |
|-----|-----|
| `show_actions()` cursor hardcoded `{0,0}` | Use `vim.api.nvim_win_get_cursor(0)` when no params |
| `get_applicable_actions()` only clangd | Remove `name='clangd'` filter, accept any attached client |
| `_get_file_level_actions()` crashes on nil uri | Guard `doc.uri` before calling `doc:is_header()` or `header_source.get_matching()` |
| Action closure in command.arguments | New `CmanticAction` struct with `id` + `execute_fn`, no closures in LSP payload |

#### 2b. Complete 19-Action Matrix

**Refactor Actions** (12):

| # | ID | Title | Trigger Condition |
|---|----|-------|-------------------|
| 1 | `addDefinitionMatching` | Add Definition in matching source file / Generate Constructor in matching source file | cursor on function declaration, header file |
| 2 | `addDefinitionInline` | Add Definition in this file / Generate Constructor in this file | cursor on function declaration, header file |
| 3 | `addDeclaration` | Add Declaration in matching header file | cursor on function definition, source file |
| 4 | `addDeclarationInClass` | Add Declaration in class/struct "X" | cursor on function definition inside class |
| 5 | `moveDefinitionToSource` | Move Definition to matching source file | cursor on function definition |
| 6 | `moveDefinitionInOutOfClass` | Move Definition into/out of class body | cursor on member function definition |
| 7 | `generateGetter` | Generate Getter for "X" | cursor on member variable |
| 8 | `generateSetter` | Generate Setter for "X" | cursor on member variable |
| 9 | `generateGetterSetter` | Generate Getter and Setter for "X" | cursor on member variable |
| 10 | `generateEqualityOperators` | Generate Equality Operators for "X" | cursor on class/struct or its member |
| 11 | `generateRelationalOperators` | Generate Relational Operators for "X" | cursor on class/struct or its member |
| 12 | `generateStreamOperator` | Generate Stream Output Operator for "X" | cursor on class/struct or its member |

**Source Actions** (4):

| # | ID | Title | Trigger Condition |
|---|----|-------|-------------------|
| 13 | `addHeaderGuard` | Add Header Guard | header file without guard |
| 14 | `amendHeaderGuard` | Amend Header Guard | header file with guard not matching config style |
| 15 | `addInclude` | Add Include | always available |
| 16 | `createMatchingSourceFile` | Create Matching Source File | header file without matching source |

**QuickFix Actions** (2):

| # | ID | Title | Trigger Condition |
|---|----|-------|-------------------|
| 17 | `updateFunctionDefinition` | Update Function Definition | signature change detected, cursor on declaration |
| 18 | `updateFunctionDeclaration` | Update Function Declaration | signature change detected, cursor on definition |

**Bulk Action** (1):

| # | ID | Title | Trigger Condition |
|---|----|-------|-------------------|
| 19 | `addDefinitionsBulk` | Add Definitions... | header file has declarations without definitions |

#### 2c. Dynamic Title Logic

Several actions have dynamic titles depending on context:

- **Add Definition**: When `csymbol:is_constructor()`, title changes to "Generate Constructor in ..."
- **Move Definition into/out of class**: Title depends on whether definition is inside or outside class:
  - Inside class → "Move Definition below class/struct body"
  - Outside class → "Move Definition into class/struct "X""
- **Add Declaration**: Title includes class name or matching file path
- **Getter/Setter**: Title includes member variable name

#### 2d. Constructor Handling

Current code skips constructors entirely (`if csymbol:is_constructor() then return end`). vscode-cmantic treats constructors as valid targets for Add Definition with a different title.

Fix: Remove the constructor skip. In `_add_definition_actions`, check `is_constructor()` to set title:

```lua
local title_prefix = csymbol:is_constructor() and 'Generate Constructor' or 'Add Definition'
-- title: title_prefix .. ' in matching source file'
-- title: title_prefix .. ' in this file'
```

#### 2e. Update Signature Tracking

Three-layer mechanism matching vscode-cmantic's approach:

**State:**
```lua
M._tracked_function = nil   -- CSymbol at cursor during last action evaluation
M._previous_signature = nil  -- FunctionSignature before change
M._signature_changed = false -- whether a change was detected
```

**Layer 1 — Track (on every `get_applicable_actions`):**
```lua
-- After evaluating all other actions:
local func_symbol = symbol and symbol:is_function() and symbol or nil
M._tracked_function = func_symbol
-- (baseline signature is stored implicitly: next TextChanged will compare against current)
```

**Layer 2 — Detect (on TextChangedI/TextChangedP autocmd):**
```lua
-- Check if edit overlaps _tracked_function.range
-- If yes, re-parse signature, compare with stored baseline
-- If different, set _signature_changed = true, save _previous_signature
```

**Layer 3 — Provide (on next `get_applicable_actions`):**
```lua
if M._signature_changed and csymbol:is_function() then
  if csymbol:is_function_declaration() then
    -- Provide "Update Function Definition" (QuickFix + preferred)
  elseif csymbol:is_function_definition() then
    -- Provide "Update Function Declaration" (QuickFix + preferred)
  end
end
```

**Reset:** After executing an Update Signature action, clear `_signature_changed` and `_previous_signature`.

**Dependencies:** Requires `function_signature.lua` (already exists). Needs a new `FunctionSignature.from_symbol(csymbol, doc)` convenience method.

#### 2f. Action Generation Flow

```lua
function M.get_applicable_actions(bufnr, params)
  local actions = {}
  local position = params.range and params.range.start or M._current_cursor()

  -- Safety: check doc.uri
  local doc = SourceDocument.new(bufnr)
  if not doc.uri then return actions end

  -- Check LSP client (any C/C++ server, not just clangd)
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  local has_lsp = #clients > 0

  -- Get symbol at position
  local symbol = doc:get_symbol_at_position(position)

  if symbol then
    local csymbol = CSymbol.new(symbol, doc)

    -- Refactor: Add Definition (includes Constructor variant)
    if csymbol:is_function() and csymbol:is_function_declaration() then
      M._add_definition_actions(actions, csymbol, doc)
    end

    -- Refactor: Add Declaration
    if csymbol:is_function() and csymbol:is_function_definition() then
      M._add_declaration_actions(actions, csymbol, doc)
    end

    -- Refactor: Move Definition
    if csymbol:is_function() and csymbol:is_function_definition() then
      M._add_move_definition_actions(actions, csymbol, doc)
    end

    -- Refactor: Getters/Setters
    if csymbol:is_member_variable() then
      M._add_getter_setter_actions(actions, csymbol, doc)
    end

    -- Refactor: Operators
    if csymbol:is_class_type() then
      M._add_operator_actions(actions, csymbol, doc)
    end

    -- QuickFix: Update Signature
    M._add_update_signature_actions(actions, csymbol, doc)
  end

  -- Source Actions (always checked)
  M._add_source_actions(actions, doc)

  -- Bulk: Add Definitions
  if doc:is_header() then
    M._add_bulk_definitions_action(actions, doc)
  end

  -- Track current function for signature change detection
  M._track_current_function(symbol)

  return actions
end
```

### 3. init.lua Integration

```lua
local config = require('cmantic.config')
local code_action = require('cmantic.code_action')
local inject = require('cmantic.code_action_inject')

local M = {}

function M.setup(opts)
  config.merge(opts or {})
  code_action.setup()   -- register autocmds, signature tracking
  inject.enable()       -- activate vim.ui.select interception
end

M.code_action = code_action

function M.show_actions()
  code_action.show_actions(0)  -- internally reads current cursor
end

return M
```

### 4. Error Handling & Edge Cases

#### Empty/Unsaved Files

```lua
-- get_applicable_actions early return
if not doc.uri then return {} end
```

#### No LSP Client

```lua
if #clients == 0 then
  -- Only source actions (header guard, etc.) that don't need symbols
  return M._get_source_actions(doc)
end
```

#### LSP Symbols Not Ready

When clangd hasn't indexed yet, `get_symbol_at_position` returns nil. Only file-level source actions are generated. This is correct behavior — no error needed.

#### vim.ui.select Wrapping Chain

Multiple plugins can wrap `vim.ui.select`. The call chain works naturally:

```
our_wrapper → other_wrapper → original_vim.ui.select
```

Our wrapper only cares about `kind == 'codeaction'` and passes everything else through. Other plugins' wrappers work the same way for their specific concerns.

#### Buffer Type Guard

The inject module checks filetype before generating actions:

```lua
local supported_ft = { c = true, cpp = true, objc = true, objcpp = true, cuda = true, proto = true }
if not supported_ft[ft] then
  return original_select(items, opts, on_choice)
end
```

## Implementation Notes

### Performance

- `get_applicable_actions()` is called on every `<leader>ca` invocation. It creates a `SourceDocument` and calls `get_symbol_at_position`, which triggers LSP `documentSymbol` request.
- The inject wrapper adds minimal overhead: one filetype check + one function call that returns early if no actions.
- Update Signature tracking uses `TextChangedI` autocmd which fires on every insert-mode change. The handler should check `_tracked_function.range` overlap early and return if the change is outside range.

### Testing Strategy

1. **Empty header file**: Should show AddHeaderGuard + AddInclude + CreateMatchingSourceFile + AddDefinitionsBulk
2. **Cursor on function declaration**: Should show AddDefinition (2 variants) + source actions
3. **Cursor on member variable**: Should show GenerateGetter + GenerateSetter + GenerateGetterSetter
4. **Cursor on class name**: Should show operator actions + source actions
5. **After editing function signature**: Should show UpdateSignature as QuickFix
6. **`:Cmantic` without args**: Should show same actions at current cursor position
7. **Non-C/C++ file**: inject should pass through without modification
8. **No LSP attached**: Should show only source actions

### Compatibility

- **Neovim 0.10+**: `vim.ui.select` `kind` parameter available since 0.9
- **Neovim 0.12+**: Uses `vim.lsp.get_clients()` (0.10+ API), compatible with `vim.lsp.config()` setup
- **UI providers**: Works with default `vim.ui.select`, dressing.nvim, telescope (when using `vim.lsp.buf.code_action`)
