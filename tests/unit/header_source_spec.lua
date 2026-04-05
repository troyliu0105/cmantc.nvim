local header_source = require('cmantic.header_source')
local config = require('cmantic.config')
local eq = assert.are.same

describe('header_source', function()
  local temp_files = {}
  local temp_dirs = {}
  local saved_config

  before_each(function()
    header_source.clear_cache()
    saved_config = vim.deepcopy(config.values)
    temp_files = {}
    temp_dirs = {}
  end)

  after_each(function()
    config.values = saved_config
    for _, f in ipairs(temp_files) do
      os.remove(f)
    end
    for i = #temp_dirs, 1, -1 do
      vim.fn.delete(temp_dirs[i], 'd')
    end
  end)

  --- Write content to a file, creating parent dirs as needed.
  --- Tracks file and dirs for cleanup.
  local function write_file(path, content)
    local dir = vim.fn.fnamemodify(path, ':h')
    vim.fn.mkdir(dir, 'p')
    local f = io.open(path, 'w')
    f:write(content or '')
    f:close()
    table.insert(temp_files, path)
    -- track dirs for cleanup (skip if already tracked)
    if not vim.tbl_contains(temp_dirs, dir) then
      table.insert(temp_dirs, dir)
    end
    return path
  end

  --- Build a unique temp base dir for a test
  local function temp_base()
    local base = vim.fn.tempname()
    vim.fn.mkdir(base, 'p')
    -- .git marker prevents tier 3 glob from walking to filesystem root
    vim.fn.mkdir(base .. '/.git', 'p')
    table.insert(temp_dirs, base .. '/.git')
    table.insert(temp_dirs, base)
    return base
  end

  local function uri(path)
    return vim.uri_from_fname(path)
  end

  -- ── Tier 1: Same directory matching ──

  describe('tier 1 — same directory matching', function()
    it('should find .cpp when matching .h in same directory', function()
      local base = temp_base()
      local h = write_file(base .. '/foo.h', '')
      local cpp = write_file(base .. '/foo.cpp', '')
      eq(uri(cpp), header_source.get_matching(uri(h)))
    end)

    it('should find .h when matching .cpp in same directory', function()
      local base = temp_base()
      local h = write_file(base .. '/bar.h', '')
      local cpp = write_file(base .. '/bar.cpp', '')
      eq(uri(h), header_source.get_matching(uri(cpp)))
    end)

    it('should return nil when no matching file exists', function()
      local base = temp_base()
      local h = write_file(base .. '/orphan.h', '')
      eq(nil, header_source.get_matching(uri(h)))
    end)

    it('should match .hpp -> .cpp extension pair', function()
      local base = temp_base()
      local hpp = write_file(base .. '/widget.hpp', '')
      local cpp = write_file(base .. '/widget.cpp', '')
      eq(uri(cpp), header_source.get_matching(uri(hpp)))
    end)

    it('should match .hh -> .cc extension pair', function()
      local base = temp_base()
      local hh = write_file(base .. '/engine.hh', '')
      local cc = write_file(base .. '/engine.cc', '')
      eq(uri(cc), header_source.get_matching(uri(hh)))
    end)
  end)

  -- ── Tier 2: Adjacent directory matching ──

  describe('tier 2 — adjacent directory matching', function()
    it('should find source in parent/src/ when no same-dir match', function()
      local base = temp_base()
      local h = write_file(base .. '/include/mymodule.h', '')
      local cpp = write_file(base .. '/src/mymodule.cpp', '')
      eq(uri(cpp), header_source.get_matching(uri(h)))
    end)

    it('should find header in parent/include/ when no same-dir match', function()
      local base = temp_base()
      local h = write_file(base .. '/include/other.h', '')
      local cpp = write_file(base .. '/src/other.cpp', '')
      eq(uri(h), header_source.get_matching(uri(cpp)))
    end)

    it('should prefer tier 1 (same dir) over tier 2', function()
      local base = temp_base()
      -- tier 1 match: same directory
      local h_same = write_file(base .. '/foo.h', '')
      local cpp_same = write_file(base .. '/foo.cpp', '')
      -- tier 2 match: adjacent dir
      local cpp_adj = write_file(base .. '/src/foo.cpp', '')
      eq(uri(cpp_same), header_source.get_matching(uri(h_same)))
    end)
  end)

  -- ── Cache behavior ──

  describe('cache behavior', function()
    it('should return same result on second call (caching)', function()
      local base = temp_base()
      local h = write_file(base .. '/cached.h', '')
      local cpp = write_file(base .. '/cached.cpp', '')
      local h_uri = uri(h)
      local result1 = header_source.get_matching(h_uri)
      local result2 = header_source.get_matching(h_uri)
      eq(result1, result2)
      eq(uri(cpp), result2)
    end)

    it('should cache result — survives source file deletion', function()
      local base = temp_base()
      local h = write_file(base .. '/survive.h', '')
      local cpp = write_file(base .. '/survive.cpp', '')
      local h_uri = uri(h)
      local cpp_uri = uri(cpp)
      -- first call populates cache
      eq(cpp_uri, header_source.get_matching(h_uri))
      -- delete the source file
      os.remove(cpp)
      -- cached result should still be returned
      eq(cpp_uri, header_source.get_matching(h_uri))
    end)

    it('should clear cache when clear_cache is called', function()
      local base = temp_base()
      local h = write_file(base .. '/fresh.h', '')
      local cpp = write_file(base .. '/fresh.cpp', '')
      local h_uri = uri(h)
      local cpp_uri = uri(cpp)
      eq(cpp_uri, header_source.get_matching(h_uri))
      header_source.clear_cache()
      -- after clear, still returns same result (re-lookup)
      eq(cpp_uri, header_source.get_matching(h_uri))
    end)

    it('clear_cache allows re-discovery after file changes', function()
      local base = temp_base()
      local h = write_file(base .. '/rediscover.h', '')
      local cpp_old = write_file(base .. '/rediscover.cpp', '')
      local h_uri = uri(h)
      eq(uri(cpp_old), header_source.get_matching(h_uri))
      -- delete old source, create a .cc version
      os.remove(cpp_old)
      local cc_new = write_file(base .. '/rediscover.cc', '')
      -- cache still holds old result
      header_source.clear_cache()
      -- now should find .cc
      eq(uri(cc_new), header_source.get_matching(h_uri))
    end)

    it('should return nil for non-matching URI on repeated calls', function()
      local base = temp_base()
      local h = write_file(base .. '/nomatch.h', '')
      local h_uri = uri(h)
      eq(nil, header_source.get_matching(h_uri))
      eq(nil, header_source.get_matching(h_uri))
    end)
  end)

  -- ── Config integration ──

  describe('config integration', function()
    it('should respect custom source_extensions from config', function()
      config.values.source_extensions = { 'cxx' }
      local base = temp_base()
      local h = write_file(base .. '/custom.h', '')
      local cxx = write_file(base .. '/custom.cxx', '')
      eq(uri(cxx), header_source.get_matching(uri(h)))
    end)

    it('should respect custom header_extensions from config', function()
      config.values.header_extensions = { 'hpp' }
      local base = temp_base()
      local hpp = write_file(base .. '/custom.hpp', '')
      local cpp = write_file(base .. '/custom.cpp', '')
      eq(uri(hpp), header_source.get_matching(uri(cpp)))
    end)

    it('should not match extensions outside config', function()
      config.values.source_extensions = { 'cxx' }
      local base = temp_base()
      local h = write_file(base .. '/strict.h', '')
      local cpp = write_file(base .. '/strict.cpp', '')
      local cxx = write_file(base .. '/strict.cxx', '')
      -- should find .cxx, not .cpp
      eq(uri(cxx), header_source.get_matching(uri(h)))
    end)
  end)

  -- ── Edge cases ──

  describe('edge cases', function()
    it('should handle file with multiple dots in name (test.module.cpp)', function()
      local base = temp_base()
      local h = write_file(base .. '/test.module.h', '')
      local cpp = write_file(base .. '/test.module.cpp', '')
      eq(uri(cpp), header_source.get_matching(uri(h)))
    end)

    it('should return nil for nil uri', function()
      eq(nil, header_source.get_matching(nil))
    end)

    it('should return first matching extension in config order', function()
      -- default order: c, cpp, cc, cxx — 'c' is first
      local base = temp_base()
      local h = write_file(base .. '/priority.h', '')
      local c = write_file(base .. '/priority.c', '')
      local cpp = write_file(base .. '/priority.cpp', '')
      eq(uri(c), header_source.get_matching(uri(h)))
    end)
  end)
end)
