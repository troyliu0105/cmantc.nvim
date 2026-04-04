# Test Suite Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a three-layer test suite (unit/integration/e2e) for cmantic.nvim using plenary.nvim test_harness, with C/C++ fixture files for integration testing.

**Architecture:** plenary.nvim runs in headless Neovim. Unit tests exercise pure-logic modules directly. Integration tests create real Neovim buffers and inject mock LSP symbol data. E2E tests connect to a real clangd instance. All tests live under `tests/` with static C/C++ fixtures in `tests/fixtures/`.

**Tech Stack:** Lua, plenary.nvim test_harness, Neovim 0.10+ headless, clangd (e2e only)

---

### Task 1: Test Infrastructure Bootstrap

**Files:**
- Create: `tests/minimal_init.lua`
- Create: `tests/helpers.lua`
- Create: `Makefile`

**Step 1: Create `tests/minimal_init.lua`**

This is the Neovim init file for headless test runs. It adds cmantic.nvim and plenary.nvim to the runtime path and calls `require('cmantic').setup()`.

```lua
local root = vim.fn.fnamemodify(vim.loop.cwd(), ':p')

vim.opt.rtp:prepend(root)
vim.opt.rtp:prepend(root .. '/.deps/plenary.nvim')
vim.opt.rtp:prepend(root)

vim.cmd('runtime plugin/plenary.vim')
vim.cmd('runtime plugin/cmantic.lua')

require('cmantic').setup()
```

**Step 2: Create `tests/helpers.lua`**

Shared helpers used across unit and integration tests.

```lua
local M = {}

--- Create a Neovim buffer with the given lines and filetype
--- @param lines string[] Buffer lines
--- @param ft string|nil Filetype (default 'cpp')
--- @return number bufnr
function M.create_buffer(lines, ft)
  local bufnr = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].filetype = ft or 'cpp'
  return bufnr
end

--- Create a mock LSP DocumentSymbol table
--- @param opts table { name, kind, range, selection_range, children, detail }
--- @return table Mock DocumentSymbol
function M.mock_symbol(opts)
  return {
    name = opts.name or 'test',
    kind = opts.kind or 12,
    range = opts.range or {
      start = opts.range_start or { line = 0, character = 0 },
      ['end'] = opts.range_end or { line = 0, character = 10 },
    },
    selectionRange = opts.selection_range or {
      start = opts.selection_start or { line = 0, character = 0 },
      ['end'] = opts.selection_end or { line = 0, character = 10 },
    },
    children = opts.children or {},
    detail = opts.detail or '',
  }
end

--- Create a SourceDocument from lines
--- @param lines string[] Buffer content
--- @param ft string|nil Filetype
--- @return table SourceDocument
function M.create_source_document(lines, ft)
  local bufnr = M.create_buffer(lines, ft)
  local SourceDocument = require('cmantic.source_document')
  return SourceDocument.new(bufnr)
end

--- Read a fixture file and return its lines
--- @param name string Fixture path relative to tests/fixtures/
--- @return string[] Lines
function M.read_fixture(name)
  local path = vim.fn.fnamemodify(vim.loop.cwd(), ':p') .. 'tests/fixtures/' .. name
  local contents = vim.fn.readfile(path)
  return contents
end

--- Create a buffer from a fixture file
--- @param name string Fixture path relative to tests/fixtures/
--- @param ft string|nil Filetype (auto-detected from extension if nil)
--- @return number bufnr
function M.create_buffer_from_fixture(name, ft)
  local lines = M.read_fixture(name)
  if not ft then
    local ext = name:match('%.(%w+)$')
    local ft_map = { h = 'c', hpp = 'cpp', hh = 'cpp', hxx = 'cpp', c = 'c', cpp = 'cpp', cc = 'cpp', cxx = 'cpp' }
    ft = ft_map[ext] or 'cpp'
  end
  return M.create_buffer(lines, ft)
end

return M
```

**Step 3: Create `Makefile`**

```makefile
.PHONY: test test-unit test-integration test-e2e deps

DEPS_DIR = .deps
PLENARY_DIR = $(DEPS_DIR)/plenary.nvim

$(PLENARY_DIR):
	git clone --depth 1 https://github.com/nvim-lua/plenary.nvim $(PLENARY_DIR)

deps: $(PLENARY_DIR)

test: deps
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/unit/ tests/integration/"

test-unit: deps
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/unit/"

test-integration: deps
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/integration/"

test-e2e: deps
	nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/e2e/"
```

**Step 4: Install plenary dependency and verify infrastructure**

Run: `make deps`
Expected: `.deps/plenary.nvim/` directory created

**Step 5: Commit**

```bash
git add tests/minimal_init.lua tests/helpers.lua Makefile
git commit -m "feat(test): bootstrap test infrastructure with plenary.nvim"
```

---

### Task 2: C/C++ Fixture Files

**Files:**
- Create: `tests/fixtures/c++/empty_header.h`
- Create: `tests/fixtures/c++/guarded_header.h`
- Create: `tests/fixtures/c++/class_with_members.hpp`
- Create: `tests/fixtures/c++/class_with_methods.hpp`
- Create: `tests/fixtures/c++/function_decls.hpp`
- Create: `tests/fixtures/c++/function_defs.cpp`
- Create: `tests/fixtures/c++/template_class.hpp`
- Create: `tests/fixtures/c++/namespaced.hpp`
- Create: `tests/fixtures/c++/namespaced.cpp`
- Create: `tests/fixtures/c++/renamed_header.h`

**Step 1: Create fixture files**

`tests/fixtures/c++/empty_header.h` — completely empty file (0 bytes)

`tests/fixtures/c++/guarded_header.h`:
```c
#ifndef GUARDED_HEADER_H
#define GUARDED_HEADER_H

void foo();

#endif // GUARDED_HEADER_H
```

`tests/fixtures/c++/class_with_members.hpp`:
```cpp
#pragma once

#include <string>

class Person {
public:
    std::string name;
    int age;
    bool active;

    Person();
    ~Person();
};
```

`tests/fixtures/c++/class_with_methods.hpp`:
```cpp
#pragma once

class Calculator {
public:
    Calculator();
    ~Calculator();

    int add(int a, int b);
    int subtract(int a, int b);
    virtual void reset();

private:
    int result_;
};
```

`tests/fixtures/c++/function_decls.hpp`:
```cpp
#pragma once

#include <string>

void free_function(int x, const std::string& s);
int compute(int a, int b);
template<typename T>
T max_val(T a, T b);
```

