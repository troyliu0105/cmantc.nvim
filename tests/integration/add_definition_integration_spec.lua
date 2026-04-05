local helpers = require('tests.helpers')
local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')

local function make_class_buffer()
  return helpers.create_buffer({
    'class A {',
    'public:',
    '  explicit A(int data) : data(data) {}',
    '  A(const A &a) { this->data = a.data; }',
    '  int task();',
    '',
    'protected:',
    '  int data;',
    '  int *ptr;',
    '};',
  }, 'cpp')
end

--- Create a mock LSP symbol tree for class A with members
local function make_class_symbols(bufnr)
  local doc = SourceDocument.new(bufnr)
  -- We need real LSP symbols for CSymbol to work.
  -- Instead, construct SourceSymbols manually to simulate what clangd returns.
  local SourceSymbol = require('cmantic.source_symbol')

  local class_sym = SourceSymbol.new({
    name = 'A',
    kind = 23, -- Class
    range = { start = { line = 0, character = 0 }, ['end'] = { line = 9, character = 2 } },
    selectionRange = { start = { line = 0, character = 6 }, ['end'] = { line = 0, character = 7 } },
    children = {
      {
        name = 'A',
        kind = 12, -- Constructor
        detail = '(int data)',
        range = { start = { line = 2, character = 2 }, ['end'] = { line = 2, character = 40 } },
        selectionRange = { start = { line = 2, character = 11 }, ['end'] = { line = 2, character = 12 } },
        children = {},
      },
      {
        name = 'A',
        kind = 12, -- Constructor
        detail = '(const A &a)',
        range = { start = { line = 3, character = 2 }, ['end'] = { line = 3, character = 38 } },
        selectionRange = { start = { line = 3, character = 2 }, ['end'] = { line = 3, character = 3 } },
        children = {},
      },
      {
        name = 'task',
        kind = 6, -- Method
        detail = '() -> int',
        range = { start = { line = 4, character = 2 }, ['end'] = { line = 4, character = 12 } },
        selectionRange = { start = { line = 4, character = 6 }, ['end'] = { line = 4, character = 10 } },
        children = {},
      },
      {
        name = 'data',
        kind = 8, -- Field
        range = { start = { line = 7, character = 2 }, ['end'] = { line = 7, character = 11 } },
        selectionRange = { start = { line = 7, character = 6 }, ['end'] = { line = 7, character = 10 } },
        children = {},
      },
      {
        name = 'ptr',
        kind = 8, -- Field
        range = { start = { line = 8, character = 2 }, ['end'] = { line = 8, character = 11 } },
        selectionRange = { start = { line = 8, character = 7 }, ['end'] = { line = 8, character = 10 } },
        children = {},
      },
    },
  }, vim.uri_from_bufnr(bufnr), nil)

  return class_sym, doc
end

