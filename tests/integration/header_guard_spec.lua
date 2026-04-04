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
  describe('_format_guard_name', function()
    it('formats guard from filename', function()
      local bufnr = load_fixture_buf('c++/guarded_header.h', 'c')
      local doc = SourceDocument.new(bufnr)
      local name = add_header_guard._format_guard_name(doc)
      eq('GUARDED_HEADER_H', name)
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
  end)
end)