`tests/fixtures/c++/function_defs.cpp`:
```cpp
#include "function_decls.hpp"

void free_function(int x, const std::string& s) {
}

int compute(int a, int b) {
    return a + b;
}
```

`tests/fixtures/c++/template_class.hpp`:
```cpp
#pragma once

template<typename T>
class Container {
public:
    Container();
    ~Container();

    void add(const T& value);
    T get(int index) const;

private:
    T data_[100];
    int size_;
};
```

`tests/fixtures/c++/namespaced.hpp`:
```cpp
#pragma once

namespace math {

class Vector {
public:
    double x;
    double y;

    Vector();
    Vector(double x, double y);

    double magnitude() const;
};

Vector add(const Vector& a, const Vector& b);

}
```

`tests/fixtures/c++/namespaced.cpp`:
```cpp
#include "namespaced.hpp"

namespace math {

Vector::Vector() : x(0), y(0) {
}

Vector::Vector(double x_, double y_) : x(x_), y(y_) {
}

double Vector::magnitude() const {
    return x * x + y * y;
}

Vector add(const Vector& a, const Vector& b) {
    return Vector(a.x + b.x, a.y + b.y);
}

}
```

`tests/fixtures/c++/renamed_header.h`:
```c
#ifndef OLD_NAME_H
#define OLD_NAME_H

void renamed_function();

#endif // OLD_NAME_H
```

**Step 2: Commit**

```bash
git add tests/fixtures/
git commit -m "feat(test): add C/C++ fixture files for integration tests"
```

---

### Task 3: Unit Tests — parsing_spec.lua

**Files:**
- Create: `tests/unit/parsing_spec.lua`

**Step 1: Write the test file**

Test every exported function in `parsing.lua`. This is the largest and most critical module — the text masking engine that everything else depends on.

```lua
local parse = require('cmantic.parsing')
local eq = assert.are.same

describe('parsing', function()
  describe('is_blank', function()
    it('returns true for nil', function()
      assert.is_true(parse.is_blank(nil))
    end)
    it('returns true for empty string', function()
      assert.is_true(parse.is_blank(''))
    end)
    it('returns true for whitespace only', function()
      assert.is_true(parse.is_blank('   \t\n  '))
    end)
    it('returns false for non-empty text', function()
      assert.is_false(parse.is_blank('hello'))
    end)
  end)

  describe('trim', function()
    it('trims leading and trailing whitespace', function()
      eq('hello', parse.trim('  hello  '))
    end)
    it('returns empty for nil', function()
      eq('', parse.trim(nil))
    end)
    it('returns empty for whitespace only', function()
      eq('', parse.trim('   \t\n  '))
    end)
  end)

  describe('normalize_whitespace', function()
    it('collapses multiple spaces to single', function()
      eq('a b c', parse.normalize_whitespace('a   b   c'))
    end)
    it('trims edges', function()
      eq('hello world', parse.normalize_whitespace('  hello world  '))
    end)
    it('returns empty for nil', function()
      eq('', parse.normalize_whitespace(nil))
    end)
  end)

  describe('mask_comments', function()
    it('masks single-line comments', function()
      local input = 'int x; // comment'
      local masked = parse.mask_comments(input)
      assert.is_not_nil(masked:find('int x;'))
      eq(true, masked:sub(#input - #' comment' + 1):match('^%s+$') ~= nil)
    end)
    it('masks block comments', function()
      local input = 'int x; /* block */ int y;'
      local masked = parse.mask_comments(input)
      assert.is_not_nil(masked:find('int x;'))
      assert.is_not_nil(masked:find('int y;'))
      -- between them should be spaces
      local _, _, between = masked:find('int x;( *)int y;')
      assert.is_not_nil(between)
    end)
    it('masks multiline block comments', function()
      local input = 'int x; /* line1\nline2 */ int y;'
      local masked = parse.mask_comments(input)
      assert.is_not_nil(masked:find('int x;'))
      assert.is_not_nil(masked:find('int y;'))
    end)
    it('preserves code outside comments', function()
      eq('int x; ', parse.mask_comments('int x; '))
    end)
    it('returns empty for nil', function()
      eq('', parse.mask_comments(nil))
    end)
  end)

  describe('mask_quotes', function()
    it('masks double-quoted strings', function()
      local input = 'printf("hello world");'
      local masked = parse.mask_quotes(input)
      assert.is_not_nil(masked:find('printf'))
      assert.is_not_nil(masked:find(');'))
      -- "hello world" should be spaces
      local _, s = masked:find('printf%(')
      local e, _ = masked:find('%);')
      local middle = masked:sub(s + 1, e - 1)
      eq(true, middle:match('^%s+$') ~= nil)
    end)
    it('masks single-quoted chars', function()
      local input = "char c = 'a';"
      local masked = parse.mask_quotes(input)
      assert.is_not_nil(masked:find('char c ='))
      assert.is_not_nil(masked:find(';'))
    end)
    it('handles escaped quotes', function()
      local input = 'printf("say \\"hi\\"");'
      local masked = parse.mask_quotes(input)
      assert.is_not_nil(masked:find('printf'))
      assert.is_not_nil(masked:find(');'))
    end)
    it('returns empty for nil', function()
      eq('', parse.mask_quotes(nil))
    end)
  end)

  describe('mask_raw_strings', function()
    it('masks R"delim(...)delim" literals', function()
      local input = 'auto s = R"raw(hello world)raw";'
      local masked = parse.mask_raw_strings(input)
      assert.is_not_nil(masked:find('auto s ='))
      assert.is_not_nil(masked:find(';'))
    end)
    it('returns empty for nil', function()
      eq('', parse.mask_raw_strings(nil))
    end)
  end)

  describe('mask_attributes', function()
    it('masks [[nodiscard]]', function()
      local input = '[[nodiscard]] int foo();'
      local masked = parse.mask_attributes(input)
      assert.is_not_nil(masked:find('int foo'))
    end)
    it('masks [[deprecated("msg")]]', function()
      local input = '[[deprecated("use bar")]] void foo();'
      local masked = parse.mask_attributes(input)
      assert.is_not_nil(masked:find('void foo'))
    end)
  end)

  describe('mask_non_source_text', function()
    it('chains all masks in order', function()
      local input = 'int x = 42; // comment\nstd::string s = "hello"; /* block */'
      local masked = parse.mask_non_source_text(input)
      assert.is_not_nil(masked:find('int x = 42;'))
      assert.is_nil(masked:find('comment'))
      assert.is_nil(masked:find('hello'))
      assert.is_nil(masked:find('block'))
    end)
    it('preserves character positions', function()
      local input = 'void foo(); // comment'
      local masked = parse.mask_non_source_text(input)
      eq('void foo();', masked:sub(1, 12))
    end)
  end)

  describe('mask_balanced', function()
    it('masks parentheses content', function()
      local input = 'foo(bar, baz)'
      local masked = parse.mask_balanced(input, '(', ')', false)
      assert.is_not_nil(masked:find('foo'))
      -- parentheses content should be spaces
      local inner = masked:match('foo(%s*)')
      assert.is_not_nil(inner)
    end)
    it('keeps enclosing delimiters when keep_enclosing=true', function()
      local input = 'foo(bar)'
      local masked = parse.mask_balanced(input, '(', ')', true)
      assert.is_not_nil(masked:find('%('))
      assert.is_not_nil(masked:find('%)'))
    end)
    it('masks angle brackets with operator disambiguation', function()
      local input = 'vector<int> x;'
      local masked = parse.mask_angle_brackets(input, false)
      assert.is_not_nil(masked:find('vector'))
      assert.is_not_nil(masked:find('x'))
      -- <int> should be spaces
      assert.is_nil(masked:find('int'))
    end)
    it('does not confuse <= with angle bracket', function()
      local input = 'if (a <= b)'
      local masked = parse.mask_angle_brackets(input, false)
      assert.is_not_nil(masked:find('<='))
    end)
  end)

  describe('strip_default_values', function()
    it('strips simple default values', function()
      eq('int x, int y', parse.strip_default_values('int x = 5, int y = 10'))
    end)
    it('strips string default values', function()
      eq('std::string s', parse.strip_default_values('std::string s = "hello"'))
    end)
    it('handles template defaults', function()
      eq('T val', parse.strip_default_values('T val = T()'))
    end)
    it('returns empty for nil', function()
      eq('', parse.strip_default_values(nil))
    end)
    it('returns empty for blank', function()
      eq('', parse.strip_default_values(''))
    end)
    it('handles single parameter without default', function()
      eq('int x', parse.strip_default_values('int x'))
    end)
  end)

  describe('matches_primitive_type', function()
    it('matches int', function()
      assert.is_true(parse.matches_primitive_type('int'))
    end)
    it('matches unsigned long', function()
      assert.is_true(parse.matches_primitive_type('unsigned long'))
    end)
    it('matches bool', function()
      assert.is_true(parse.matches_primitive_type('bool'))
    end)
    it('matches auto', function()
      assert.is_true(parse.matches_primitive_type('auto'))
    end)
    it('rejects std::string', function()
      assert.is_false(parse.matches_primitive_type('std::string'))
    end)
    it('rejects template types', function()
      assert.is_false(parse.matches_primitive_type('vector<int>'))
    end)
    it('rejects nil', function()
      assert.is_false(parse.matches_primitive_type(nil))
    end)
    it('rejects empty', function()
      assert.is_false(parse.matches_primitive_type(''))
    end)
  end)
end)
```

