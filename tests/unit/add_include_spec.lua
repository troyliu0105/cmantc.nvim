local add_include = require('cmantic.commands.add_include')
local helpers = require('tests.helpers')
local utils = require('cmantic.utils')
local eq = assert.are.same

local original_input
local original_notify
local notify_log

local function mock_input(return_value)
  original_input = vim.ui.input
  vim.ui.input = function(opts, cb)
    cb(return_value)
  end
end

local function mock_notify()
  original_notify = utils.notify
  notify_log = {}
  utils.notify = function(msg, level)
    table.insert(notify_log, { msg = msg, level = level })
  end
end

local function restore_mocks()
  if original_input then
    vim.ui.input = original_input
    original_input = nil
  end
  if original_notify then
    utils.notify = original_notify
    original_notify = nil
  end
  notify_log = nil
end

local function get_buf_lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

describe('add_include', function()
  after_each(function()
    restore_mocks()
  end)

  describe('execute — prompting', function()
    it('should prompt user for include path via vim.ui.input', function()
      local prompted = false
      local prompt_text = nil
      original_input = vim.ui.input
      vim.ui.input = function(opts, cb)
        prompted = true
        prompt_text = opts.prompt
        cb('vector')
      end
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <iostream>', 'int main() {}' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      assert.is_true(prompted)
      eq('Include path: ', prompt_text)

      restore_mocks()
    end)

    it('should do nothing when user cancels input (returns nil)', function()
      mock_input(nil)
      mock_notify()

      local lines = { 'int main() {}' }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      eq(lines, get_buf_lines(bufnr))
      eq(0, #notify_log)
    end)

    it('should do nothing when user enters empty string', function()
      mock_input('')
      mock_notify()

      local lines = { 'int main() {}' }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      eq(lines, get_buf_lines(bufnr))
      eq(0, #notify_log)
    end)

    it('should do nothing when user enters only whitespace', function()
      mock_input('   ')
      mock_notify()

      local lines = { 'int main() {}' }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      eq(lines, get_buf_lines(bufnr))
      eq(0, #notify_log)
    end)
  end)

  describe('execute — system vs project include detection', function()
    it('should detect angle bracket path as system include', function()
      mock_input('<vector>')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <iostream>', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      local content = table.concat(lines, '\n')
      assert.is_not_nil(content:find('#include <vector>'))
    end)

    it('should detect quoted path as project include', function()
      mock_input('"myheader.h"')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <iostream>', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      local content = table.concat(lines, '\n')
      assert.is_not_nil(content:find('#include "myheader.h"'))
    end)

    it('should detect known C++ standard library header as system include', function()
      mock_input('vector')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <iostream>', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      local content = table.concat(lines, '\n')
      assert.is_not_nil(content:find('#include <vector>'))
    end)

    it('should detect known C standard header as system include', function()
      mock_input('stdio.h')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <iostream>', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      local content = table.concat(lines, '\n')
      assert.is_not_nil(content:find('#include <stdio.h>'))
    end)

    it('should treat unknown path without delimiters as project include', function()
      mock_input('my_utils.h')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <iostream>', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      local content = table.concat(lines, '\n')
      assert.is_not_nil(content:find('#include "my_utils.h"'))
    end)

    it('should treat path with separators as project include (sys/ lookup unreachable — known bug)', function()
      mock_input('sys/types.h')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include "mylib.h"', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      local content = table.concat(lines, '\n')
      assert.is_not_nil(content:find('#include "sys/types.h"'))
    end)
  end)

  describe('execute — duplicate detection', function()
    it('should warn when file is already included (exact match)', function()
      mock_input('vector')
      mock_notify()

      local lines = {
        '#include <vector>',
        '',
        'int main() {}',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local result = get_buf_lines(bufnr)
      eq(3, #result)
      eq('#include <vector>', result[1])

      eq(1, #notify_log)
      assert.is_not_nil(notify_log[1].msg:find('already included'))
      eq('warn', notify_log[1].level)
    end)

    it('should warn when file is already included (with different delimiters)', function()
      mock_input('<string>')
      mock_notify()

      local lines = {
        '#include <string>',
        '',
        'int main() {}',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local result = get_buf_lines(bufnr)
      eq(3, #result)
      eq('#include <string>', result[1])

      eq(1, #notify_log)
      assert.is_not_nil(notify_log[1].msg:find('already included'))
    end)

    it('should warn when file already included with quotes', function()
      mock_input('"config.h"')
      mock_notify()

      local lines = {
        '#include "config.h"',
        '',
        'int main() {}',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local result = get_buf_lines(bufnr)
      eq(3, #result)
      eq(1, #notify_log)
      assert.is_not_nil(notify_log[1].msg:find('already included'))
    end)
  end)

  describe('execute — insertion', function()
    it('should insert #include with correct delimiters for system header', function()
      mock_input('iostream')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <vector>', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      eq('#include <vector>', lines[1])
      eq('#include <iostream>', lines[2])
      eq('int x;', lines[3])
    end)

    it('should insert #include with correct delimiters for project header', function()
      mock_input('mylib.h')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include "other.h"', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      eq('#include "other.h"', lines[1])
      eq('#include "mylib.h"', lines[2])
      eq('int x;', lines[3])
    end)

    it('should handle include path with trailing whitespace', function()
      mock_input('map  ')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <vector>', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      eq('#include <map>', lines[2])
    end)

    it('should notify info after successful insertion', function()
      mock_input('map')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <vector>', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      eq(1, #notify_log)
      assert.is_not_nil(notify_log[1].msg:find('Added'))
      assert.is_not_nil(notify_log[1].msg:find('#include <map>'))
      eq('info', notify_log[1].level)
    end)

    it('should preserve existing delimiters in input', function()
      mock_input('<sys/types.h>')
      mock_notify()

      local bufnr = helpers.create_buffer({ '#include <iostream>', 'int x;' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local lines = get_buf_lines(bufnr)
      local found = false
      for _, line in ipairs(lines) do
        if line == '#include <sys/types.h>' then found = true end
      end
      assert.is_true(found)
    end)
  end)

  describe('execute — edge cases', function()
    it('should handle buffer with existing includes', function()
      mock_input('iostream')
      mock_notify()

      local lines = {
        '#include <vector>',
        '',
        'int main() {}',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local result = get_buf_lines(bufnr)
      eq(4, #result)
      local found_vector = false
      local found_iostream = false
      for _, line in ipairs(result) do
        if line == '#include <vector>' then found_vector = true end
        if line == '#include <iostream>' then found_iostream = true end
      end
      assert.is_true(found_vector)
      assert.is_true(found_iostream)
    end)

    it('should insert system include after last system include', function()
      mock_input('map')
      mock_notify()

      local lines = {
        '#include <string>',
        '#include "mylib.h"',
        '',
        'int main() {}',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local result = get_buf_lines(bufnr)
      eq(5, #result)
      eq('#include <string>', result[1])
      eq('#include <map>', result[2])
      eq('#include "mylib.h"', result[3])
    end)

    it('should insert project include after last project include', function()
      mock_input('other.h')
      mock_notify()

      local lines = {
        '#include <string>',
        '#include "mylib.h"',
        '',
        'int main() {}',
      }
      local bufnr = helpers.create_buffer(lines, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      add_include.execute()

      local result = get_buf_lines(bufnr)
      eq(5, #result)
      eq('#include <string>', result[1])
      eq('#include "mylib.h"', result[2])
      eq('#include "other.h"', result[3])
    end)

    it('should detect various C++ standard headers as system includes', function()
      local system_headers = { 'algorithm', 'memory', 'optional', 'string_view', 'thread' }
      for _, header in ipairs(system_headers) do
        mock_input(header)
        mock_notify()

        local bufnr = helpers.create_buffer({ '#include <iostream>', 'int x;' }, 'cpp')
        vim.api.nvim_set_current_buf(bufnr)

        add_include.execute()

        local lines = get_buf_lines(bufnr)
        local expected = '#include <' .. header .. '>'
        local found = false
        for _, line in ipairs(lines) do
          if line == expected then found = true end
        end
        assert.is_true(found, 'expected ' .. expected .. ' to be in buffer')

        restore_mocks()
      end
    end)

    it('should handle empty buffer gracefully', function()
      mock_input('vector')
      mock_notify()

      local bufnr = helpers.create_buffer({ '' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      local ok = pcall(add_include.execute)
      assert.is_true(ok)

      local lines = get_buf_lines(bufnr)
      local found = false
      for _, line in ipairs(lines) do
        if line == '#include <vector>' then found = true end
      end
      assert.is_true(found)
    end)

    it('should handle buffer with no includes gracefully', function()
      mock_input('vector')
      mock_notify()

      local bufnr = helpers.create_buffer({ '// comment', 'int main() {}' }, 'cpp')
      vim.api.nvim_set_current_buf(bufnr)

      local ok = pcall(add_include.execute)
      assert.is_true(ok)

      local lines = get_buf_lines(bufnr)
      local found = false
      for _, line in ipairs(lines) do
        if line == '#include <vector>' then found = true end
      end
      assert.is_true(found)
    end)
  end)
end)
