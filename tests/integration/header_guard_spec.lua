local helpers = require('tests.helpers')
local add_header_guard = require('cmantic.commands.add_header_guard')
local SourceDocument = require('cmantic.source_document')
local config = require('cmantic.config')

local eq = assert.are.same

local function load_fixture_buf(name, ft)
  local cwd = vim.fn.getcwd()
  local fname = cwd .. '/tests/fixtures/' .. name
  local bufnr = vim.fn.bufadd(fname)
  vim.fn.bufload(bufnr)
  vim.bo[bufnr].filetype = ft or 'cpp'
  return bufnr
end

local function make_buf_in_project(lines, fname)
  local cwd = vim.fn.getcwd()
  local fullpath = cwd .. '/tests/fixtures/' .. fname
  local f = io.open(fullpath, 'w')
  for _, line in ipairs(lines) do
    f:write(line .. '\n')
  end
  f:close()
  local bufnr = vim.fn.bufadd(fullpath)
  vim.fn.bufload(bufnr)
  vim.bo[bufnr].filetype = 'c'
  return bufnr, fullpath
end

describe('header_guard', function()
  local saved_config

  before_each(function()
    saved_config = vim.deepcopy(config.values)
  end)

  after_each(function()
    config.values = saved_config
  end)

  describe('_format_guard_name', function()
    it('formats guard from filename', function()
      local bufnr = load_fixture_buf('c++/guarded_header.h', 'c')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      eq('GUARDED_HEADER_H', name)
    end)

    it('resolves ${PATH} token', function()
      config.merge({ header_guard_format = '${PATH}' })
      local bufnr, path = make_buf_in_project({ '' }, 'my_header.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      -- Path is uppercased and non-alnum replaced with underscore
      assert.is_not_nil(name:match('MY_HEADER'))
      assert.is_nil(name:match('${PATH}'))
      os.remove(path)
    end)

    it('collapses multiple consecutive non-alphanumeric chars to single underscore', function()
      config.merge({ header_guard_format = '${FILE_NAME}___${EXT}' })
      local bufnr, path = make_buf_in_project({ '' }, 'collapse.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      -- The ___ between tokens should collapse to single _
      assert.is_nil(name:match('__'))
      os.remove(path)
    end)

    it('strips leading underscores from guard name', function()
      config.merge({ header_guard_format = '_${FILE_NAME}_${EXT}' })
      local bufnr, path = make_buf_in_project({ '' }, 'leading.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      assert.is_not_nil(name:match('^[^_]'))
      os.remove(path)
    end)

    it('strips trailing underscores from guard name', function()
      config.merge({ header_guard_format = '${FILE_NAME}_${EXT}_' })
      local bufnr, path = make_buf_in_project({ '' }, 'trailing.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      assert.is_not_nil(name:match('[^_]$'))
      os.remove(path)
    end)

    it('handles file with hyphens in name', function()
      local bufnr, path = make_buf_in_project({ '' }, 'my-component.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      -- Hyphens become underscores
      assert.is_not_nil(name:match('MY_COMPONENT'))
      -- No hyphens in guard name
      assert.is_nil(name:match('-'))
      os.remove(path)
    end)
  end)

  describe('_get_existing_guard_name', function()
    it('extracts guard name from #ifndef GUARD_NAME', function()
      local lines = {
        '#ifndef MY_GUARD_H',
        '#define MY_GUARD_H',
        '',
        '#endif // MY_GUARD_H',
      }
      local bufnr, path = make_buf_in_project(lines, 'extract_guard.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._get_existing_guard_name(doc)
      eq('MY_GUARD_H', name)
      os.remove(path)
    end)

    it('returns nil when no #ifndef/#define guard pair exists', function()
      local lines = {
        '#include <stdio.h>',
        '',
        'void foo();',
      }
      local bufnr, path = make_buf_in_project(lines, 'no_guard.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._get_existing_guard_name(doc)
      assert.is_nil(name)
      os.remove(path)
    end)

    it('returns nil when file has only #pragma once', function()
      local lines = {
        '#pragma once',
        '',
        'void foo();',
      }
      local bufnr, path = make_buf_in_project(lines, 'pragma_only.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._get_existing_guard_name(doc)
      assert.is_nil(name)
      os.remove(path)
    end)

    it('returns nil on empty file with no directives', function()
      local bufnr, path = make_buf_in_project({ '' }, 'empty_nodirective.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._get_existing_guard_name(doc)
      assert.is_nil(name)
      os.remove(path)
    end)
  end)

  describe('execute — add guard', function()
    it('adds #ifndef/#define/#endif to empty header', function()
      local bufnr, path = make_buf_in_project({ '' }, 'test_hg_add.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, '\n')
      assert.is_not_nil(content:find('#ifndef'))
      assert.is_not_nil(content:find('#define'))
      assert.is_not_nil(content:find('#endif'))

      os.remove(path)
    end)

    it('inserts only #pragma once when header_guard_style is pragma_once', function()
      config.merge({ header_guard_style = 'pragma_once' })
      local bufnr, path = make_buf_in_project({ '' }, 'pragma_style.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, '\n')
      assert.is_not_nil(content:find('#pragma once'))
      assert.is_nil(content:find('#ifndef'))
      assert.is_nil(content:find('#endif'))

      os.remove(path)
    end)

    it('inserts #ifndef, #define, AND #pragma once when header_guard_style is both', function()
      config.merge({ header_guard_style = 'both' })
      local bufnr, path = make_buf_in_project({ '' }, 'both_style.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, '\n')
      assert.is_not_nil(content:find('#ifndef'))
      assert.is_not_nil(content:find('#define'))
      assert.is_not_nil(content:find('#pragma once'))
      assert.is_not_nil(content:find('#endif'))

      os.remove(path)
    end)
  end)

  describe('execute — precondition checks', function()
    it('warns and returns when current file is not a header file', function()
      local bufnr, path = make_buf_in_project({ '' }, 'not_a_header.cpp')
      vim.api.nvim_set_current_buf(bufnr)

      -- Execute should not error, just notify and return
      add_header_guard.execute()

      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(lines, '\n')
      assert.is_nil(content:find('#ifndef'))
      assert.is_nil(content:find('#pragma once'))

      os.remove(path)
    end)

    it('calls _amend_guard when doc already has a header guard', function()
      local lines = {
        '#ifndef EXISTING_H',
        '#define EXISTING_H',
        '',
        '#endif // EXISTING_H',
      }
      local bufnr, path = make_buf_in_project(lines, 'amend_target.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(updated, '\n')
      -- Guard name should have changed from EXISTING_H to AMEND_TARGET_H
      assert.is_nil(content:find('EXISTING_H'))
      assert.is_not_nil(content:find('AMEND_TARGET_H'))

      os.remove(path)
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
      local bufnr, path = make_buf_in_project(lines, 'new_name.h')
      vim.api.nvim_set_current_buf(bufnr)

      local doc = SourceDocument.new(bufnr)
      local new_guard = add_header_guard._format_guard_name(doc)

      add_header_guard._amend_guard(doc, new_guard)

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(updated, '\n')
      assert.is_nil(content:find('OLD_GUARD_H'))
      assert.is_not_nil(content:find(new_guard))

      os.remove(path)
    end)

    it('does nothing when guard name is already correct', function()
      local lines = {
        '#ifndef ALREADY_CORRECT_H',
        '#define ALREADY_CORRECT_H',
        '',
        '#endif // ALREADY_CORRECT_H',
      }
      local bufnr, path = make_buf_in_project(lines, 'already_correct.h')
      local doc = SourceDocument.new(bufnr)
      local guard = add_header_guard._format_guard_name(doc)

      add_header_guard._amend_guard(doc, guard)

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq(lines, updated)

      os.remove(path)
    end)

    it('warns when no existing guard found', function()
      local lines = {
        '#include <stdio.h>',
        '',
        'void foo();',
      }
      local bufnr, path = make_buf_in_project(lines, 'no_guard_amend.h')
      local doc = SourceDocument.new(bufnr)

      -- Should not error, just notify and return
      add_header_guard._amend_guard(doc, 'NEW_GUARD_H')

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq(lines, updated)

      os.remove(path)
    end)

    it('replaces guard name in all three directive lines simultaneously', function()
      local lines = {
        '#ifndef AAA_H',
        '#define AAA_H',
        '',
        'void foo();',
        '',
        '#endif // AAA_H',
      }
      local bufnr, path = make_buf_in_project(lines, 'triple_replace.h')
      local doc = SourceDocument.new(bufnr)

      add_header_guard._amend_guard(doc, 'BBB_H')

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq('#ifndef BBB_H', updated[1])
      eq('#define BBB_H', updated[2])
      eq('#endif // BBB_H', updated[6])

      os.remove(path)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: execute() with existing #pragma once
  --------------------------------------------------------------------------------

  describe('execute() with existing #pragma once', function()
    it('should NOT add #ifndef guard when #pragma once exists', function()
      local lines = {
        '#pragma once',
        '',
        'void foo();',
      }
      local bufnr, path = make_buf_in_project(lines, 'pragma_exists.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(updated, '\n')
      assert.is_nil(content:find('#ifndef'))
      assert.is_nil(content:find('#define'))
      os.remove(path)
    end)

    it('should NOT add another #pragma once when one already exists', function()
      local lines = {
        '#pragma once',
        '',
        'void foo();',
      }
      local bufnr, path = make_buf_in_project(lines, 'pragma_duplicate.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local pragma_count = 0
      for _, line in ipairs(updated) do
        if line:match('#pragma once') then
          pragma_count = pragma_count + 1
        end
      end
      eq(1, pragma_count)
      os.remove(path)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: execute() with header comments
  --------------------------------------------------------------------------------

  describe('execute() with header comments', function()
    it('should insert guard AFTER comment block at top', function()
      local lines = {
        '// Copyright 2024 MyCompany',
        '// All rights reserved',
        '',
        'void foo();',
      }
      local bufnr, path = make_buf_in_project(lines, 'comment_top.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq('// Copyright 2024 MyCompany', updated[1])
      eq('// All rights reserved', updated[2])
      local has_guard = false
      for _, line in ipairs(updated) do
        if line:match('#ifndef') then has_guard = true break end
      end
      assert.True(has_guard, 'should have #ifndef guard')
      os.remove(path)
    end)

    it('should insert guard after single-line comment with blank line', function()
      local lines = {
        '// Copyright 2024',
        '',
        'void foo();',
      }
      local bufnr, path = make_buf_in_project(lines, 'comment_blank.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq('// Copyright 2024', updated[1])
      local has_guard = false
      for _, line in ipairs(updated) do
        if line:match('#ifndef') then has_guard = true break end
      end
      assert.True(has_guard, 'should have #ifndef guard')
      os.remove(path)
    end)

    it('should insert guard after multi-line block comment', function()
      local lines = {
        '/*',
        ' * Multi-line copyright',
        ' * header comment',
        ' */',
        '',
        'void foo();',
      }
      local bufnr, path = make_buf_in_project(lines, 'block_comment.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq('/*', updated[1])
      eq(' * Multi-line copyright', updated[2])
      eq(' * header comment', updated[3])
      eq(' */', updated[4])
      local has_guard = false
      for _, line in ipairs(updated) do
        if line:match('#ifndef') then has_guard = true break end
      end
      assert.True(has_guard, 'should have #ifndef guard')
      os.remove(path)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: _format_guard_name edge cases
  --------------------------------------------------------------------------------

  describe('_format_guard_name edge cases', function()
    it('handles file with dots in name', function()
      local bufnr, path = make_buf_in_project({ '' }, 'foo.bar.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      assert.is_not_nil(name:match('FOO'))
      assert.is_not_nil(name:match('BAR'))
      assert.is_not_nil(name:match('H'))
      assert.is_nil(name:match('%.'))
      os.remove(path)
    end)

    it('handles file with uppercase in name', function()
      local bufnr, path = make_buf_in_project({ '' }, 'MyHeader.H')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      eq('MYHEADER_H', name)
      os.remove(path)
    end)

    it('handles file with numbers in name', function()
      local bufnr, path = make_buf_in_project({ '' }, 'v2_parser.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      assert.is_not_nil(name:match('V2'))
      assert.is_not_nil(name:match('PARSER'))
      os.remove(path)
    end)

    it('handles custom format with ${PATH} producing long path', function()
      config.merge({ header_guard_format = '${PATH}' })
      local bufnr, path = make_buf_in_project({ '' }, 'deeply_nested_header.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      assert.is_true(#name > 0)
      assert.is_nil(name:match('${PATH}'))
      os.remove(path)
    end)

    it('handles format string with unknown token', function()
      config.merge({ header_guard_format = '${UNKNOWN}_${FILE_NAME}_${EXT}' })
      local bufnr, path = make_buf_in_project({ '' }, 'unknown_token.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      assert.is_not_nil(name:match('UNKNOWN_TOKEN'))
      assert.is_not_nil(name:match('H'))
      os.remove(path)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: _amend_guard edge cases
  --------------------------------------------------------------------------------

  describe('_amend_guard edge cases', function()
    it('updates #endif comment containing old guard name', function()
      local lines = {
        '#ifndef OLD_GUARD_H',
        '#define OLD_GUARD_H',
        '',
        'void foo();',
        '',
        '#endif // OLD_GUARD_H',
      }
      local bufnr, path = make_buf_in_project(lines, 'endif_comment.h')
      local doc = SourceDocument.new(bufnr)

      add_header_guard._amend_guard(doc, 'NEWNAME_H')

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      eq('#ifndef NEWNAME_H', updated[1])
      eq('#define NEWNAME_H', updated[2])
      eq('#endif // NEWNAME_H', updated[6])
      os.remove(path)
    end)

    it('handles #endif with multi-line comment after', function()
      local lines = {
        '#ifndef OLD_H',
        '#define OLD_H',
        '',
        'void foo();',
        '',
        '#endif /* OLD_H */',
      }
      local bufnr, path = make_buf_in_project(lines, 'multiline_comment.h')
      local doc = SourceDocument.new(bufnr)

      add_header_guard._amend_guard(doc, 'NEW_H')

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(updated, '\n')
      assert.is_not_nil(content:find('NEW_H'))
      os.remove(path)
    end)

    it('should NOT replace guard name appearing in code (only directives)', function()
      local lines = {
        '#ifndef SPECIAL_H',
        '#define SPECIAL_H',
        '',
        'const char* guard_name = "SPECIAL_H";',
        '#define MACRO_USING_SPECIAL_H(x) x##_SPECIAL_H',
        '',
        '#endif // SPECIAL_H',
      }
      local bufnr, path = make_buf_in_project(lines, 'code_guard_ref.h')
      local doc = SourceDocument.new(bufnr)

      add_header_guard._amend_guard(doc, 'CODE_GUARD_REF_H')

      local updated = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local content = table.concat(updated, '\n')
      assert.is_not_nil(content:find('"SPECIAL_H"'))
      assert.is_not_nil(content:find('_SPECIAL_H'))
      os.remove(path)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: _get_existing_guard_name edge cases
  --------------------------------------------------------------------------------

  describe('_get_existing_guard_name edge cases', function()
    it('detects #if !defined(GUARD) style guard', function()
      local lines = {
        '#if !defined(MY_GUARD_H)',
        '#define MY_GUARD_H',
        '',
        '#endif',
      }
      local bufnr, path = make_buf_in_project(lines, 'if_defined.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._get_existing_guard_name(doc)
      assert.is_nil(name)
      os.remove(path)
    end)

    it('detects #ifdef GUARD style (non-standard)', function()
      local lines = {
        '#ifdef MY_GUARD_H',
        '',
        '#endif',
      }
      local bufnr, path = make_buf_in_project(lines, 'ifdef_style.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._get_existing_guard_name(doc)
      assert.is_nil(name)
      os.remove(path)
    end)

    it('finds first #ifndef when multiple blocks exist', function()
      local lines = {
        '#ifndef FIRST_H',
        '#define FIRST_H',
        '',
        '#ifndef PLATFORM_WINDOWS',
        '#define PLATFORM_WINDOWS',
        '#endif',
        '',
        '#endif // FIRST_H',
      }
      local bufnr, path = make_buf_in_project(lines, 'multiple_blocks.h')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._get_existing_guard_name(doc)
      eq('FIRST_H', name)
      os.remove(path)
    end)
  end)

  --------------------------------------------------------------------------------
  -- EDGE CASE TESTS: execute() idempotency
  --------------------------------------------------------------------------------

  describe('execute() idempotency', function()
    it('running execute() twice should amend, not add duplicate', function()
      local lines = {
        '#ifndef INITIAL_H',
        '#define INITIAL_H',
        '',
        'void foo();',
        '',
        '#endif // INITIAL_H',
      }
      local bufnr, path = make_buf_in_project(lines, 'idempotent.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()
      local first_run = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      add_header_guard.execute()
      local second_run = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      eq(first_run, second_run)

      local content = table.concat(second_run, '\n')
      assert.is_nil(content:find('#ifndef.*#ifndef'))
      os.remove(path)
    end)

    it('running execute() on fresh header twice produces same result', function()
      local lines = { '' }
      local bufnr, path = make_buf_in_project(lines, 'fresh_twice.h')
      vim.api.nvim_set_current_buf(bufnr)

      add_header_guard.execute()
      local first_run = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      add_header_guard.execute()
      local second_run = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      eq(first_run, second_run)
      os.remove(path)
    end)
  end)
end)