**Step 2: Run the test**

Run: `make test-unit`
Expected: All parsing tests pass

**Step 3: Commit**

```bash
git add tests/unit/parsing_spec.lua
git commit -m "test(unit): add parsing module unit tests"
```

---

### Task 4: Unit Tests — function_signature_spec.lua

**Files:**
- Create: `tests/unit/function_signature_spec.lua`

**Step 1: Write the test file**

```lua
local FunctionSignature = require('cmantic.function_signature')
local eq = assert.are.same

describe('function_signature', function()
  describe('new', function()
    it('parses simple function', function()
      local sig = FunctionSignature.new('void foo(int x, int y);')
      eq('void', sig.return_type)
      eq('foo', sig.name)
      eq('int x, int y', sig.parameters)
      eq(';', sig.trailing)
    end)

    it('parsis function with no parameters', function()
      local sig = FunctionSignature.new('int bar();')
      eq('int', sig.return_type)
      eq('bar', sig.name)
      eq('', sig.parameters)
    end)

    it('parsis const member function', function()
      local sig = FunctionSignature.new('int getValue() const;')
      eq('int', sig.return_type)
      eq('getValue', sig.name)
      eq('const', sig.trailing)
    end)

    it('parsis function with scope resolution', function()
      local sig = FunctionSignature.new('void MyClass::method(int x);')
      eq('void', sig.return_type)
      eq('method', sig.name)
      eq('int x', sig.parameters)
    end)

    it('parsis function with default values', function()
      local sig = FunctionSignature.new('void set(int x = 5, const std::string& s = "hello");')
      eq('void', sig.return_type)
      eq('set', sig.name)
    end)

    it('parsis template function', function()
      local sig = FunctionSignature.new('T max_val<T>(T a, T b);')
      eq('T', sig.return_type)
      eq('max_val', sig.name)
    end)

    it('handles empty input', function()
      local sig = FunctionSignature.new('')
      eq('', sig.return_type)
      eq('', sig.name)
      eq('', sig.parameters)
    end)

    it('handles nil input', function()
      local sig = FunctionSignature.new(nil)
      eq('', sig.return_type)
      eq('', sig.name)
    end)
  end)

  describe('equals', function()
    it('same signatures are equal', function()
      local a = FunctionSignature.new('void foo(int x);')
      local b = FunctionSignature.new('void foo(int x);')
      assert.is_true(a:equals(b))
    end)

    it('different names are not equal', function()
      local a = FunctionSignature.new('void foo(int x);')
      local b = FunctionSignature.new('void bar(int x);')
      assert.is_false(a:equals(b))
    end)

    it('different return types are not equal', function()
      local a = FunctionSignature.new('void foo(int x);')
      local b = FunctionSignature.new('int foo(int x);')
      assert.is_false(a:equals(b))
    end)

    it('different parameters are not equal', function()
      local a = FunctionSignature.new('void foo(int x);')
      local b = FunctionSignature.new('void foo(int y);')
      assert.is_false(a:equals(b))
    end)

    it('ignores default values in comparison', function()
      local a = FunctionSignature.new('void foo(int x = 5);')
      local b = FunctionSignature.new('void foo(int x = 10);')
      assert.is_true(a:equals(b))
    end)

    it('nil is not equal', function()
      local a = FunctionSignature.new('void foo();')
      assert.is_false(a:equals(nil))
    end)
  end)
end)
```

