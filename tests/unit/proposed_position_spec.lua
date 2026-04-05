local ProposedPosition = require('cmantic.proposed_position')

local eq = assert.are.same

describe('proposed_position', function()
  describe('new', function()
    it('creates instance with position', function()
      local pos = { line = 5, character = 10 }
      local pp = ProposedPosition.new(pos)
      eq(pos, pp.position)
    end)

    it('defaults options to empty table when not provided', function()
      local pp = ProposedPosition.new({ line = 0, character = 0 })
      eq({}, pp.options)
    end)

    it('stores provided options table', function()
      local opts = { indent = 2, before = true }
      local pp = ProposedPosition.new({ line = 3, character = 0 }, opts)
      eq(opts, pp.options)
    end)

    it('has correct metatable', function()
      local pp = ProposedPosition.new({ line = 0, character = 0 })
      assert.is_true(getmetatable(pp) == ProposedPosition)
    end)
  end)

  describe('line()', function()
    it('returns line number from position', function()
      local pp = ProposedPosition.new({ line = 7, character = 4 })
      eq(7, pp:line())
    end)

    it('returns 0 when position is nil', function()
      local pp = ProposedPosition.new(nil)
      eq(0, pp:line())
    end)

    it('returns 0 for line 0', function()
      local pp = ProposedPosition.new({ line = 0, character = 0 })
      eq(0, pp:line())
    end)
  end)

  describe('character()', function()
    it('returns character number from position', function()
      local pp = ProposedPosition.new({ line = 2, character = 15 })
      eq(15, pp:character())
    end)

    it('returns 0 when position is nil', function()
      local pp = ProposedPosition.new(nil)
      eq(0, pp:character())
    end)

    it('returns 0 for character 0', function()
      local pp = ProposedPosition.new({ line = 5, character = 0 })
      eq(0, pp:character())
    end)
  end)

  describe('to_position()', function()
    it('returns line and character table', function()
      local pp = ProposedPosition.new({ line = 3, character = 8 })
      eq({ line = 3, character = 8 }, pp:to_position())
    end)

    it('returns zeros when position is nil', function()
      local pp = ProposedPosition.new(nil)
      eq({ line = 0, character = 0 }, pp:to_position())
    end)

    it('matches line() and character() values', function()
      local pp = ProposedPosition.new({ line = 12, character = 20 })
      local result = pp:to_position()
      eq(pp:line(), result.line)
      eq(pp:character(), result.character)
    end)
  end)

  describe('options handling', function()
    it('stores relative_to option', function()
      local ref = { line = 1, character = 0 }
      local pp = ProposedPosition.new({ line = 2, character = 0 }, { relative_to = ref })
      eq(ref, pp.options.relative_to)
    end)

    it('stores before boolean option', function()
      local pp = ProposedPosition.new({ line = 0, character = 0 }, { before = true })
      assert.is_true(pp.options.before)
    end)

    it('stores after boolean option', function()
      local pp = ProposedPosition.new({ line = 0, character = 0 }, { after = true })
      assert.is_true(pp.options.after)
    end)

    it('stores next_to boolean option', function()
      local pp = ProposedPosition.new({ line = 0, character = 0 }, { next_to = true })
      assert.is_true(pp.options.next_to)
    end)

    it('stores indent option', function()
      local pp = ProposedPosition.new({ line = 0, character = 0 }, { indent = 4 })
      eq(4, pp.options.indent)
    end)

    it('stores blank_lines_before option', function()
      local pp = ProposedPosition.new({ line = 0, character = 0 }, { blank_lines_before = 2 })
      eq(2, pp.options.blank_lines_before)
    end)

    it('stores blank_lines_after option', function()
      local pp = ProposedPosition.new({ line = 0, character = 0 }, { blank_lines_after = 1 })
      eq(1, pp.options.blank_lines_after)
    end)

    it('stores multiple options simultaneously', function()
      local opts = {
        before = true,
        indent = 2,
        blank_lines_before = 1,
        blank_lines_after = 1,
      }
      local pp = ProposedPosition.new({ line = 5, character = 0 }, opts)
      assert.is_true(pp.options.before)
      eq(2, pp.options.indent)
      eq(1, pp.options.blank_lines_before)
      eq(1, pp.options.blank_lines_after)
    end)
  end)
end)