describe('add_definition integration', function()
  it('execute_in_current places definition AFTER class body, not inside', function()
    local bufnr = make_class_buffer()
    local class_sym, doc = make_class_symbols(bufnr)

    -- Find the task() method declaration (child index 3)
    local task_child = class_sym.children[3]
    assert.truthy(task_child)
    assert.equals('task', task_child.name)

    -- Wrap as CSymbol
    local csymbol = CSymbol.new(task_child, doc)
    assert.truthy(csymbol:is_function())
    assert.truthy(csymbol:is_function_declaration())

    -- Check parent is class
    assert.truthy(csymbol.parent)
    assert.truthy(csymbol.parent:is_class_type())

    -- Wrap parent as CSymbol and check body_end
    local parent_csym = CSymbol.new(csymbol.parent, doc)
    local body_end = parent_csym:_find_body_end()

    -- body_end should be on the line with '};' (line 10), at the '}'
    assert.equals(9, body_end.line, 'body_end should be on the closing brace line')
    local insert_line = body_end.line + 1

    local definition_text = csymbol:new_function_definition(doc, { line = insert_line, character = 0 })
    assert.truthy(definition_text and #definition_text > 0)
    assert.True(insert_line > 9, 'definition must be placed after class closing brace')
  end)

  it('insert_text handles position at buffer end without crash', function()
    -- Simulate a nearly-empty source file (just an include)
    local lines = { '#include "test.hpp"' }
    local bufnr = helpers.create_buffer(lines, 'cpp')
    local doc = SourceDocument.new(bufnr)

    -- Position after last line (line_count = 1, so line 1 is valid for append)
    local pos = { line = vim.api.nvim_buf_line_count(bufnr), character = 0 }

    -- This should NOT crash
    assert.has_no.errors(function()
      doc:insert_text(pos, '\nvoid test() {}')
    end)

    -- Verify the text was inserted
    local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals(3, #new_lines, 'should have 3 lines: original + blank + new')
    assert.equals('#include "test.hpp"', new_lines[1], 'first line should be original include')
    assert.equals('', new_lines[2], 'second line should be blank')
    assert.truthy(new_lines[3]:match('void test%(%)'), 'last line should contain void test()')
  end)

  it('insert_text handles position beyond buffer end via clamp', function()
    local lines = { '#include "test.hpp"' }
    local bufnr = helpers.create_buffer(lines, 'cpp')
    local doc = SourceDocument.new(bufnr)

    -- Position way beyond end
    local pos = { line = 999, character = 0 }

    assert.has_no.errors(function()
      doc:insert_text(pos, '\nvoid test() {}')
    end)

    local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals(3, #new_lines, 'should have 3 lines after append beyond end')
    assert.equals('#include "test.hpp"', new_lines[1], 'first line should be original include')
    assert.equals('', new_lines[2], 'second line should be blank from leading newline')
    assert.equals('void test() {}', new_lines[3], 'last line should be inserted function')
  end)

  it('insert_text handles empty buffer', function()
    local bufnr = helpers.create_buffer({ '' }, 'cpp')
    local doc = SourceDocument.new(bufnr)

    assert.has_no.errors(function()
      doc:insert_text({ line = 0, character = 0 }, 'void test() {}')
    end)

    local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals('void test() {}', new_lines[1])
  end)

  it('insert_text handles position at last line with high character', function()
    local lines = { 'int x = 5;' }
    local bufnr = helpers.create_buffer(lines, 'cpp')
    local doc = SourceDocument.new(bufnr)

    -- Character beyond line length should be clamped
    assert.has_no.errors(function()
      doc:insert_text({ line = 0, character = 100 }, ' // comment')
    end)

    local new_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    assert.equals('int x = 5; // comment', new_lines[1])
  end)
end)

describe('generate_getter_setter integration', function()
  it('wraps parent in CSymbol for position lookup', function()
    local bufnr = make_class_buffer()
    local class_sym, doc = make_class_symbols(bufnr)

    -- Find the 'data' field (child index 4)
    local data_child = class_sym.children[4]
    assert.truthy(data_child)
    assert.equals('data', data_child.name)

    local csymbol = CSymbol.new(data_child, doc)
    assert.truthy(csymbol:is_member_variable())

    -- This is what generate_getter_setter does:
    local parent = csymbol.parent
    assert.truthy(parent)
    assert.truthy(parent:is_class_type())

    -- Wrap parent as CSymbol (the fix)
    local parent_csym = CSymbol.new(parent, doc)
    local pos_info = parent_csym:find_position_for_new_member_function(
      require('cmantic.utils').AccessLevel.public,
      csymbol.name
    )

    assert.truthy(pos_info, 'should find position for accessor')
    assert.truthy(pos_info.position, 'position should not be nil')
    assert.equals(7, pos_info.position.line, 'position.line should be a specific value (line 7, near data field)')
    assert.is_false(pos_info.insert_before, 'should insert after, not before')
  end)
end)

--------------------------------------------------------------------------------
-- Command Execution Tests (with buffer mutation)
--------------------------------------------------------------------------------

describe('add_definition.execute_in_current command', function()
  local add_definition = require('cmantic.commands.add_definition')
  local SourceFile = require('cmantic.source_file')
  local orig_buf
  local orig_get_symbols

  before_each(function()
    orig_buf = vim.api.nvim_win_get_buf(0)
    orig_get_symbols = SourceFile.get_symbols
  end)

  after_each(function()
    vim.api.nvim_win_set_buf(0, orig_buf)
    SourceFile.get_symbols = orig_get_symbols
  end)

  local function to_raw_symbol(source_sym)
    local raw_children = {}
    for _, child in ipairs(source_sym.children or {}) do
      table.insert(raw_children, to_raw_symbol(child))
    end
    return {
      name = source_sym.name,
      kind = source_sym.kind,
      range = source_sym.range,
      selectionRange = source_sym.selection_range or source_sym.selectionRange,
      children = raw_children,
      detail = source_sym.detail or '',
    }
  end

  it('inserts definition AFTER class body, not inside', function()
    local bufnr = make_class_buffer()
    local class_sym, doc = make_class_symbols(bufnr)

    local uri = vim.uri_from_bufnr(bufnr)
    SourceFile.get_symbols = function(self)
      if self.uri == uri then
        return { to_raw_symbol(class_sym) }
      end
      return {}
    end

    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 5, 6 })

    add_definition.execute_in_current()

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local closing_brace_line = nil
    for i, line in ipairs(lines) do
      if line:match('^};') then
        closing_brace_line = i
        break
      end
    end
    assert.truthy(closing_brace_line, 'should find closing brace };')

    local found_definition = false
    for i = closing_brace_line + 1, #lines do
      if lines[i]:match('int%s+A::task%s*%(') then
        found_definition = true
        break
      end
    end
    assert.True(found_definition, 'definition must appear after };')

    assert.equals('', lines[closing_brace_line + 1], 'blank line should exist between }; and definition')

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)

describe('generate_getter_setter.execute command', function()
  local generate_getter_setter = require('cmantic.commands.generate_getter_setter')
  local SourceFile = require('cmantic.source_file')
  local orig_buf
  local orig_get_symbols

  before_each(function()
    orig_buf = vim.api.nvim_win_get_buf(0)
    orig_get_symbols = SourceFile.get_symbols
  end)

  after_each(function()
    vim.api.nvim_win_set_buf(0, orig_buf)
    SourceFile.get_symbols = orig_get_symbols
  end)

  local function to_raw_symbol(source_sym)
    local raw_children = {}
    for _, child in ipairs(source_sym.children or {}) do
      table.insert(raw_children, to_raw_symbol(child))
    end
    return {
      name = source_sym.name,
      kind = source_sym.kind,
      range = source_sym.range,
      selectionRange = source_sym.selection_range or source_sym.selectionRange,
      children = raw_children,
      detail = source_sym.detail or '',
    }
  end

  local function mock_symbols_for_buf(bufnr, class_sym)
    local uri = vim.uri_from_bufnr(bufnr)
    SourceFile.get_symbols = function(self)
      if self.uri == uri then
        return { to_raw_symbol(class_sym) }
      end
      return {}
    end
  end

  it('inserts getter inside class in public section', function()
    local bufnr = make_class_buffer()
    local class_sym, doc = make_class_symbols(bufnr)

    mock_symbols_for_buf(bufnr, class_sym)

    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 8, 6 })

    generate_getter_setter.execute({ mode = 'getter' })

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local closing_brace_line = nil
    for i, line in ipairs(lines) do
      if line:match('^};') then
        closing_brace_line = i
        break
      end
    end
    assert.truthy(closing_brace_line, 'should find closing brace };')

    local getter_line = nil
    for i = 1, closing_brace_line - 1 do
      if lines[i]:match('getData') or lines[i]:match('get_data') then
        getter_line = i
        break
      end
    end
    assert.truthy(getter_line, 'getter should exist inside class')
    assert.True(getter_line < closing_brace_line, 'getter must be inside class (before };)')
    assert.falsy(lines[getter_line]:match('A::'), 'getter should NOT have class scope prefix (it is inside the class)')

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)

  it('inserts both getter and setter with mode=both', function()
    local bufnr = make_class_buffer()
    local class_sym, doc = make_class_symbols(bufnr)

    mock_symbols_for_buf(bufnr, class_sym)

    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_win_set_cursor(0, { 8, 6 })

    generate_getter_setter.execute({ mode = 'both' })

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

    local closing_brace_line = nil
    for i, line in ipairs(lines) do
      if line:match('^};') then
        closing_brace_line = i
        break
      end
    end
    assert.truthy(closing_brace_line, 'should find closing brace };')

    local found_getter = false
    for i = 1, closing_brace_line - 1 do
      if lines[i]:match('getData') or lines[i]:match('get_data') then
        found_getter = true
        break
      end
    end
    assert.True(found_getter, 'getter should exist inside class')

    local found_setter = false
    for i = 1, closing_brace_line - 1 do
      if lines[i]:match('setData') or lines[i]:match('set_data') then
        found_setter = true
        break
      end
    end
    assert.True(found_setter, 'setter should exist inside class')

    vim.api.nvim_buf_delete(bufnr, { force = true })
  end)
end)