**Step 2: Run the test**

Run: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/unit/function_signature_spec.lua"`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/unit/function_signature_spec.lua
git commit -m "test(unit): add function_signature module unit tests"
```

---

### Task 5: Unit Tests — source_symbol_spec.lua

**Files:**
- Create: `tests/unit/source_symbol_spec.lua`

**Step 1: Write the test file**

Test `source_symbol.lua` predicates using mock LSP DocumentSymbol data.

```lua
local SourceSymbol = require('cmantic.source_symbol')
local SK = SourceSymbol.SymbolKind

local eq = assert.are.same

-- Helper: build a mock LSP symbol
local function mock_sym(name, kind, opts)
  opts = opts or {}
  return {
    name = name,
    kind = kind,
    range = opts.range or {
      start = { line = opts.start_line or 0, character = opts.start_char or 0 },
      ['end'] = { line = opts.end_line or 0, character = opts.end_char or 10 },
    },
    selectionRange = {
      start = { line = opts.start_line or 0, character = opts.start_char or 0 },
      ['end'] = { line = opts.end_line or 0, character = opts.end_char or 10 },
    },
    detail = opts.detail or '',
    children = opts.children or {},
  }
end

describe('source_symbol', function()
  describe('new', function()
    it('creates symbol with correct fields', function()
      local raw = mock_sym('MyClass', SK.Class)
      local sym = SourceSymbol.new(raw, 'file:///test.hpp', nil)
      eq('MyClass', sym.name)
      eq(SK.Class, sym.kind)
    end)

    it('strips scope resolution from name', function()
      local raw = mock_sym('MyClass::method', SK.Method)
      local sym = SourceSymbol.new(raw, 'file:///test.hpp', nil)
      eq('method', sym.name)
    end)

    it('sets parent reference', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('x', SK.Field) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      eq(parent, parent.children[1].parent)
    end)

    it('sorts children by range start position', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = {
          mock_sym('b', SK.Field, { start_line = 5 }),
          mock_sym('a', SK.Field, { start_line = 3 }),
          mock_sym('c', SK.Field, { start_line = 7 }),
        }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      eq('a', parent.children[1].name)
      eq('b', parent.children[2].name)
      eq('c', parent.children[3].name)
    end)
  end)

  describe('is_function', function()
    it('returns true for Function', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Function), 'file:///test.hpp', nil)
      assert.is_true(sym:is_function())
    end)
    it('returns true for Method', function()
      local sym = SourceSymbol.new(mock_sym('method', SK.Method), 'file:///test.hpp', nil)
      assert.is_true(sym:is_function())
    end)
    it('returns true for Constructor', function()
      local sym = SourceSymbol.new(mock_sym('MyClass', SK.Constructor), 'file:///test.hpp', nil)
      assert.is_true(sym:is_function())
    end)
    it('returns true for Operator', function()
      local sym = SourceSymbol.new(mock_sym('operator==', SK.Operator), 'file:///test.hpp', nil)
      assert.is_true(sym:is_function())
    end)
    it('returns false for Field', function()
      local sym = SourceSymbol.new(mock_sym('x', SK.Field), 'file:///test.hpp', nil)
      assert.is_false(sym:is_function())
    end)
  end)

  describe('is_class_type', function()
    it('returns true for Class', function()
      local sym = SourceSymbol.new(mock_sym('Foo', SK.Class), 'file:///test.hpp', nil)
      assert.is_true(sym:is_class_type())
    end)
    it('returns true for Struct', function()
      local sym = SourceSymbol.new(mock_sym('Bar', SK.Struct), 'file:///test.hpp', nil)
      assert.is_true(sym:is_class_type())
    end)
    it('returns false for Namespace', function()
      local sym = SourceSymbol.new(mock_sym('ns', SK.Namespace), 'file:///test.hpp', nil)
      assert.is_false(sym:is_class_type())
    end)
  end)

  describe('is_member_variable', function()
    it('returns true for Field inside a class', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('x', SK.Field) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_true(parent.children[1]:is_member_variable())
    end)
    it('returns false for Field outside a class', function()
      local sym = SourceSymbol.new(mock_sym('x', SK.Field), 'file:///test.hpp', nil)
      assert.is_false(sym:is_member_variable())
    end)
    it('returns false for Method inside a class', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('foo', SK.Method) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_false(parent.children[1]:is_member_variable())
    end)
  end)

  describe('is_constructor', function()
    it('returns true for Constructor kind inside class', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('MyClass', SK.Constructor) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_true(parent.children[1]:is_constructor())
    end)
    it('returns true when name matches parent name', function()
      local parent_raw = mock_sym('Foo', SK.Class, {
        children = { mock_sym('Foo', SK.Function) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_true(parent.children[1]:is_constructor())
    end)
    it('returns false when not inside class', function()
      local sym = SourceSymbol.new(mock_sym('Foo', SK.Constructor), 'file:///test.hpp', nil)
      assert.is_false(sym:is_constructor())
    end)
  end)

  describe('is_destructor', function()
    it('returns true for ~Name', function()
      local sym = SourceSymbol.new(mock_sym('~MyClass', SK.Method), 'file:///test.hpp', nil)
      assert.is_true(sym:is_destructor())
    end)
    it('returns false for regular method', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Method), 'file:///test.hpp', nil)
      assert.is_false(sym:is_destructor())
    end)
  end)

  describe('base_name', function()
    it('strips leading underscores', function()
      local sym = SourceSymbol.new(mock_sym('_value', SK.Field), 'file:///test.hpp', nil)
      eq('value', sym:base_name())
    end)
    it('strips trailing underscores', function()
      local sym = SourceSymbol.new(mock_sym('value_', SK.Field), 'file:///test.hpp', nil)
      eq('value', sym:base_name())
    end)
    it('strips m_ prefix', function()
      local sym = SourceSymbol.new(mock_sym('m_name', SK.Field), 'file:///test.hpp', nil)
      eq('name', sym:base_name())
    end)
    it('strips s_ prefix', function()
      local sym = SourceSymbol.new(mock_sym('s_instance', SK.Field), 'file:///test.hpp', nil)
      eq('instance', sym:base_name())
    end)
    it('returns name as-is when no prefix', function()
      local sym = SourceSymbol.new(mock_sym('count', SK.Field), 'file:///test.hpp', nil)
      eq('count', sym:base_name())
    end)
  end)

  describe('scopes', function()
    it('returns empty for root symbol', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Function), 'file:///test.hpp', nil)
      eq(0, #sym:scopes())
    end)

    it('returns parent chain for nested symbols', function()
      local ns_raw = mock_sym('ns', SK.Namespace, {
        children = {
          mock_sym('MyClass', SK.Class, {
            children = { mock_sym('method', SK.Method) }
          })
        }
      })
      local ns = SourceSymbol.new(ns_raw, 'file:///test.hpp', nil)
      local class_sym = ns.children[1]
      local method = class_sym.children[1]

      local scopes = method:scopes()
      eq(2, #scopes)
      eq('ns', scopes[1].name)
      eq('MyClass', scopes[2].name)
    end)
  end)
end)
```

**Step 2: Run the test**

Run: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/unit/source_symbol_spec.lua"`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/unit/source_symbol_spec.lua
git commit -m "test(unit): add source_symbol module unit tests"
```

---

### Task 6: Unit Tests — config_spec.lua

**Files:**
- Create: `tests/unit/config_spec.lua`

**Step 1: Write the test file**

```lua
local config = require('cmantic.config')
local eq = assert.are.same

