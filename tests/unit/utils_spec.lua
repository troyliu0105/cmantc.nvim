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

  describe('notify', function()
    local original_config
    local original_notify

    before_each(function()
      original_config = require('cmantic.config').values.alert_level
      original_notify = vim.notify
    end)

    after_each(function()
      require('cmantic.config').values.alert_level = original_config
      vim.notify = original_notify
    end)

    it('does not call vim.notify for info when alert_level is warn', function()
      local called = false
      local call_msg = nil
      vim.notify = function(msg, level)
        called = true
        call_msg = msg
      end
      
      require('cmantic.config').values.alert_level = 'warn'
      utils.notify('test', 'info')
      
      assert.is_false(called)
      eq(nil, call_msg)
    end)

    it('calls vim.notify for error when alert_level is warn', function()
      local called = false
      local call_msg = nil
      local call_level = nil
      vim.notify = function(msg, level)
        called = true
        call_msg = msg
        call_level = level
      end
      
      require('cmantic.config').values.alert_level = 'warn'
      utils.notify('test', 'error')
      
      assert.is_true(called)
      eq('[C-mantic] test', call_msg)
    end)
  end)
end)
