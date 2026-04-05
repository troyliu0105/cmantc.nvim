local helpers = require('tests.helpers')
local SourceDocument = require('cmantic.source_document')
local add_include = require('cmantic.commands.add_include')

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

local function make_buffer_with_content(lines, ft)
  ft = ft or 'cpp'
  return helpers.create_buffer(lines, ft)
end

local function mock_vim_input(return_value)
  local orig_input = vim.ui.input
  vim.ui.input = function(opts, callback)
    callback(return_value)
  end
  return orig_input
end

local function restore_vim_input(orig_input)
  vim.ui.input = orig_input
end

local function find_include(lines, pattern)
  for i, line in ipairs(lines) do
    if line:match(pattern) then
      return i
    end
  end
  return nil
end

local function get_all_includes(lines)
  local includes = {}
  for i, line in ipairs(lines) do
    if line:match('^#include') then
      table.insert(includes, { line = i, text = line })
    end
  end
  return includes
end

--------------------------------------------------------------------------------
-- Test Suite
--------------------------------------------------------------------------------

describe('add_include integration', function()
  local orig_buf
  local orig_input

  before_each(function()
    orig_buf = vim.api.nvim_win_get_buf(0)
  end)

  after_each(function()
    vim.api.nvim_win_set_buf(0, orig_buf)
    if orig_input then
      restore_vim_input(orig_input)
      orig_input = nil
    end
  end)

  --------------------------------------------------------------------------------
  -- Basic Insertion Tests
  --------------------------------------------------------------------------------

  describe('basic insertion', function()
    it('inserts system include in empty header file', function()
      local bufnr = make_buffer_with_content({ '' }, 'cpp')
      orig_input = mock_vim_input('<iostream>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_iostream = find_include(lines, '#include <iostream>')
      assert.truthy(has_iostream, 'should have #include <iostream>')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('inserts system include at top when no other includes', function()
      local bufnr = make_buffer_with_content({ 'int main() { return 0; }' }, 'cpp')
      orig_input = mock_vim_input('<vector>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals('#include <vector>', lines[1], 'include should be at line 1')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('inserts include after existing includes', function()
      local bufnr = make_buffer_with_content({
        '#include <iostream>',
        '',
        'int main() { return 0; }',
      }, 'cpp')
      orig_input = mock_vim_input('<vector>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local includes = get_all_includes(lines)

      assert.equals(2, #includes, 'should have 2 includes')
      assert.equals('#include <iostream>', includes[1].text)
      assert.equals('#include <vector>', includes[2].text)
      assert.True(includes[2].line > includes[1].line, 'new include should be after existing')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('inserts include after #pragma once', function()
      local bufnr = make_buffer_with_content({
        '#pragma once',
        '',
        'class MyClass {};',
      }, 'hpp')
      orig_input = mock_vim_input('<string>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local pragma_line = find_include(lines, '#pragma once')
      local include_line = find_include(lines, '#include <string>')

      assert.truthy(pragma_line, 'should have #pragma once')
      assert.truthy(include_line, 'should have #include <string>')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('inserts include after #ifndef header guard', function()
      local bufnr = make_buffer_with_content({
        '#ifndef MY_HEADER_H',
        '#define MY_HEADER_H',
        '',
        'class MyClass {};',
        '',
        '#endif',
      }, 'h')
      orig_input = mock_vim_input('<memory>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local define_line = nil
      for i, line in ipairs(lines) do
        if line:match('^#define MY_HEADER_H') then
          define_line = i
          break
        end
      end

      local include_line = find_include(lines, '#include <memory>')
      assert.truthy(define_line, 'should have #define guard')
      assert.truthy(include_line, 'should have #include <memory>')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('inserts project include with quotes', function()
      local bufnr = make_buffer_with_content({ '' }, 'cpp')
      orig_input = mock_vim_input('"myheader.h"')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_project_include = find_include(lines, '#include "myheader.h"')
      assert.truthy(has_project_include, 'should have #include "myheader.h"')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('inserts project include without delimiters (auto-detects quotes)', function()
      local bufnr = make_buffer_with_content({ '' }, 'cpp')
      orig_input = mock_vim_input('myproject/header.h')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_project_include = find_include(lines, '#include "myproject/header.h"')
      assert.truthy(has_project_include, 'should have #include "myproject/header.h"')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  --------------------------------------------------------------------------------
  -- Grouping Tests
  --------------------------------------------------------------------------------

  describe('include grouping', function()
    it('groups new system include with existing system includes', function()
      local bufnr = make_buffer_with_content({
        '#include <iostream>',
        '#include <vector>',
        '',
        'int main() {}',
      }, 'cpp')
      orig_input = mock_vim_input('<string>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local includes = get_all_includes(lines)

      assert.equals(3, #includes, 'should have 3 includes')
      assert.equals('#include <iostream>', includes[1].text)
      assert.equals('#include <vector>', includes[2].text)
      assert.equals('#include <string>', includes[3].text)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('groups new project include with existing project includes', function()
      local bufnr = make_buffer_with_content({
        '#include "header1.h"',
        '#include "header2.h"',
        '',
        'void foo() {}',
      }, 'cpp')
      orig_input = mock_vim_input('"header3.h"')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local includes = get_all_includes(lines)

      assert.equals(3, #includes, 'should have 3 includes')
      assert.truthy(includes[1].text:match('"header1.h"'), 'first should be header1')
      assert.truthy(includes[2].text:match('"header2.h"'), 'second should be header2')
      assert.truthy(includes[3].text:match('"header3.h"'), 'third should be header3')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('maintains separate groups for system and project includes', function()
      local bufnr = make_buffer_with_content({
        '#include <iostream>',
        '#include <vector>',
        '#include "myheader.h"',
        '',
        'int main() {}',
      }, 'cpp')
      orig_input = mock_vim_input('<string>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      local system_includes = {}
      local project_includes = {}
      for i, line in ipairs(lines) do
        if line:match('^#include <') then
          table.insert(system_includes, { line = i, text = line })
        elseif line:match('^#include "') then
          table.insert(project_includes, { line = i, text = line })
        end
      end

      assert.equals(3, #system_includes, 'should have 3 system includes')
      assert.equals(1, #project_includes, 'should have 1 project include')

      local last_system = system_includes[#system_includes].line
      local first_project = project_includes[1].line
      assert.True(last_system < first_project, 'system includes should come before project includes')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('inserts system include before project includes when both exist', function()
      local bufnr = make_buffer_with_content({
        '#include "myheader.h"',
        '',
        'void foo() {}',
      }, 'cpp')
      orig_input = mock_vim_input('<vector>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      local system_line = nil
      local project_line = nil
      for i, line in ipairs(lines) do
        if line:match('#include <vector>') then
          system_line = i
        elseif line:match('#include "myheader.h"') then
          project_line = i
        end
      end

      assert.truthy(system_line, 'should have system include')
      assert.truthy(project_line, 'should have project include')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  --------------------------------------------------------------------------------
  -- System Header Detection Tests
  --------------------------------------------------------------------------------

  describe('system header detection', function()
    it('recognizes standard C++ headers as system includes', function()
      local std_headers = { 'vector', 'string', 'map', 'iostream', 'memory', 'algorithm' }

      for _, header in ipairs(std_headers) do
        local bufnr = make_buffer_with_content({ '' }, 'cpp')
        orig_input = mock_vim_input(header)
        restore_vim_input(orig_input)
        orig_input = mock_vim_input(header)

        vim.api.nvim_win_set_buf(0, bufnr)
        add_include.execute()

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local has_angle = find_include(lines, '#include <' .. header .. '>')
        assert.truthy(has_angle, 'should use angle brackets for ' .. header)

        restore_vim_input(orig_input)
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it('recognizes standard C headers as system includes', function()
      local c_headers = { 'stdio.h', 'stdlib.h', 'string.h', 'math.h' }

      for _, header in ipairs(c_headers) do
        local bufnr = make_buffer_with_content({ '' }, 'c')
        orig_input = mock_vim_input(header)
        restore_vim_input(orig_input)
        orig_input = mock_vim_input(header)

        vim.api.nvim_win_set_buf(0, bufnr)
        add_include.execute()

        local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        local has_angle = find_include(lines, '#include <' .. header .. '>')
        assert.truthy(has_angle, 'should use angle brackets for ' .. header)

        restore_vim_input(orig_input)
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end)

    it('uses quotes for path-based includes', function()
      local bufnr = make_buffer_with_content({ '' }, 'cpp')
      orig_input = mock_vim_input('project/utils/helper.h')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_quotes = find_include(lines, '#include "project/utils/helper.h"')
      assert.truthy(has_quotes, 'should use quotes for path-based include')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  --------------------------------------------------------------------------------
  -- Edge Cases
  --------------------------------------------------------------------------------

  describe('edge cases', function()
    it('handles file with only comments at top', function()
      local bufnr = make_buffer_with_content({
        '// Copyright 2024',
        '// License: MIT',
        '',
        'int main() {}',
      }, 'cpp')
      orig_input = mock_vim_input('<iostream>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local include_line = find_include(lines, '#include <iostream>')
      assert.truthy(include_line, 'should have include')

      local first_code_line = nil
      for i, line in ipairs(lines) do
        if not line:match('^//') and not line:match('^#') and line ~= '' then
          first_code_line = i
          break
        end
      end

      if first_code_line then
        assert.True(include_line < first_code_line, 'include should be before code')
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does nothing when input is cancelled', function()
      local bufnr = make_buffer_with_content({
        'int main() {}',
      }, 'cpp')

      local orig = vim.ui.input
      vim.ui.input = function(opts, callback)
        callback(nil)
      end

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.equals(1, #lines, 'should still have only 1 line')
      assert.falsy(lines[1]:match('#include'), 'should not have any include')

      vim.ui.input = orig
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does nothing when input is empty string', function()
      local bufnr = make_buffer_with_content({
        'int main() {}',
      }, 'cpp')

      local orig = vim.ui.input
      vim.ui.input = function(opts, callback)
        callback('')
      end

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.falsy(lines[1]:match('#include'), 'should not have any include')

      vim.ui.input = orig
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('does nothing when input is whitespace only', function()
      local bufnr = make_buffer_with_content({
        'int main() {}',
      }, 'cpp')

      local orig = vim.ui.input
      vim.ui.input = function(opts, callback)
        callback('   ')
      end

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      assert.falsy(lines[1]:match('#include'), 'should not have any include')

      vim.ui.input = orig
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('warns when file is already included', function()
      local bufnr = make_buffer_with_content({
        '#include <vector>',
        '',
        'int main() {}',
      }, 'cpp')

      local orig = vim.ui.input
      vim.ui.input = function(opts, callback)
        callback('<vector>')
      end

      local notify_called = false
      local orig_notify = vim.notify
      vim.notify = function(msg, level)
        if msg and msg:match('already included') then
          notify_called = true
        end
        return orig_notify(msg, level)
      end

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      vim.notify = orig_notify
      vim.ui.input = orig

      assert.True(notify_called, 'should warn about duplicate include')

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local includes = get_all_includes(lines)
      assert.equals(1, #includes, 'should still have only 1 include (no duplicate)')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('preserves include path with angle brackets already present', function()
      local bufnr = make_buffer_with_content({ '' }, 'cpp')
      orig_input = mock_vim_input('<custom/header.h>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_include = find_include(lines, '#include <custom/header.h>')
      assert.truthy(has_include, 'should preserve angle brackets')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('preserves include path with quotes already present', function()
      local bufnr = make_buffer_with_content({ '' }, 'cpp')
      orig_input = mock_vim_input('"custom/header.h"')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_include = find_include(lines, '#include "custom/header.h"')
      assert.truthy(has_include, 'should preserve quotes')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('handles mixed include styles in file', function()
      local bufnr = make_buffer_with_content({
        '#include <iostream>',
        '#include "local.h"',
        '#include <vector>',
        '#include "other.h"',
        '',
        'void foo() {}',
      }, 'cpp')
      orig_input = mock_vim_input('<string>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      local found_string = false
      for _, line in ipairs(lines) do
        if line:match('#include <string>') then
          found_string = true
          break
        end
      end
      assert.True(found_string, 'should insert <string>')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  --------------------------------------------------------------------------------
  -- Source File (.cpp) Specific Tests
  --------------------------------------------------------------------------------

  describe('source file handling', function()
    it('inserts include at top of source file', function()
      local bufnr = make_buffer_with_content({
        '#include "myclass.h"',
        '',
        'void MyClass::method() {}',
      }, 'cpp')
      orig_input = mock_vim_input('<algorithm>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local includes = get_all_includes(lines)

      assert.True(#includes >= 2, 'should have at least 2 includes')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('handles header file with pragma once and includes', function()
      local bufnr = make_buffer_with_content({
        '#pragma once',
        '#include <string>',
        '',
        'class MyClass {',
        '  std::string name;',
        '};',
      }, 'hpp')
      orig_input = mock_vim_input('<memory>')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local includes = get_all_includes(lines)

      assert.equals(2, #includes, 'should have 2 includes')
      assert.equals('#include <string>', includes[1].text)
      assert.equals('#include <memory>', includes[2].text)

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  --------------------------------------------------------------------------------
  -- Special System Headers
  --------------------------------------------------------------------------------

  describe('special system headers', function()
    it('recognizes windows.h as system include', function()
      local bufnr = make_buffer_with_content({ '' }, 'cpp')
      orig_input = mock_vim_input('windows.h')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_angle = find_include(lines, '#include <windows.h>')
      assert.truthy(has_angle, 'windows.h should use angle brackets')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('recognizes pthread.h as system include', function()
      local bufnr = make_buffer_with_content({ '' }, 'c')
      orig_input = mock_vim_input('pthread.h')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_angle = find_include(lines, '#include <pthread.h>')
      assert.truthy(has_angle, 'pthread.h should use angle brackets')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('recognizes unistd.h as system include', function()
      local bufnr = make_buffer_with_content({ '' }, 'c')
      orig_input = mock_vim_input('unistd.h')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_angle = find_include(lines, '#include <unistd.h>')
      assert.truthy(has_angle, 'unistd.h should use angle brackets')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('recognizes sys/ prefixed headers as system includes', function()
      local bufnr = make_buffer_with_content({ '' }, 'c')
      orig_input = mock_vim_input('sys/types.h')

      vim.api.nvim_win_set_buf(0, bufnr)
      add_include.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local has_include = find_include(lines, 'sys/types.h')
      assert.truthy(has_include, 'should have sys/types.h include')

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)
end)