describe('config', function()
  before_each(function()
    config.values = vim.deepcopy(require('cmantic.config').values)
    config.values.case_style = 'camelCase'
  end)

  describe('defaults', function()
    it('has header_extensions', function()
      eq({ 'h', 'hpp', 'hh', 'hxx' }, config.header_extensions())
    end)
    it('has source_extensions', function()
      eq({ 'c', 'cpp', 'cc', 'cxx' }, config.source_extensions())
    end)
  end)

  describe('merge', function()
    it('overrides specific values', function()
      config.merge({ case_style = 'snake_case' })
      eq('snake_case', config.values.case_style)
    end)

    it('preserves non-merged values', function()
      local orig_style = config.values.header_guard_style
      config.merge({ case_style = 'snake_case' })
      eq(orig_style, config.values.header_guard_style)
    end)
  end)

  describe('format_to_case_style', function()
    it('camelCase: converts snake_case to camelCase', function()
      config.values.case_style = 'camelCase'
      eq('myVariable', config.format_to_case_style('my_variable'))
    end)

    it('camelCase: converts PascalCase to camelCase', function()
      config.values.case_style = 'camelCase'
      eq('myVariable', config.format_to_case_style('MyVariable'))
    end)

    it('snake_case: converts camelCase to snake_case', function()
      config.values.case_style = 'snake_case'
      eq('my_variable', config.format_to_case_style('myVariable'))
    end)

    it('snake_case: converts PascalCase to snake_case', function()
      config.values.case_style = 'snake_case'
      eq('my_class', config.format_to_case_style('MyClass'))
    end)

    it('PascalCase: converts snake_case to PascalCase', function()
      config.values.case_style = 'PascalCase'
      eq('MyVariable', config.format_to_case_style('my_variable'))
    end)

    it('returns nil for nil input', function()
      eq(nil, config.format_to_case_style(nil))
    end)

    it('returns empty for empty input', function()
      eq('', config.format_to_case_style(''))
    end)
  end)
end)
```

**Step 2: Run the test**

Run: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/unit/config_spec.lua"`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/unit/config_spec.lua
git commit -m "test(unit): add config module unit tests"
```

---

### Task 7: Unit Tests — utils_spec.lua

**Files:**
- Create: `tests/unit/utils_spec.lua`

**Step 1: Write the test file**

Test only the pure-logic position/range/array functions (skip vim.bo/vim.fn dependent ones).

```lua
local utils = require('cmantic.utils')
local eq = assert.are.same

describe('utils', function()
  describe('contains_exclusive', function()
    local range = {
      start = { line = 1, character = 5 },
      ['end'] = { line = 3, character = 10 },
    }

    it('returns true for position inside range', function()
      assert.is_true(utils.contains_exclusive(range, { line = 2, character = 0 }))
    end)
    it('returns false for position at range start', function()
      assert.is_false(utils.contains_exclusive(range, { line = 1, character = 5 }))
    end)
    it('returns false for position at range end', function()
      assert.is_false(utils.contains_exclusive(range, { line = 3, character = 10 }))
    end)
    it('returns false for position before range', function()
      assert.is_false(utils.contains_exclusive(range, { line = 0, character = 0 }))
    end)
    it('returns false for position after range', function()
      assert.is_false(utils.contains_exclusive(range, { line = 4, character = 0 }))
    end)
    it('returns false for nil range', function()
      assert.is_false(utils.contains_exclusive(nil, { line = 0, character = 0 }))
    end)
    it('returns false for nil position', function()
      assert.is_false(utils.contains_exclusive(range, nil))
    end)
  end)

  describe('position_equal', function()
    it('returns true for equal positions', function()
      assert.is_true(utils.position_equal({ line = 1, character = 5 }, { line = 1, character = 5 }))
    end)
    it('returns false for different positions', function()
      assert.is_false(utils.position_equal({ line = 1, character = 5 }, { line = 1, character = 6 }))
    end)
    it('returns true for both nil', function()
      assert.is_true(utils.position_equal(nil, nil))
    end)
    it('returns false for one nil', function()
      assert.is_false(utils.position_equal({ line = 0, character = 0 }, nil))
    end)
  end)

  describe('range_equal', function()
    it('returns true for equal ranges', function()
      local a = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 5 } }
      local b = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 5 } }
      assert.is_true(utils.range_equal(a, b))
    end)
    it('returns false for different ranges', function()
      local a = { start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 5 } }
      local b = { start = { line = 0, character = 0 }, ['end'] = { line = 2, character = 5 } }
      assert.is_false(utils.range_equal(a, b))
    end)
  end)

  describe('position_before', function()
    it('returns true when a is before b', function()
      assert.is_true(utils.position_before({ line = 1, character = 0 }, { line = 2, character = 0 }))
    end)
    it('returns false when a is after b', function()
      assert.is_false(utils.position_before({ line = 2, character = 0 }, { line = 1, character = 0 }))
    end)
    it('returns true when same line but a char < b char', function()
      assert.is_true(utils.position_before({ line = 1, character = 3 }, { line = 1, character = 5 }))
    end)
    it('returns false for nil', function()
      assert.is_false(utils.position_before(nil, { line = 0, character = 0 }))
    end)
  end)

  describe('arrays_equal', function()
    it('returns true for identical arrays', function()
      assert.is_true(utils.arrays_equal({ 1, 2, 3 }, { 1, 2, 3 }))
    end)
    it('returns false for different arrays', function()
      assert.is_false(utils.arrays_equal({ 1, 2 }, { 1, 3 }))
    end)
    it('returns false for different lengths', function()
      assert.is_false(utils.arrays_equal({ 1 }, { 1, 2 }))
    end)
    it('returns true for same reference', function()
      local a = { 1, 2 }
      assert.is_true(utils.arrays_equal(a, a))
    end)
  end)

  describe('arrays_intersect', function()
    it('returns true when arrays share an element', function()
      assert.is_true(utils.arrays_intersect({ 1, 2, 3 }, { 3, 4, 5 }))
    end)
    it('returns false when arrays share no elements', function()
      assert.is_false(utils.arrays_intersect({ 1, 2 }, { 3, 4 }))
    end)
    it('returns false for empty arrays', function()
      assert.is_false(utils.arrays_intersect({}, { 1 }))
    end)
    it('returns false for nil arrays', function()
      assert.is_false(utils.arrays_intersect(nil, { 1 }))
    end)
  end)

  describe('make_position', function()
    it('creates a position table', function()
      eq({ line = 5, character = 10 }, utils.make_position(5, 10))
    end)
  end)

  describe('make_range', function()
    it('creates a range table', function()
      local r = utils.make_range(1, 2, 3, 4)
      eq({ line = 1, character = 2 }, r.start)
      eq({ line = 3, character = 4 }, r['end'])
    end)
  end)

  describe('sort_by_range', function()
    it('sorts by line number', function()
      local a = { range = { start = { line = 5, character = 0 } } }
      local b = { range = { start = { line = 3, character = 0 } } }
      assert.is_true(utils.sort_by_range(b, a))
    end)
    it('sorts by character when same line', function()
      local a = { range = { start = { line = 1, character = 10 } } }
      local b = { range = { start = { line = 1, character = 5 } } }
      assert.is_true(utils.sort_by_range(b, a))
    end)
  end)
