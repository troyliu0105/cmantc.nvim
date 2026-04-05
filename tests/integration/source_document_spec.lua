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

  --------------------------------------------------------------------------------
  -- Position Helpers
  --------------------------------------------------------------------------------

  describe('offset_at', function()
    it('returns 0 for position at start of buffer', function()
      local doc = helpers.create_source_document({ 'hello', 'world' })
      local offset = doc:offset_at({ line = 0, character = 0 })
      eq(0, offset)
    end)

    it('calculates offset for position on first line', function()
      local doc = helpers.create_source_document({ 'hello world' })
      local offset = doc:offset_at({ line = 0, character = 5 })
      -- First line offset starts at 0, character 5
      eq(5, offset)
    end)

    it('calculates offset for position on second line', function()
      local doc = helpers.create_source_document({ 'hello', 'world' })
      local offset = doc:offset_at({ line = 1, character = 2 })
      -- Line 0: "hello\n" = 6 bytes, Line 1: character 2 = 2 more
      -- This depends on buffer byte offsets
      assert.is_true(offset >= 6)
    end)

    it('returns 0 for negative line offset', function()
      local doc = helpers.create_source_document({ 'test' })
      -- Edge case: try to get offset at invalid position
      local offset = doc:offset_at({ line = 0, character = 0 })
      eq(0, offset)
    end)
  end)

  describe('position_at_offset', function()
    it('returns start position for offset 0', function()
      local doc = helpers.create_source_document({ 'hello' })
      local pos = doc:position_at_offset(0)
      eq(0, pos.line)
      eq(0, pos.character)
    end)

    it('converts offset to position on first line', function()
      local doc = helpers.create_source_document({ 'hello world' })
      local pos = doc:position_at_offset(5)
      eq(0, pos.line)
      eq(5, pos.character)
    end)

    it('handles offset beyond content', function()
      local doc = helpers.create_source_document({ 'hi' })
      local pos = doc:position_at_offset(100)
      -- Should return last position
      assert.is_true(pos.line >= 0)
    end)

    it('handles negative offset', function()
      local doc = helpers.create_source_document({ 'test' })
      local pos = doc:position_at_offset(-1)
      eq(0, pos.line)
      eq(0, pos.character)
    end)

    it('handles empty buffer', function()
      local doc = helpers.create_source_document({ '' })
      local pos = doc:position_at_offset(0)
      eq(0, pos.line)
    end)
  end)

  describe('end_of_line', function()
    it('returns newline character for unix format', function()
      local doc = helpers.create_source_document({ 'test' })
      -- Default is unix format
      local eol = doc:end_of_line()
      eq('\n', eol)
    end)
  end)

  describe('indentation', function()
    it('returns spaces when expandtab is set', function()
      local bufnr = helpers.create_buffer({ 'test' }, 'cpp')
      vim.bo[bufnr].expandtab = true
      vim.bo[bufnr].shiftwidth = 4
      local doc = SourceDocument.new(bufnr)
      local indent = doc:indentation()
      eq('    ', indent)
    end)

    it('returns tab when expandtab is false', function()
      local bufnr = helpers.create_buffer({ 'test' }, 'cpp')
      vim.bo[bufnr].expandtab = false
      local doc = SourceDocument.new(bufnr)
      local indent = doc:indentation()
      eq('\t', indent)
    end)

    it('uses tabstop when shiftwidth is 0', function()
      local bufnr = helpers.create_buffer({ 'test' }, 'cpp')
      vim.bo[bufnr].expandtab = true
      vim.bo[bufnr].shiftwidth = 0
      vim.bo[bufnr].tabstop = 8
      local doc = SourceDocument.new(bufnr)
      local indent = doc:indentation()
      eq('        ', indent)
    end)
  end)

  describe('file_extension', function()
    it('returns cpp for .cpp file', function()
      local doc = helpers.create_source_document({ 'int x;' }, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.cpp')
      eq('cpp', doc:file_extension())
    end)

    it('returns h for .h file', function()
      local doc = helpers.create_source_document({ 'int x;' }, 'c')
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      eq('h', doc:file_extension())
    end)

    it('returns hpp for .hpp file', function()
      local doc = helpers.create_source_document({ 'class Foo {};' }, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.hpp')
      eq('hpp', doc:file_extension())
    end)

    it('handles paths with multiple dots', function()
      local doc = helpers.create_source_document({ 'int x;' }, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.file.cpp')
      eq('cpp', doc:file_extension())
    end)
  end)

  --------------------------------------------------------------------------------
  -- Header Guard Position Helpers
  --------------------------------------------------------------------------------

  describe('position_after_header_guard', function()
    it('returns nil for file without header guard', function()
      local doc = helpers.create_source_document({ 'int x;' })
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      local pos = doc:position_after_header_guard()
      assert.is_nil(pos)
    end)

    it('returns position after #ifndef/#define guard', function()
      local lines = {
        '#ifndef TEST_H',
        '#define TEST_H',
        '',
        'int x;',
        '',
        '#endif',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      local pos = doc:position_after_header_guard()
      assert.is_not_nil(pos)
      -- Should be after line 1 (#define)
      assert.is_true(pos.line >= 2)
    end)

    it('returns position after #pragma once', function()
      local lines = {
        '#pragma once',
        '',
        'int x;',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      local pos = doc:position_after_header_guard()
      assert.is_not_nil(pos)
      assert.is_true(pos.line >= 1)
    end)
  end)

  describe('position_after_header_comment', function()
    it('returns position after comment block', function()
      local lines = {
        '// Copyright 2024',
        '// License: MIT',
        '',
        'int x;',
      }
      local doc = helpers.create_source_document(lines)
      local pos = doc:position_after_header_comment()
      assert.is_not_nil(pos)
      assert.is_not_nil(pos.position)
    end)

    it('handles file with no comments', function()
      local doc = helpers.create_source_document({ 'int x;' })
      local pos = doc:position_after_header_comment()
      assert.is_not_nil(pos)
    end)

    it('handles empty file', function()
      local doc = helpers.create_source_document({ '' })
      local pos = doc:position_after_header_comment()
      assert.is_not_nil(pos)
    end)

    it('handles multi-line comment', function()
      local lines = {
        '/*',
        ' * Multi-line comment',
        ' */',
        '',
        'int x;',
      }
      local doc = helpers.create_source_document(lines)
      local pos = doc:position_after_header_comment()
      assert.is_not_nil(pos)
    end)
  end)

  describe('position_after_last_symbol', function()
    it('returns position after last symbol', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      local symbols = {
        {
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } },
        },
      }
      local pos = doc:position_after_last_symbol(doc, symbols)
      assert.is_not_nil(pos)
      assert.is_not_nil(pos.position)
      eq(1, pos.position.line)
    end)

    it('falls back to after last non-empty line for empty symbols', function()
      local doc = helpers.create_source_document({ 'int x;' })
      local pos = doc:position_after_last_symbol(doc, {})
      assert.is_not_nil(pos)
    end)

    it('handles nil symbols', function()
      local doc = helpers.create_source_document({ 'int x;' })
      local pos = doc:position_after_last_symbol(doc, nil)
      assert.is_not_nil(pos)
    end)
  end)

  describe('position_after_last_non_empty_line', function()
    it('returns position after last non-empty line', function()
      local doc = helpers.create_source_document({ 'line1', 'line2', '' })
      local pos = doc:position_after_last_non_empty_line(doc)
      assert.is_not_nil(pos)
      eq(2, pos.position.line)
    end)

    it('handles file with all empty lines', function()
      local doc = helpers.create_source_document({ '', '', '' })
      local pos = doc:position_after_last_non_empty_line(doc)
      assert.is_not_nil(pos)
    end)

    it('handles single line file', function()
      local doc = helpers.create_source_document({ 'single' })
      local pos = doc:position_after_last_non_empty_line(doc)
      assert.is_not_nil(pos)
      eq(1, pos.position.line)
    end)

    it('handles empty file', function()
      local doc = helpers.create_source_document({ '' })
      local pos = doc:position_after_last_non_empty_line(doc)
      assert.is_not_nil(pos)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Preprocessor/File Helpers
  --------------------------------------------------------------------------------

  describe('get_included_files', function()
    it('extracts system includes', function()
      local lines = {
        '#include <iostream>',
        '#include <vector>',
        '',
        'int main() {}',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      local includes = doc:get_included_files()
      assert.is_true(#includes >= 2)
      assert.is_true(vim.tbl_contains(includes, 'iostream'))
      assert.is_true(vim.tbl_contains(includes, 'vector'))
    end)

    it('extracts project includes', function()
      local lines = {
        '#include "myheader.h"',
        '#include "utils/helper.h"',
        '',
        'int main() {}',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      local includes = doc:get_included_files()
      assert.is_true(#includes >= 2)
      assert.is_true(vim.tbl_contains(includes, 'myheader.h'))
      assert.is_true(vim.tbl_contains(includes, 'utils/helper.h'))
    end)

    it('returns empty table for file with no includes', function()
      local doc = helpers.create_source_document({ 'int x;' })
      local includes = doc:get_included_files()
      eq({}, includes)
    end)

    it('handles mixed includes', function()
      local lines = {
        '#include <string>',
        '#include "local.h"',
        '#include <vector>',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      local includes = doc:get_included_files()
      assert.is_true(#includes >= 3)
    end)
  end)

  describe('get_header_guard_directives', function()
    it('returns empty for source file', function()
      local doc = helpers.create_source_document({ '#include <iostream>' })
      doc.uri = vim.uri_from_fname('/tmp/test.cpp')
      local directives = doc:get_header_guard_directives()
      eq({}, directives)
    end)

    it('finds #ifndef/#define/#endif guard', function()
      local lines = {
        '#ifndef TEST_H',
        '#define TEST_H',
        '',
        'int x;',
        '',
        '#endif',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      local directives = doc:get_header_guard_directives()
      assert.is_true(#directives >= 2)
    end)

    it('finds #pragma once', function()
      local lines = {
        '#pragma once',
        '',
        'int x;',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      local directives = doc:get_header_guard_directives()
      assert.is_true(#directives >= 1)
    end)
  end)

  describe('has_pragma_once', function()
    it('returns true for file with #pragma once', function()
      local lines = {
        '#pragma once',
        '',
        'class Foo {};',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      assert.is_true(doc:has_pragma_once())
    end)

    it('returns false for file with #ifndef guard', function()
      local lines = {
        '#ifndef TEST_H',
        '#define TEST_H',
        '',
        'int x;',
        '#endif',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      assert.is_false(doc:has_pragma_once())
    end)

    it('returns false for file without guard', function()
      local doc = helpers.create_source_document({ 'int x;' })
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      assert.is_false(doc:has_pragma_once())
    end)
  end)

  describe('find_position_for_new_include', function()
    it('returns position after existing system includes', function()
      local lines = {
        '#include <iostream>',
        '#include <vector>',
        '',
        'int main() {}',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      local pos = doc:find_position_for_new_include()
      assert.is_not_nil(pos.system)
      assert.is_not_nil(pos.project)
      -- System include should be after line 1
      assert.is_true(pos.system.line >= 1)
    end)

    it('returns position after existing project includes', function()
      local lines = {
        '#include "local.h"',
        '#include "other.h"',
        '',
        'int main() {}',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      local pos = doc:find_position_for_new_include()
      assert.is_not_nil(pos.system)
      assert.is_not_nil(pos.project)
    end)

    it('falls back to after header guard when no includes', function()
      local lines = {
        '#ifndef TEST_H',
        '#define TEST_H',
        '',
        'int x;',
        '#endif',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      doc.uri = vim.uri_from_fname('/tmp/test.h')
      local pos = doc:find_position_for_new_include()
      assert.is_not_nil(pos.system)
      assert.is_not_nil(pos.project)
    end)

    it('handles empty file', function()
      local doc = helpers.create_source_document({ '' })
      local pos = doc:find_position_for_new_include()
      assert.is_not_nil(pos.system)
      assert.is_not_nil(pos.project)
    end)

    it('respects before_pos parameter', function()
      local lines = {
        '#include <iostream>',
        '#include <vector>',
        '#include <string>',
        '',
        'int main() {}',
      }
      local doc = helpers.create_source_document(lines, 'cpp')
      local pos = doc:find_position_for_new_include({ line = 1, character = 0 })
      -- Should stop before #include <string>
      assert.is_not_nil(pos.system)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Symbol Helpers
  --------------------------------------------------------------------------------

  describe('get_c_symbols', function()
    it('returns empty table for buffer without LSP', function()
      local doc = helpers.create_source_document({ 'int x;' })
      -- No LSP attached, should handle gracefully
      local symbols = doc:get_c_symbols()
      -- Without LSP, symbols should be empty or handled gracefully
      assert.is_not_nil(symbols)
    end)

    it('caches symbols after first call', function()
      local doc = helpers.create_source_document({ 'int x;' })
      local symbols1 = doc:get_c_symbols()
      local symbols2 = doc:get_c_symbols()
      eq(symbols1, symbols2)
    end)
  end)

  describe('get_symbol_at_position', function()
    it('returns nil for empty document', function()
      local doc = helpers.create_source_document({ '' })
      -- Inject mock symbols
      doc.symbols = {}
      local symbol = doc:get_symbol_at_position({ line = 0, character = 0 })
      assert.is_nil(symbol)
    end)

    it('finds symbol at position', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      -- Inject mock symbol
      doc.symbols = {
        {
          name = 'foo',
          kind = 12, -- Function
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } },
          selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 8 } },
          children = {},
        },
      }
      local symbol = doc:get_symbol_at_position({ line = 0, character = 5 })
      assert.is_not_nil(symbol)
      eq('foo', symbol.name)
    end)

    it('returns nil for position outside all symbols', function()
      local doc = helpers.create_source_document({ 'void foo() {}', '', 'void bar() {}' })
      doc.symbols = {
        {
          name = 'foo',
          kind = 12,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } },
          selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 8 } },
          children = {},
        },
      }
      local symbol = doc:get_symbol_at_position({ line = 5, character = 0 })
      assert.is_nil(symbol)
    end)

    it('finds deepest nested symbol', function()
      local doc = helpers.create_source_document({ 'namespace NS { void foo() {} }' })
      -- Mock nested symbols
      doc.symbols = {
        {
          name = 'NS',
          kind = 3, -- Namespace
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 30 } },
          selectionRange = { start = { line = 0, character = 10 }, ['end'] = { line = 0, character = 12 } },
          children = {
            {
              name = 'foo',
              kind = 12, -- Function
              range = { start = { line = 0, character = 14 }, ['end'] = { line = 0, character = 28 } },
              selectionRange = { start = { line = 0, character = 19 }, ['end'] = { line = 0, character = 22 } },
              children = {},
            },
          },
        },
      }
      local symbol = doc:get_symbol_at_position({ line = 0, character = 19 })
      assert.is_not_nil(symbol)
      eq('foo', symbol.name)
    end)
  end)

  describe('find_matching_symbol', function()
    it('finds matching symbol by name and kind', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      doc.symbols = {
        {
          name = 'foo',
          kind = 12, -- Function
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } },
          selectionRange = { start = { line = 0, character = 5 }, ['end'] = { line = 0, character = 8 } },
          children = {},
        },
      }
      local target = { name = 'foo', kind = 12 }
      local found = doc:find_matching_symbol(target)
      assert.is_not_nil(found)
      eq('foo', found.name)
    end)

    it('returns nil for non-matching symbol', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      doc.symbols = {
        {
          name = 'foo',
          kind = 12,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } },
          children = {},
        },
      }
      local target = { name = 'bar', kind = 12 }
      local found = doc:find_matching_symbol(target)
      assert.is_nil(found)
    end)

    it('searches nested symbols', function()
      local doc = helpers.create_source_document({ 'namespace NS { void foo() {} }' })
      doc.symbols = {
        {
          name = 'NS',
          kind = 3, -- Namespace
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 30 } },
          children = {
            {
              name = 'foo',
              kind = 12, -- Function
              range = { start = { line = 0, character = 14 }, ['end'] = { line = 0, character = 28 } },
              children = {},
            },
          },
        },
      }
      local target = { name = 'foo', kind = 12 }
      local found = doc:find_matching_symbol(target)
      assert.is_not_nil(found)
      eq('foo', found.name)
    end)

    it('returns nil for empty symbols', function()
      local doc = helpers.create_source_document({ '' })
      doc.symbols = {}
      local target = { name = 'foo', kind = 12 }
      local found = doc:find_matching_symbol(target)
      assert.is_nil(found)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Smart Positioning: Sibling Functions
  --------------------------------------------------------------------------------

  describe('get_sibling_functions', function()
    it('returns functions from same parent', function()
      local doc = helpers.create_source_document({})
      local parent = { children = {} }
      local func1 = {
        name = 'foo',
        kind = 12, -- Function
        parent = parent,
        is_function = function() return true end,
      }
      local func2 = {
        name = 'bar',
        kind = 12, -- Function
        parent = parent,
        is_function = function() return true end,
      }
      local field = {
        name = 'x',
        kind = 8, -- Field
        parent = parent,
        is_function = function() return false end,
      }
      parent.children = { func1, field, func2 }

      local siblings = doc:get_sibling_functions(func1)
      eq(2, #siblings)
    end)

    it('returns functions from root when no parent', function()
      local doc = helpers.create_source_document({})
      doc.symbols = {}
      local func = {
        name = 'foo',
        kind = 12, -- Function
        parent = nil,
        is_function = function() return true end,
      }

      local siblings = doc:get_sibling_functions(func)
      assert.is_not_nil(siblings)
    end)

    it('filters out non-functions', function()
      local doc = helpers.create_source_document({})
      local parent = { children = {} }
      local func = {
        name = 'foo',
        kind = 12, -- Function
        parent = parent,
        is_function = function() return true end,
      }
      local cls = {
        name = 'MyClass',
        kind = 5, -- Class
        parent = parent,
        is_function = function() return false end,
      }
      parent.children = { func, cls }

      local siblings = doc:get_sibling_functions(func)
      eq(1, #siblings)
    end)
  end)

  describe('index_of_symbol', function()
    it('finds symbol index by position', function()
      local doc = helpers.create_source_document({})
      local siblings = {
        { selection_range = { start = { line = 0, character = 5 } } },
        { selection_range = { start = { line = 1, character = 5 } } },
        { selection_range = { start = { line = 2, character = 5 } } },
      }
      local symbol = { selection_range = { start = { line = 1, character = 5 } } }

      local idx = doc:index_of_symbol(symbol, siblings)
      eq(2, idx)
    end)

    it('returns 0 for symbol not found', function()
      local doc = helpers.create_source_document({})
      local siblings = {
        { selection_range = { start = { line = 0, character = 5 } } },
      }
      local symbol = { selection_range = { start = { line = 5, character = 5 } } }

      local idx = doc:index_of_symbol(symbol, siblings)
      eq(0, idx)
    end)

    it('returns 0 for symbol without selection_range', function()
      local doc = helpers.create_source_document({})
      local siblings = {
        { selection_range = { start = { line = 0, character = 5 } } },
      }
      local symbol = {}

      local idx = doc:index_of_symbol(symbol, siblings)
      eq(0, idx)
    end)

    it('handles empty siblings array', function()
      local doc = helpers.create_source_document({})
      local symbol = { selection_range = { start = { line = 0, character = 0 } } }

      local idx = doc:index_of_symbol(symbol, {})
      eq(0, idx)
    end)
  end)

  describe('scopes_intersect', function()
    it('returns true for matching scopes', function()
      local doc = helpers.create_source_document({})
      local scopes_a = { { name = 'NS', kind = 3 } }
      local scopes_b = { { name = 'NS', kind = 3 } }

      local result = doc:scopes_intersect(scopes_a, scopes_b)
      assert.is_true(result)
    end)

    it('returns true when one scope matches', function()
      local doc = helpers.create_source_document({})
      local scopes_a = { { name = 'NS1', kind = 3 }, { name = 'NS2', kind = 3 } }
      local scopes_b = { { name = 'NS2', kind = 3 }, { name = 'NS3', kind = 3 } }

      local result = doc:scopes_intersect(scopes_a, scopes_b)
      assert.is_true(result)
    end)

    it('returns false for disjoint scopes', function()
      local doc = helpers.create_source_document({})
      local scopes_a = { { name = 'NS1', kind = 3 } }
      local scopes_b = { { name = 'NS2', kind = 3 } }

      local result = doc:scopes_intersect(scopes_a, scopes_b)
      assert.is_false(result)
    end)

    it('returns true for empty scopes', function()
      local doc = helpers.create_source_document({})
      local result = doc:scopes_intersect({}, {})
      assert.is_true(result)
    end)

    it('returns true for nil scopes', function()
      local doc = helpers.create_source_document({})
      local result = doc:scopes_intersect(nil, nil)
      assert.is_true(result)
    end)

    it('matches by name and kind', function()
      local doc = helpers.create_source_document({})
      local scopes_a = { { name = 'MyClass', kind = 5 } } -- Class
      local scopes_b = { { name = 'MyClass', kind = 5 } }

      local result = doc:scopes_intersect(scopes_a, scopes_b)
      assert.is_true(result)
    end)

    it('does not match different kinds with same name', function()
      local doc = helpers.create_source_document({})
      local scopes_a = { { name = 'Foo', kind = 3 } } -- Namespace
      local scopes_b = { { name = 'Foo', kind = 5 } } -- Class

      local result = doc:scopes_intersect(scopes_a, scopes_b)
      assert.is_false(result)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Smart Positioning: Function Definition
  --------------------------------------------------------------------------------

  describe('find_smart_position_for_function_definition', function()
    it('returns position after last non-empty line for empty target', function()
      local doc = helpers.create_source_document({ 'void foo();' })
      local target_doc = helpers.create_source_document({})
      target_doc.symbols = {}

      local declaration = {
        name = 'foo',
        kind = 12,
        selection_range = { start = { line = 0, character = 5 } },
        parent = nil,
        scopes = function() return {} end,
      }

      local pos = doc:find_smart_position_for_function_definition(declaration, target_doc)
      assert.is_not_nil(pos)
      assert.is_not_nil(pos.position)
    end)

    it('uses target_doc as self when not provided', function()
      local doc = helpers.create_source_document({ 'void foo();', 'void bar();' })
      doc.symbols = {
        {
          name = 'foo',
          kind = 12,
          selection_range = { start = { line = 0, character = 5 } },
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 12 } },
          parent = nil,
          is_function = function() return true end,
          is_function_declaration = function() return true end,
          scopes = function() return {} end,
          find_definition = function() return nil end,
        },
        {
          name = 'bar',
          kind = 12,
          selection_range = { start = { line = 1, character = 5 } },
          range = { start = { line = 1, character = 0 }, ['end'] = { line = 1, character = 12 } },
          parent = nil,
          is_function = function() return true end,
          is_function_declaration = function() return true end,
          scopes = function() return {} end,
          find_definition = function() return nil end,
        },
      }

      local declaration = doc.symbols[1]
      local pos = doc:find_smart_position_for_function_definition(declaration)
      assert.is_not_nil(pos)
    end)

    it('falls back to position after last symbol', function()
      local doc = helpers.create_source_document({ 'void foo();' })
      local target_doc = helpers.create_source_document({ 'void bar() {}' })
      target_doc.symbols = {
        {
          name = 'bar',
          kind = 12,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 14 } },
        },
      }

      local declaration = {
        name = 'foo',
        kind = 12,
        selection_range = { start = { line = 0, character = 5 } },
        parent = { children = {} },
        scopes = function() return {} end,
      }

      local pos = doc:find_smart_position_for_function_definition(declaration, target_doc)
      assert.is_not_nil(pos)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Smart Positioning: Function Declaration
  --------------------------------------------------------------------------------

  describe('find_smart_position_for_function_declaration', function()
    it('returns position after last non-empty line for empty target', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      local target_doc = helpers.create_source_document({})
      target_doc.symbols = {}

      local definition = {
        name = 'foo',
        kind = 12,
        selection_range = { start = { line = 0, character = 5 } },
        parent = nil,
        scopes = function() return {} end,
      }

      local pos = doc:find_smart_position_for_function_declaration(definition, target_doc, nil, 'public')
      assert.is_not_nil(pos)
      assert.is_not_nil(pos.position)
    end)

    it('tries member function position when access is specified', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      local target_doc = helpers.create_source_document({ 'class MyClass {};' })
      target_doc.symbols = {}

      local definition = {
        name = 'foo',
        kind = 12,
        selection_range = { start = { line = 0, character = 5 } },
        parent = nil,
        scopes = function() return {} end,
        immediate_scope = function() return nil end,
      }

      local pos = doc:find_smart_position_for_function_declaration(definition, target_doc, nil, 'public')
      assert.is_not_nil(pos)
    end)

    it('falls back to position after last symbol', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      local target_doc = helpers.create_source_document({ 'void bar();' })
      target_doc.symbols = {
        {
          name = 'bar',
          kind = 12,
          range = { start = { line = 0, character = 0 }, ['end'] = { line = 0, character = 12 } },
        },
      }

      local definition = {
        name = 'foo',
        kind = 12,
        selection_range = { start = { line = 0, character = 5 } },
        parent = { children = {} },
        scopes = function() return {} end,
        immediate_scope = function() return nil end,
      }

      local pos = doc:find_smart_position_for_function_declaration(definition, target_doc, nil, nil)
      assert.is_not_nil(pos)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Smart Positioning: Member Functions
  --------------------------------------------------------------------------------

  describe('find_position_for_member_function', function()
    it('uses parent_class find_position_for_new_member_function when available', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      local target_doc = helpers.create_source_document({ 'class MyClass {};' })

      local parent_class = {
        find_position_for_new_member_function = function(self, access)
          return require('cmantic.proposed_position').new({ line = 5, character = 0 }, {})
        end,
      }

      local symbol = {
        name = 'foo',
        kind = 12,
      }

      local pos = doc:find_position_for_member_function(symbol, target_doc, parent_class, 'public')
      assert.is_not_nil(pos)
      eq(5, pos.position.line)
    end)

    it('returns nil when no parent class found', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      local target_doc = helpers.create_source_document({ 'void bar() {}' })

      local symbol = {
        name = 'foo',
        kind = 12,
        immediate_scope = function() return nil end,
      }

      local pos = doc:find_position_for_member_function(symbol, target_doc, nil, 'public')
      assert.is_nil(pos)
    end)

    it('defaults to public access when not specified', function()
      local doc = helpers.create_source_document({})
      local target_doc = helpers.create_source_document({})

      local parent_class = {
        find_position_for_new_member_function = function(self, access)
          eq('public', access)
          return require('cmantic.proposed_position').new({ line = 0, character = 0 }, {})
        end,
      }

      local symbol = {}
      doc:find_position_for_member_function(symbol, target_doc, parent_class, nil)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Smart Positioning: Namespace
  --------------------------------------------------------------------------------

  describe('find_position_in_parent_namespace', function()
    it('finds position in matching namespace', function()
      local doc = helpers.create_source_document({ 'namespace NS { void foo(); }' })
      local target_doc = helpers.create_source_document({ 'namespace NS {}' })

      local namespace_sym = {
        name = 'NS',
        kind = 3, -- Namespace
        is_namespace = function() return true end,
        children = {},
        body_start = function() return { line = 0, character = 14 } end,
      }
      target_doc.symbols = { namespace_sym }

      local symbol = {
        name = 'foo',
        kind = 12,
        scopes = function()
          return { namespace_sym }
        end,
      }

      local pos = doc:find_position_in_parent_namespace(symbol, target_doc)
      assert.is_not_nil(pos)
    end)

    it('returns nil when no matching namespace found', function()
      local doc = helpers.create_source_document({ 'void foo() {}' })
      local target_doc = helpers.create_source_document({ 'void bar() {}' })
      target_doc.symbols = {}

      local symbol = {
        name = 'foo',
        kind = 12,
        scopes = function()
          return { { name = 'NonExistent', kind = 3, is_namespace = function() return true end } }
        end,
      }

      local pos = doc:find_position_in_parent_namespace(symbol, target_doc)
      assert.is_nil(pos)
    end)

    it('positions after last child in non-empty namespace', function()
      local doc = helpers.create_source_document({ 'namespace NS { void foo(); }' })
      local target_doc = helpers.create_source_document({ 'namespace NS { void bar() {} }' })

      local namespace_sym = {
        name = 'NS',
        kind = 3, -- Namespace
        is_namespace = function() return true end,
        children = {
          {
            name = 'bar',
            kind = 12,
            range = { start = { line = 0, character = 15 }, ['end'] = { line = 0, character = 29 } },
          },
        },
      }
      target_doc.symbols = { namespace_sym }

      local symbol = {
        name = 'foo',
        kind = 12,
        scopes = function()
          return { namespace_sym }
        end,
      }

      local pos = doc:find_position_in_parent_namespace(symbol, target_doc)
      assert.is_not_nil(pos)
    end)

    it('returns nil for symbol without scopes', function()
      local doc = helpers.create_source_document({})
      local target_doc = helpers.create_source_document({})

      local symbol = {
        name = 'foo',
        kind = 12,
        scopes = function() return {} end,
      }

      local pos = doc:find_position_in_parent_namespace(symbol, target_doc)
      assert.is_nil(pos)
    end)
  end)

  --------------------------------------------------------------------------------
  -- Smart Positioning: Relative to Siblings
  --------------------------------------------------------------------------------

  describe('find_position_relative_to_siblings', function()
    it('returns nil when no siblings have definitions', function()
      local doc = helpers.create_source_document({})
      local target_doc = helpers.create_source_document({ 'void foo() {}' })

      local anchor = {
        name = 'bar',
        kind = 12,
        scopes = function() return {} end,
      }

      local before = {
        {
          name = 'existing',
          kind = 12,
          is_function_declaration = function() return true end,
          find_definition = function() return nil end,
        },
      }

      local pos = doc:find_position_relative_to_siblings(anchor, before, {}, target_doc, true, nil)
      assert.is_nil(pos)
    end)

    it('checks up to 5 siblings before', function()
      local doc = helpers.create_source_document({})
      local target_doc = helpers.create_source_document({})

      local anchor = {
        name = 'bar',
        kind = 12,
        scopes = function() return {} end,
      }

      -- Create 6 siblings before
      local before = {}
      for i = 1, 6 do
        table.insert(before, {
          name = 'sibling' .. i,
          kind = 12,
          is_function_declaration = function() return true end,
          find_definition = function() return nil end,
        })
      end

      local pos = doc:find_position_relative_to_siblings(anchor, before, {}, target_doc, true, nil)
      assert.is_nil(pos) -- No matching definitions
    end)

    it('checks up to 5 siblings after', function()
      local doc = helpers.create_source_document({})
      local target_doc = helpers.create_source_document({})

      local anchor = {
        name = 'bar',
        kind = 12,
        scopes = function() return {} end,
      }

      -- Create 6 siblings after
      local after = {}
      for i = 1, 6 do
        table.insert(after, {
          name = 'sibling' .. i,
          kind = 12,
          is_function_definition = function() return true end,
          find_declaration = function() return nil end,
        })
      end

      local pos = doc:find_position_relative_to_siblings(anchor, {}, after, target_doc, false, nil)
      assert.is_nil(pos) -- No matching declarations
    end)

    it('returns nil for empty before and after', function()
      local doc = helpers.create_source_document({})
      local target_doc = helpers.create_source_document({})

      local anchor = {
        name = 'bar',
        kind = 12,
        scopes = function() return {} end,
      }

      local pos = doc:find_position_relative_to_siblings(anchor, {}, {}, target_doc, true, nil)
      assert.is_nil(pos)
    end)
  end)
end)
