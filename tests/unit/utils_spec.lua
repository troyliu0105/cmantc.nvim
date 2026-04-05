local utils = require('cmantic.utils')
local config = require('cmantic.config')
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
    it('returns false for range with nil start field', function()
      assert.is_false(utils.contains_exclusive({ start = nil, ['end'] = { line = 1, character = 0 } }, { line = 0, character = 0 }))
    end)
    it('handles single-line range correctly', function()
      local single_line_range = {
        start = { line = 1, character = 5 },
        ['end'] = { line = 1, character = 10 },
      }
      assert.is_true(utils.contains_exclusive(single_line_range, { line = 1, character = 7 }))
      assert.is_false(utils.contains_exclusive(single_line_range, { line = 1, character = 5 }))
      assert.is_false(utils.contains_exclusive(single_line_range, { line = 1, character = 10 }))
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
    it('returns true when both are nil', function()
      assert.is_true(utils.range_equal(nil, nil))
    end)
    it('returns false when one is nil', function()
      assert.is_false(utils.range_equal({ start = { line = 0, character = 0 }, ['end'] = { line = 1, character = 5 } }, nil))
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
    it('returns false for equal positions', function()
      assert.is_false(utils.position_before({ line = 1, character = 5 }, { line = 1, character = 5 }))
    end)
    it('returns false when both are nil', function()
      assert.is_false(utils.position_before(nil, nil))
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
    it('returns true when both are nil', function()
      assert.is_true(utils.arrays_equal(nil, nil))
    end)
    it('returns false when one is nil and other is not', function()
      assert.is_false(utils.arrays_equal(nil, { 1 }))
      assert.is_false(utils.arrays_equal({ 1 }, nil))
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
    it('returns false for nil a', function()
      assert.is_false(utils.sort_by_range(nil, { range = { start = { line = 1, character = 0 } } }))
    end)
    it('returns false for nil b', function()
      assert.is_false(utils.sort_by_range({ range = { start = { line = 1, character = 0 } } }, nil))
    end)
  end)

  describe('notify', function()
    local original_notify
    local original_alert_level
    local captured

    before_each(function()
      original_notify = vim.notify
      original_alert_level = config.values.alert_level
      captured = nil
      vim.notify = function(msg, level)
        captured = { msg = msg, level = level }
      end
      config.values.alert_level = 'warn'
    end)

    after_each(function()
      vim.notify = original_notify
      config.values.alert_level = original_alert_level
    end)

    it('does not call vim.notify for info when alert_level is warn', function()
      utils.notify('test', 'info')
      assert.is_nil(captured)
    end)

    it('calls vim.notify for error when alert_level is warn', function()
      utils.notify('test', 'error')
      assert.is_not_nil(captured)
      eq('[C-mantic] test', captured.msg)
      eq(vim.log.levels.ERROR, captured.level)
    end)

    it('calls vim.notify for warn level when alert_level is warn', function()
      utils.notify('test', 'warn')
      assert.is_not_nil(captured)
      eq('[C-mantic] test', captured.msg)
      eq(vim.log.levels.WARN, captured.level)
    end)

    it('calls vim.notify for error level when alert_level is error', function()
      config.values.alert_level = 'error'
      utils.notify('test', 'error')
      assert.is_not_nil(captured)
      eq('[C-mantic] test', captured.msg)
      eq(vim.log.levels.ERROR, captured.level)
    end)

    it('defaults to info level when level is nil', function()
      config.values.alert_level = 'info'
      utils.notify('test')
      assert.is_not_nil(captured)
      eq('[C-mantic] test', captured.msg)
      eq(vim.log.levels.INFO, captured.level)
    end)
  end)

  describe('end_of_line', function()
    it('should return \\n for unix fileformat', function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'hello' })
      vim.bo[bufnr].fileformat = 'unix'
      eq('\n', utils.end_of_line(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should return \\r\\n for dos fileformat', function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'hello' })
      vim.bo[bufnr].fileformat = 'dos'
      eq('\r\n', utils.end_of_line(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('indentation', function()
    it('should return spaces when expandtab is true', function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'hello' })
      vim.bo[bufnr].expandtab = true
      vim.bo[bufnr].shiftwidth = 4
      eq('    ', utils.indentation(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should return tab character when expandtab is false', function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'hello' })
      vim.bo[bufnr].expandtab = false
      eq('\t', utils.indentation(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)

    it('should use shiftwidth when it is positive', function()
      local bufnr = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'hello' })
      vim.bo[bufnr].expandtab = true
      vim.bo[bufnr].shiftwidth = 2
      eq('  ', utils.indentation(bufnr))
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end)
  end)

  describe('file_extension', function()
    it('should return extension without dot for "file.lua"', function()
      eq('lua', utils.file_extension('file.lua'))
    end)

    it('should return empty for no extension', function()
      eq('', utils.file_extension('file'))
    end)

    it('should handle multi-dot "file.test.cpp"', function()
      eq('cpp', utils.file_extension('file.test.cpp'))
    end)

    it('should handle hidden files ".gitignore"', function()
      -- vim treats dotfiles with no additional dot as having no extension
      eq('', utils.file_extension('.gitignore'))
    end)
  end)

  describe('file_name_no_ext', function()
    it('should return filename without extension', function()
      eq('file', utils.file_name_no_ext('file.cpp'))
    end)

    it('should handle full path "/path/to/file.cpp"', function()
      eq('file', utils.file_name_no_ext('/path/to/file.cpp'))
    end)

    it('should handle no extension', function()
      eq('file', utils.file_name_no_ext('file'))
    end)
  end)
end)