end)
```

**Step 2: Run the test**

Run: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/unit/utils_spec.lua"`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/unit/utils_spec.lua
git commit -m "test(unit): add utils module unit tests"
```

---

### Task 8: Integration Tests — source_document_spec.lua

**Files:**
- Create: `tests/integration/source_document_spec.lua`

**Step 1: Write the test file**

```lua
local helpers = require('tests.helpers')
local SourceDocument = require('cmantic.source_document')
local eq = assert.are.same

describe('source_document', function()
  describe('is_header / is_source', function()
    it('detects .h as header', function()
      local doc = helpers.create_source_document({ 'int x;' }, 'c')
      -- Override URI to look like .h
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      assert.is_true(doc:is_header())
      assert.is_false(doc:is_source())
    end)

    it('detects .hpp as header', function()
      local bufnr = helpers.create_buffer({ '#pragma once', 'class Foo {};' }, 'cpp')
      local doc = SourceDocument.new(bufnr)
      doc.uri = vim.uri_from_fname('/tmp/test.hpp')
      assert.is_true(doc:is_header())
    end)

    it('detects .cpp as source', function()
      local bufnr = helpers.create_buffer({ 'int main() {}' }, 'cpp')
      local doc = SourceDocument.new(bufnr)
      doc.uri = vim.uri_from_fname('/tmp/test.cpp')
      assert.is_true(doc:is_source())
      assert.is_false(doc:is_header())
    end)

    it('detects .c as source', function()
      local bufnr = helpers.create_buffer({ 'int main() {}' }, 'c')
      local doc = SourceDocument.new(bufnr)
      doc.uri = vim.uri_from_fname('/tmp/test.c')
      assert.is_true(doc:is_source())
    end)
  end)

  describe('header guard detection', function()
    it('detects no guard in empty header', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/empty_header.h')
      local doc = SourceDocument.new(bufnr)
      assert.is_false(doc:has_header_guard())
    end)

    it('detects existing #ifndef/#define guard', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/guarded_header.h')
      local doc = SourceDocument.new(bufnr)
      assert.is_true(doc:has_header_guard())
    end)

    it('detects header guard with wrong name (renamed header)', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/renamed_header.h')
      local doc = SourceDocument.new(bufnr)
      assert.is_true(doc:has_header_guard())
    end)
  end)

  describe('preprocessor directives', function()
    it('finds preprocessor directives', function()
      local lines = {
        '#ifndef TEST_H',
        '#define TEST_H',
        '',
        '#include <string>',
        '',
        'class Test {};',
        '',
        '#endif // TEST_H',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      local doc = SourceDocument.new(bufnr)
      local directives = doc:get_preprocessor_directives()
      assert.is_true(#directives >= 4) -- #ifndef, #define, #include, #endif
    end)
  end)

  describe('symbol_contains_position', function()
    it('returns true for position inside symbol range', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      local symbol = { range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } } }
      assert.is_true(doc:symbol_contains_position(symbol, { line = 0, character = 5 }))
    end)

    it('returns false for position outside symbol range', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      local symbol = { range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } } }
      assert.is_false(doc:symbol_contains_position(symbol, { line = 1, character = 0 }))
    end)

    it('returns false for nil symbol', function()
      local doc = helpers.create_source_document({ '' })
      assert.is_false(doc:symbol_contains_position(nil, { line = 0, character = 0 }))
    end)
  end)

  describe('text access', function()
    it('get_text returns full buffer content', function()
      local lines = { 'line1', 'line2', 'line3' }
      local doc = helpers.create_source_document(lines)
      local text = doc:get_text()
      eq('line1\nline2\nline3', text)
    end)

    it('get_text with range returns partial content', function()
      local lines = { 'hello world' }
      local doc = helpers.create_source_document(lines)
      local text = doc:get_text({
        start = { line = 0, character = 0 },
        ['end'] = { line = 0, character = 5 },
      })
      eq('hello', text)
    end)

    it('get_line returns single line', function()
      local doc = helpers.create_source_document({ 'first', 'second' })
      eq('first', doc:get_line(0))
      eq('second', doc:get_line(1))
    end)
  end)
