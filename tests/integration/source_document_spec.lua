local helpers = require('tests.helpers')
local SourceDocument = require('cmantic.source_document')
local eq = assert.are.same

describe('source_document', function()
  describe('is_header / is_source', function()
    it('detects .h as header', function()
      local doc = helpers.create_source_document({ 'int x;' }, 'c')
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
      doc.uri = vim.uri_from_fname('/tmp/empty_header.h')
      assert.is_false(doc:has_header_guard())
    end)

    it('detects existing #ifndef/#define guard', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/guarded_header.h')
      local doc = SourceDocument.new(bufnr)
      doc.uri = vim.uri_from_fname('/tmp/guarded_header.h')
      assert.is_true(doc:has_header_guard())
    end)

    it('detects header guard with wrong name (renamed header)', function()
      local bufnr = helpers.create_buffer_from_fixture('c++/renamed_header.h')
      local doc = SourceDocument.new(bufnr)
      doc.uri = vim.uri_from_fname('/tmp/renamed_header.h')
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
      assert.is_true(#directives >= 4)
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

  describe('text modification', function()
    it('insert_text adds text at position', function()
      local doc = helpers.create_source_document({ 'hello world' })
      doc:insert_text({ line = 0, character = 5 }, ', cruel')
      eq('hello, cruel world', doc:get_text())
    end)

    it('replace_text replaces text in range', function()
      local doc = helpers.create_source_document({ 'hello world' })
      doc:replace_text(
        { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 5 } },
        'goodbye'
      )
      eq('goodbye world', doc:get_text())
    end)

    it('insert_lines adds lines at given line number', function()
      local doc = helpers.create_source_document({ 'line1', 'line3' })
      doc:insert_lines(1, { 'line2' })
      eq({ 'line1', 'line2', 'line3' }, doc:get_lines())
    end)

    it('get_lines returns all lines', function()
      local doc = helpers.create_source_document({ 'a', 'b', 'c' })
      eq({ 'a', 'b', 'c' }, doc:get_lines())
    end)

    it('line_count returns correct count', function()
      local doc = helpers.create_source_document({ 'a', 'b', 'c' })
      eq(3, doc:line_count())
    end)
  end)
end)
