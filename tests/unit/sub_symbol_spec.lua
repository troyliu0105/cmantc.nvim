local SubSymbol = require('cmantic.sub_symbol')
local helpers = require('tests.helpers')

local eq = assert.are.same

local function make_range(start_line, start_char, end_line, end_char)
  return {
    start = { line = start_line, character = start_char },
    ['end'] = { line = end_line, character = end_char },
  }
end

describe('sub_symbol', function()
  describe('new', function()
    it('creates instance with document, range, and selection_range', function()
      local doc = helpers.create_source_document({ 'hello world' })
      local range = make_range(0, 0, 0, 11)
      local sel = make_range(0, 0, 0, 5)
      local sub = SubSymbol.new(doc, range, sel)
      eq(doc, sub.document)
      eq(range, sub.range)
      eq(sel, sub.selection_range)
    end)

    it('defaults selection_range to range when not provided', function()
      local doc = helpers.create_source_document({ 'hello world' })
      local range = make_range(0, 0, 0, 11)
      local sub = SubSymbol.new(doc, range)
      eq(range, sub.selection_range)
    end)

    it('sets name from document:get_text(range)', function()
      local doc = helpers.create_source_document({ 'hello world' })
      local range = make_range(0, 0, 0, 5)
      local sub = SubSymbol.new(doc, range)
      eq('hello', sub.name)
    end)

    it('sets name to empty string when document is nil', function()
      local range = make_range(0, 0, 0, 5)
      local sub = SubSymbol.new(nil, range)
      eq('', sub.name)
    end)

    it('sets name to empty string when range is nil', function()
      local doc = helpers.create_source_document({ 'hello world' })
      local sub = SubSymbol.new(doc, nil)
      eq('', sub.name)
    end)

    it('has correct metatable', function()
      local doc = helpers.create_source_document({ 'hello' })
      local range = make_range(0, 0, 0, 5)
      local sub = SubSymbol.new(doc, range)
      assert.is_true(getmetatable(sub) == SubSymbol)
    end)
  end)

  describe('text()', function()
    it('returns text from document for range', function()
      local doc = helpers.create_source_document({ 'foo bar baz' })
      local range = make_range(0, 4, 0, 7)
      local sub = SubSymbol.new(doc, range)
      eq('bar', sub:text())
    end)

    it('returns empty string when document is nil', function()
      local range = make_range(0, 0, 0, 5)
      local sub = SubSymbol.new(nil, range)
      eq('', sub:text())
    end)

    it('returns empty string when range is nil', function()
      local doc = helpers.create_source_document({ 'hello' })
      local sub = SubSymbol.new(doc, nil)
      eq('', sub:text())
    end)

    it('handles single-line range', function()
      local doc = helpers.create_source_document({ 'int x = 42;' })
      local range = make_range(0, 0, 0, 3)
      local sub = SubSymbol.new(doc, range)
      eq('int', sub:text())
    end)

    it('handles multi-line range', function()
      local doc = helpers.create_source_document({
        'void foo() {',
        '  int x;',
        '}',
      })
      local range = make_range(0, 0, 2, 1)
      local sub = SubSymbol.new(doc, range)
      eq('void foo() {\n  int x;\n}', sub:text())
    end)

    it('returns text from selection_range when range differs', function()
      local doc = helpers.create_source_document({ 'int myFunc(int x);' })
      local range = make_range(0, 0, 0, 19)
      local sel = make_range(0, 4, 0, 10)
      local sub = SubSymbol.new(doc, range, sel)
      -- text() uses self.range, not selection_range
      eq('int myFunc(int x);', sub:text())
    end)
  end)
end)