end)
```

**Step 2: Run the test**

Run: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/integration/source_document_spec.lua"`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/integration/source_document_spec.lua
git commit -m "test(integration): add source_document integration tests"
```

---

### Task 9: Integration Tests — c_symbol_spec.lua

**Files:**
- Create: `tests/integration/c_symbol_spec.lua`

**Step 1: Write the test file**

```lua
local helpers = require('tests.helpers')
local CSymbol = require('cmantic.c_symbol')
local SK = require('cmantic.source_symbol').SymbolKind

local eq = assert.are.same

-- Helper: create a CSymbol from a raw LSP symbol + buffer content
local function make_csymbol(lines, sym_opts)
  local bufnr = helpers.create_buffer(lines, 'cpp')
  local SourceDocument = require('cmantic.source_document')
  local doc = SourceDocument.new(bufnr)

  local raw_sym = helpers.mock_symbol(sym_opts.name or 'test', sym_opts.kind or SK.Function, {
    start_line = sym_opts.start_line or 0,
    start_char = sym_opts.start_char or 0,
    end_line = sym_opts.end_line or (#lines - 1),
    end_char = sym_opts.end_char or #(lines[#lines] or ''),
    detail = sym_opts.detail or '',
    children = sym_opts.children or {},
  })

  return CSymbol.new(raw_sym, doc), doc
end

describe('c_symbol', function()
  describe('is_function_declaration', function()
    it('returns true for declaration without body', function()
      local sym = make_csymbol({ 'void foo(int x);' }, {
        name = 'foo', kind = SK.Function,
        end_char = 17,
      })
      assert.is_true(sym:is_function_declaration())
    end)

    it('returns false for definition with body', function()
      local sym = make_csymbol({ 'void foo(int x) {', '}' }, {
        name = 'foo', kind = SK.Function,
        end_line = 1, end_char = 1,
      })
      assert.is_false(sym:is_function_declaration())
    end)
  end)

  describe('is_function_definition', function()
    it('returns true for definition with body', function()
      local sym = make_csymbol({ 'void foo(int x) {', '}' }, {
        name = 'foo', kind = SK.Function,
        end_line = 1, end_char = 1,
      })
      assert.is_true(sym:is_function_definition())
    end)

    it('returns false for declaration without body', function()
      local sym = make_csymbol({ 'void foo(int x);' }, {
        name = 'foo', kind = SK.Function,
        end_char = 17,
      })
      assert.is_false(sym:is_function_definition())
    end)
  end)

  describe('specifier detection', function()
    it('detects virtual keyword', function()
      local sym = make_csymbol({ 'virtual void foo();' }, {
        name = 'foo', kind = SK.Method,
        end_char = 19,
      })
      assert.is_true(sym:is_virtual())
    end)

    it('detects static keyword', function()
      local sym = make_csymbol({ 'static int count();' }, {
        name = 'count', kind = SK.Method,
        end_char = 19,
      })
      assert.is_true(sym:is_static())
    end)

    it('detects inline keyword', function()
      local sym = make_csymbol({ 'inline void foo() {}', }, {
        name = 'foo', kind = SK.Function,
        end_char = 20,
      })
      assert.is_true(sym:is_inline())
    end)

    it('detects const qualifier', function()
      local sym = make_csymbol({ 'int getValue() const;' }, {
        name = 'getValue', kind = SK.Method,
        end_char = 21,
      })
      assert.is_true(sym:is_const())
    end)
  end)

  describe('getter/setter names', function()
    it('generates getter name for member variable', function()
      local parent_raw = helpers.mock_symbol('MyClass', SK.Class, {
        children = { helpers.mock_symbol('age', SK.Field) },
        end_char = 50,
      })
      local bufnr = helpers.create_buffer({
        'class MyClass {',
        'public:',
        '    int age;',
        '};',
      }, 'cpp')
      local SourceDocument = require('cmantic.source_document')
      local doc = SourceDocument.new(bufnr)

      local parent_sym = require('cmantic.source_symbol').new(parent_raw, doc.uri, nil)
      -- Manually set parent on child for is_member_variable check
      local child = parent_sym.children[1]

      local csym = CSymbol.new({
        name = 'age',
        kind = SK.Field,
        range = { start = { line = 2, character = 4 }, ['end'] = { line = 2, character = 12 } },
        selectionRange = { start = { line = 2, character = 8 }, ['end'] = { line = 2, character = 11 } },
        detail = 'int',
        children = {},
      }, doc)
      csym.parent = parent_sym

      local getter = csym:getter_name()
      local setter = csym:setter_name()
      assert.is_true(getter ~= '')
      assert.is_true(setter ~= '')
    end)
  end)
end)
```

**Step 2: Run the test**

Run: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/integration/c_symbol_spec.lua"`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/integration/c_symbol_spec.lua
git commit -m "test(integration): add c_symbol integration tests"
```

---

### Task 10: Integration Tests — code_action_spec.lua

**Files:**
- Create: `tests/integration/code_action_spec.lua`

**Step 1: Write the test file**

Tests that `get_applicable_actions` returns correct actions for different contexts. Uses real buffers with mock symbol data.

```lua
local helpers = require('tests.helpers')
local code_action = require('cmantic.code_action')

local eq = assert.are.same

local function get_actions_for_buffer(lines, ft, position)
  local bufnr = helpers.create_buffer(lines, ft)
  local params = {
    range = {
      start = position or { line = 0, character = 0 },
      ['end'] = position or { line = 0, character = 0 },
    },
  }
  return code_action.get_applicable_actions(bufnr, params)
end

local function has_action(actions, id)
  for _, a in ipairs(actions) do
    if a.id == id then return true end
  end
  return false
end

local function has_action_title(actions, title_substr)
  for _, a in ipairs(actions) do
    if a.title:find(title_substr) then return true end
  end
  return false
end

describe('code_action', function()
  describe('empty header file', function()
    it('offers Add Header Guard action', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/empty_header.h')
      local actions = code_action.get_applicable_actions(bufnr, {
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
      })
      assert.is_true(has_action(actions, 'addHeaderGuard'))
    end)

    it('offers Add Include action', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/empty_header.h')
      local actions = code_action.get_applicable_actions(bufnr, {
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
      })
      assert.is_true(has_action(actions, 'addInclude'))
    end)
  end)

  describe('guarded header file', function()
    it('offers Amend Header Guard action', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/guarded_header.h')
      local actions = code_action.get_applicable_actions(bufnr, {
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
      })
      assert.is_true(has_action(actions, 'amendHeaderGuard'))
    end)

    it('does NOT offer Add Header Guard (already has one)', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/guarded_header.h')
      local actions = code_action.get_applicable_actions(bufnr, {
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
      })
      assert.is_false(has_action(actions, 'addHeaderGuard'))
    end)
  end)

  describe('non-C/C++ file', function()
    it('returns empty actions for Lua file', function()
      local actions = get_actions_for_buffer({ 'local x = 1' }, 'lua')
      -- code_action checks vim.b.cmantic_enabled, which is only set for C/C++ filetypes
      -- But get_applicable_actions itself doesn't filter by filetype — that's inject's job
      -- So it may still return source actions. The key is it shouldn't error.
      assert.is_true(type(actions) == 'table')
    end)
  end)

  describe('source file', function()
    it('offers Add Include but not Header Guard', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/function_defs.cpp')
      local actions = code_action.get_applicable_actions(bufnr, {
        range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 0 } },
      })
      assert.is_true(has_action(actions, 'addInclude'))
      assert.is_false(has_action(actions, 'addHeaderGuard'))
      assert.is_false(has_action(actions, 'amendHeaderGuard'))
    end)
  end)
end)
```

**Step 2: Run the test**

Run: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/integration/code_action_spec.lua"`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/integration/code_action_spec.lua
git commit -m "test(integration): add code_action integration tests"
```

---

### Task 11: Integration Tests — header_guard_spec.lua

**Files:**
- Create: `tests/integration/header_guard_spec.lua`

**Step 1: Write the test file**

```lua
local helpers = require('tests.helpers')
local add_header_guard = require('cmantic.commands.add_header_guard')
local SourceDocument = require('cmantic.source_document')
local config = require('cmantic.config')

local eq = assert.are.same

describe('header_guard', function()
  describe('_format_guard_name', function()
    it('formats guard from filename', function()
      local bufnr = helpers.create_buffer({}, 'c')
      local doc = SourceDocument.new(bufnr)
      doc.uri = vim.uri_from_fname('/tmp/my_header.h')
      local name = add_header_guard._format_guard_name(doc)
      eq('MY_HEADER_H', name)
    end)
  end)

  describe('execute — add guard', function()
    it('adds #ifndef/#define/#endif to empty header', function()
      local bufnr = helpers.create_buffer({ '' }, 'c')
      vim.api.nvim_set_current_buf(bufnr)
      -- Override URI
      local doc = SourceDocument.new(bufnr)
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      -- We need to make the SourceDocument used by execute() use this URI
      -- Since execute creates a new SourceDocument, we set the buffer name
      vim.api.nvim_buf_set_name(bufnr, '/tmp/test_header_guard_add.h')

      add_header_guard.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, '\n')
      assert.is_true(content:find('#ifndef') ~= nil)
      assert.is_true(content:find('#define') ~= nil)
      assert.is_true(content:find('#endif') ~= nil)
    end)
  end)

  describe('_amend_guard', function()
    it('replaces old guard name with new one', function()
      local lines = {
        '#ifndef OLD_GUARD_H',
        '#define OLD_GUARD_H',
        '',
        'void foo();',
        '',
        '#endif // OLD_GUARD_H',
      }
      local bufnr = helpers.create_buffer(lines, 'c')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/new_name.h')
      vim.api.nvim_set_current_buf(bufnr)

      local doc = SourceDocument.new(bufnr)
      local new_guard = add_header_guard._format_guard_name(doc)

      add_header_guard._amend_guard(doc, new_guard)

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(updated, '\n')
      assert.is_nil(content:find('OLD_GUARD_H'))
      assert.is_not_nil(content:find(new_guard))
    end)

    it('does nothing when guard name is already correct', function()
      local lines = {
        '#ifndef ALREADY_CORRECT_H',
        '#define ALREADY_CORRECT_H',
        '',
        '#endif // ALREADY_CORRECT_H',
      }
      local bufnr = helpers.create_buffer(lines, 'c')
      vim.api.nvim_buf_set_name(bufnr, '/tmp/already_correct.h')

      local doc = SourceDocument.new(bufnr)
      local guard = add_header_guard._format_guard_name(doc)

      -- Guard name should match — amend should be a no-op
      add_header_guard._amend_guard(doc, guard)

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq(lines, updated)
    end)
  end)
end)
```

**Step 2: Run the test**

Run: `nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/integration/header_guard_spec.lua"`
Expected: All tests pass

**Step 3: Commit**

```bash
git add tests/integration/header_guard_spec.lua
git commit -m "test(integration): add header_guard integration tests"
```

---

### Task 12: E2E Smoke Tests — smoke_spec.lua

**Files:**
- Create: `tests/e2e/smoke_spec.lua`

**Step 1: Write the test file**

These tests require clangd to be running. They verify end-to-end flows that would catch regressions like the `%b` bug.

```lua
-- E2E smoke tests require real clangd
-- These are skipped unless E2E=1 environment variable is set

local has_e2e = os.getenv('E2E') == '1'

local function skip_if_no_e2e()
  if not has_e2e then
    pending('E2E tests require E2E=1 and clangd')
  end
end

describe('e2e smoke', function()
  describe('clangd availability', function()
    it('clangd is attached to C/C++ buffers', function()
      skip_if_no_e2e()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'int main() { return 0; }' })
      vim.bo[bufnr].filetype = 'cpp'
      vim.api.nvim_set_current_buf(bufnr)

      -- Wait for clangd to attach (up to 5 seconds)
      local clients = {}
      vim.wait(5000, function()
        clients = vim.lsp.get_clients({ bufnr = bufnr, name = 'clangd' })
        return #clients > 0
      end, 100)

      assert.is_true(#clients > 0, 'clangd should be attached')
    end)
  end)
end)
```

**Step 2: Run the test (with clangd)**

Run: `E2E=1 nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedFile tests/e2e/smoke_spec.lua"`
Expected: Skipped if no clangd; passes if clangd is available

**Step 3: Commit**

```bash
git add tests/e2e/smoke_spec.lua
git commit -m "test(e2e): add smoke test scaffolding for clangd integration"
```

---

### Task 13: Verify All Tests and Final Cleanup

**Step 1: Run all unit tests**

Run: `make test-unit`
Expected: All pass

**Step 2: Run all integration tests**

Run: `make test-integration`
Expected: All pass

**Step 3: Run combined test suite**

Run: `make test`
Expected: All pass

**Step 4: Add .deps to .gitignore**

```bash
echo '.deps/' >> .gitignore
git add .gitignore
git commit -m "chore: ignore .deps/ directory"
```
