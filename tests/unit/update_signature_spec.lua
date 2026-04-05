local update_signature = require('cmantic.commands.update_signature')
local SourceDocument = require('cmantic.source_document')
local CSymbol = require('cmantic.c_symbol')
local FunctionSignature = require('cmantic.function_signature')
local utils = require('cmantic.utils')
local eq = assert.are.same

--------------------------------------------------------------------------------
-- Mock infrastructure
--------------------------------------------------------------------------------

local saved = {}
local notify_log

local function mock_notify()
  saved.notify = utils.notify
  notify_log = {}
  utils.notify = function(msg, level)
    table.insert(notify_log, { msg = msg, level = level })
  end
end

--- Create a mock symbol with all methods needed by update_signature.
--- Setting `document` to truthy skips the CSymbol.new wrap on line 20/53.
local function make_symbol(opts)
  opts = opts or {}
  local sym = {
    document = opts.has_document ~= false, -- default true → skip CSymbol.new
    name = opts.name or 'test_func',
    kind = opts.kind or 12, -- Function
    range = opts.range or {
      start = opts.range_start or { line = 0, character = 0 },
      ['end'] = opts.range_end or { line = 0, character = 20 },
    },
  }

  sym.is_function = function()
    if opts.is_function ~= nil then return opts.is_function end
    return true
  end
  sym.is_function_definition = function()
    return opts.is_definition or false
  end
  sym.is_function_declaration = function()
    return opts.is_declaration or false
  end
  sym.find_declaration = function()
    return opts.decl_location
  end
  sym.find_definition = function()
    return opts.def_location
  end
  sym.text = function()
    return opts.text or ''
  end
  sym.true_start = function()
    return opts.true_start or sym.range.start
  end
  sym.declaration_end = function()
    return opts.declaration_end or sym.range['end']
  end
  sym.new_function_declaration = function()
    return opts.new_decl_text or ''
  end
  sym.new_function_definition = function()
    return opts.new_def_text or ''
  end

  return sym
end

--- Create a mock FunctionSignature with a controlled equals() result
local function make_sig(opts)
  opts = opts or {}
  return {
    name = opts.name or 'test_func',
    return_type = opts.return_type or 'void',
    parameters = opts.parameters or '',
    trailing = opts.trailing or '',
    equals = function(_, other)
      if opts.equals ~= nil then return opts.equals end
      if not other then return false end
      return opts.name == other.name
        and opts.parameters == other.parameters
        and opts.return_type == other.return_type
    end,
  }
end

--- Wire up all vim.api and module mocks for a full update_signature scenario
--- @param cfg table with current_bufnr, counterpart_bufnr, current_doc, counterpart_doc, etc.
local function setup_scenario(cfg)
  saved.get_current_buf = vim.api.nvim_get_current_buf
  saved.win_get_cursor = vim.api.nvim_win_get_cursor
  saved.sd_new = SourceDocument.new
  saved.uri_to_bufnr = vim.uri_to_bufnr
  saved.buf_is_loaded = vim.api.nvim_buf_is_loaded
  saved.bufload = vim.fn.bufload

  vim.api.nvim_get_current_buf = function()
    return cfg.current_bufnr or 1
  end
  vim.api.nvim_win_get_cursor = function()
    return cfg.cursor or { 1, 0 }
  end

  local doc_map = {
    [cfg.current_bufnr or 1] = cfg.current_doc,
    [cfg.counterpart_bufnr or 2] = cfg.counterpart_doc,
  }
  SourceDocument.new = function(bufnr)
    return doc_map[bufnr]
  end

  vim.uri_to_bufnr = function(uri)
    return cfg.uri_to_bufnr and cfg.uri_to_bufnr(uri) or (cfg.counterpart_bufnr or 2)
  end
  vim.api.nvim_buf_is_loaded = function()
    return cfg.buf_loaded ~= false
  end
  vim.fn.bufload = function() end
end

local function restore_all()
  if saved.notify then utils.notify = saved.notify end
  if saved.get_current_buf then vim.api.nvim_get_current_buf = saved.get_current_buf end
  if saved.win_get_cursor then vim.api.nvim_win_get_cursor = saved.win_get_cursor end
  if saved.sd_new then SourceDocument.new = saved.sd_new end
  if saved.csym_new then CSymbol.new = saved.csym_new end
  if saved.fs_new then FunctionSignature.new = saved.fs_new end
  if saved.uri_to_bufnr then vim.uri_to_bufnr = saved.uri_to_bufnr end
  if saved.buf_is_loaded then vim.api.nvim_buf_is_loaded = saved.buf_is_loaded end
  if saved.bufload then vim.fn.bufload = saved.bufload end
  saved = {}
  notify_log = nil
end

--------------------------------------------------------------------------------
-- Tests
--------------------------------------------------------------------------------

describe('update_signature', function()
  after_each(function()
    restore_all()
  end)

  -----------------------------------------------------------------------
  -- Precondition checks (guard clauses)
  -----------------------------------------------------------------------
  describe('precondition checks', function()
    it('should notify warn when no symbol at cursor position', function()
      mock_notify()
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return nil end,
        },
      })

      update_signature.execute()

      eq(1, #notify_log)
      eq('No symbol at cursor', notify_log[1].msg)
    end)

    it('should notify warn when symbol is not a function (variable)', function()
      mock_notify()

      local variable_sym = make_symbol({
        kind = 13, -- Variable
        is_function = false,
      })

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return variable_sym end,
        },
      })

      update_signature.execute()

      eq(1, #notify_log)
      eq('Cursor is not on a function', notify_log[1].msg)
    end)

    it('should notify warn when symbol is not a function (class)', function()
      mock_notify()

      local class_sym = make_symbol({
        kind = 5, -- Class
        is_function = false,
      })

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return class_sym end,
        },
      })

      update_signature.execute()

      eq(1, #notify_log)
      eq('Cursor is not on a function', notify_log[1].msg)
    end)

    it('should notify warn when no counterpart location found (nil)', function()
      mock_notify()

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        decl_location = nil,
      })

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
      })

      update_signature.execute()

      eq(1, #notify_log)
      eq('Could not find matching declaration/definition', notify_log[1].msg)
    end)

    it('should notify warn when counterpart location has no uri', function()
      mock_notify()

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        def_location = {
          range = { start = { line = 0, character = 0 } },
          -- no uri field
        },
      })

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return decl_sym end,
        },
      })

      update_signature.execute()

      eq(1, #notify_log)
      eq('Could not find matching declaration/definition', notify_log[1].msg)
    end)

    it('should notify warn when counterpart symbol not found in counterpart doc', function()
      mock_notify()

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        decl_location = {
          uri = 'file:///counterpart.h',
          range = { start = { line = 5, character = 0 } },
        },
      })

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return nil end,
        },
      })

      update_signature.execute()

      eq(1, #notify_log)
      eq('Could not locate counterpart symbol', notify_log[1].msg)
    end)
  end)

  -----------------------------------------------------------------------
  -- Signature comparison
  -----------------------------------------------------------------------
  describe('signature comparison', function()
    it('should notify info when signatures are already identical', function()
      mock_notify()

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar(int x) { }',
        decl_location = {
          uri = 'file:///test.h',
          range = { start = { line = 0, character = 0 } },
        },
      })

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar(int x);',
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 0, character = 16 },
        },
      })

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return decl_sym end,
        },
      })

      -- Mock FunctionSignature to report identical
      saved.fs_new = FunctionSignature.new
      local sig = make_sig({ equals = true })
      FunctionSignature.new = function()
        return sig
      end

      update_signature.execute()

      eq(1, #notify_log)
      eq('Signatures are already synchronized', notify_log[1].msg)
    end)
  end)

  -----------------------------------------------------------------------
  -- Signature update — parameter changes (definition → declaration)
  -----------------------------------------------------------------------
  describe('signature update — parameter changes', function()
    it('should update declaration with changed parameter type (int → double)', function()
      mock_notify()

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar(double x) { }',
        decl_location = {
          uri = 'file:///test.h',
          range = { start = { line = 0, character = 0 } },
        },
        new_decl_text = 'void bar(double x);',
      })

      local decl_true_start = { line = 0, character = 0 }
      local decl_end = { line = 0, character = 17 }

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar(int x);',
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 0, character = 16 },
        },
        true_start = decl_true_start,
        declaration_end = decl_end,
      })

      local captured_range, captured_text
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return decl_sym end,
          replace_text = function(_, range, text)
            captured_range = range
            captured_text = text
          end,
        },
      })

      -- Mock FunctionSignature to report different
      saved.fs_new = FunctionSignature.new
      local call_n = 0
      FunctionSignature.new = function()
        call_n = call_n + 1
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq('void bar(double x);', captured_text)
      eq(decl_true_start, captured_range.start)
      eq(decl_end, captured_range['end'])
      eq(1, #notify_log)
      eq('Signature updated in matching file', notify_log[1].msg)
    end)

    it('should update declaration with added parameter', function()
      mock_notify()

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar(int x, int y) { }',
        decl_location = {
          uri = 'file:///test.h',
          range = { start = { line = 0, character = 0 } },
        },
        new_decl_text = 'void bar(int x, int y);',
      })

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar(int x);',
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 0, character = 16 },
        },
        true_start = { line = 0, character = 0 },
        declaration_end = { line = 0, character = 15 },
      })

      local captured_text
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return decl_sym end,
          replace_text = function(_, range, text)
            captured_text = text
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq('void bar(int x, int y);', captured_text)
    end)

    it('should update declaration with removed parameter', function()
      mock_notify()

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar() { }',
        decl_location = {
          uri = 'file:///test.h',
          range = { start = { line = 0, character = 0 } },
        },
        new_decl_text = 'void bar();',
      })

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar(int x);',
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 0, character = 16 },
        },
        true_start = { line = 0, character = 0 },
        declaration_end = { line = 0, character = 11 },
      })

      local captured_text
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return decl_sym end,
          replace_text = function(_, range, text)
            captured_text = text
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq('void bar();', captured_text)
    end)
  end)

  -----------------------------------------------------------------------
  -- Signature update — parameter name change (declaration → definition)
  -----------------------------------------------------------------------
  describe('signature update — reverse direction', function()
    it('should update definition with changed parameter name', function()
      mock_notify()

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar(int newX);',
        def_location = {
          uri = 'file:///test.cpp',
          range = { start = { line = 5, character = 0 } },
        },
        new_def_text = 'void Foo::bar(int newX) {\n}',
      })

      local def_true_start = { line = 5, character = 0 }
      local def_range_end = { line = 7, character = 1 }

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar(int oldX) {\n}',
        range = {
          start = { line = 5, character = 0 },
          ['end'] = def_range_end,
        },
        true_start = def_true_start,
      })

      local captured_range, captured_text
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return decl_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return def_sym end,
          replace_text = function(_, range, text)
            captured_range = range
            captured_text = text
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq('void Foo::bar(int newX) {\n}', captured_text)
      -- For definition update, range is true_start → range['end']
      eq(def_true_start, captured_range.start)
      eq(def_range_end, captured_range['end'])
    end)
  end)

  -----------------------------------------------------------------------
  -- Signature update — return type changes
  -----------------------------------------------------------------------
  describe('signature update — return type', function()
    it('should update declaration with changed return type (int → void)', function()
      mock_notify()

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar() { }',
        decl_location = {
          uri = 'file:///test.h',
          range = { start = { line = 0, character = 0 } },
        },
        new_decl_text = 'void bar();',
      })

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'int bar();',
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 0, character = 10 },
        },
        true_start = { line = 0, character = 0 },
        declaration_end = { line = 0, character = 9 },
      })

      local captured_text
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return decl_sym end,
          replace_text = function(_, range, text)
            captured_text = text
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq('void bar();', captured_text)
      eq(1, #notify_log)
      eq('Signature updated in matching file', notify_log[1].msg)
    end)

    it('should update definition with changed return type (void → double)', function()
      mock_notify()

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'double bar(int x);',
        def_location = {
          uri = 'file:///test.cpp',
          range = { start = { line = 3, character = 0 } },
        },
        new_def_text = 'double Foo::bar(int x) {\n}',
      })

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'int Foo::bar(int x) {\n  return 0;\n}',
        range = {
          start = { line = 3, character = 0 },
          ['end'] = { line = 5, character = 1 },
        },
        true_start = { line = 3, character = 0 },
      })

      local captured_text
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return decl_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return def_sym end,
          replace_text = function(_, range, text)
            captured_text = text
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq('double Foo::bar(int x) {\n}', captured_text)
    end)
  end)

  -----------------------------------------------------------------------
  -- Signature update — qualifiers (const, noexcept)
  -----------------------------------------------------------------------
  describe('signature update — qualifiers', function()
    it('should update when const qualifier added to definition', function()
      mock_notify()

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'int Foo::getValue() const { return m_val; }',
        decl_location = {
          uri = 'file:///test.h',
          range = { start = { line = 2, character = 4 } },
        },
        new_decl_text = 'int getValue() const;',
      })

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'int getValue();',
        range = {
          start = { line = 2, character = 4 },
          ['end'] = { line = 2, character = 19 },
        },
        true_start = { line = 2, character = 4 },
        declaration_end = { line = 2, character = 18 },
      })

      local captured_text
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return decl_sym end,
          replace_text = function(_, range, text)
            captured_text = text
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq('int getValue() const;', captured_text)
    end)

    it('should update when noexcept qualifier added to declaration', function()
      mock_notify()

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void safeOp() noexcept;',
        def_location = {
          uri = 'file:///test.cpp',
          range = { start = { line = 10, character = 0 } },
        },
        new_def_text = 'void safeOp() noexcept {\n}',
      })

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void safeOp() {\n}',
        range = {
          start = { line = 10, character = 0 },
          ['end'] = { line = 11, character = 1 },
        },
        true_start = { line = 10, character = 0 },
      })

      local captured_text
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return decl_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return def_sym end,
          replace_text = function(_, range, text)
            captured_text = text
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq('void safeOp() noexcept {\n}', captured_text)
    end)
  end)

  -----------------------------------------------------------------------
  -- Empty text generation
  -----------------------------------------------------------------------
  describe('empty text generation', function()
    it('should notify warn when generated declaration text is empty', function()
      mock_notify()

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar() { }',
        decl_location = {
          uri = 'file:///test.h',
          range = { start = { line = 0, character = 0 } },
        },
        new_decl_text = '', -- empty → should trigger warning
      })

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar();',
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 0, character = 11 },
        },
      })

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return decl_sym end,
          replace_text = function() end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq(1, #notify_log)
      eq('Could not generate updated signature', notify_log[1].msg)
    end)

    it('should notify warn when generated definition text is empty', function()
      mock_notify()

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar();',
        def_location = {
          uri = 'file:///test.cpp',
          range = { start = { line = 0, character = 0 } },
        },
        new_def_text = '', -- empty → should trigger warning
      })

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar() { }',
        range = {
          start = { line = 0, character = 0 },
          ['end'] = { line = 0, character = 20 },
        },
      })

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return decl_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return def_sym end,
          replace_text = function() end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq(1, #notify_log)
      eq('Could not generate updated signature', notify_log[1].msg)
    end)
  end)

  -----------------------------------------------------------------------
  -- Text replacement ranges
  -----------------------------------------------------------------------
  describe('text replacement ranges', function()
    it('should use true_start → declaration_end for declaration replacement', function()
      mock_notify()

      local true_start = { line = 0, character = 4 }
      local decl_end = { line = 0, character = 22 }

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar(double x) { }',
        decl_location = {
          uri = 'file:///test.h',
          range = { start = { line = 0, character = 4 } },
        },
        new_decl_text = 'void bar(double x);',
      })

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = '    void bar(int x);',
        range = {
          start = { line = 0, character = 4 },
          ['end'] = { line = 0, character = 23 },
        },
        true_start = true_start,
        declaration_end = decl_end,
      })

      local captured_range
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return decl_sym end,
          replace_text = function(_, range, text)
            captured_range = range
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq(true_start, captured_range.start)
      eq(decl_end, captured_range['end'])
    end)

    it('should use true_start → range.end for definition replacement', function()
      mock_notify()

      local def_true_start = { line = 5, character = 0 }
      local def_range_end = { line = 7, character = 1 }

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar(int x);',
        def_location = {
          uri = 'file:///test.cpp',
          range = { start = { line = 5, character = 0 } },
        },
        new_def_text = 'void Foo::bar(int x) {\n}',
      })

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar(double x) {\n}',
        range = {
          start = { line = 5, character = 0 },
          ['end'] = def_range_end,
        },
        true_start = def_true_start,
      })

      local captured_range
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return decl_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return def_sym end,
          replace_text = function(_, range, text)
            captured_range = range
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq(def_true_start, captured_range.start)
      eq(def_range_end, captured_range['end'])
    end)

    it('should fall back to range.end when declaration_end is absent', function()
      mock_notify()

      local range_end = { line = 0, character = 16 }

      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar() { }',
        decl_location = {
          uri = 'file:///test.h',
          range = { start = { line = 0, character = 0 } },
        },
        new_decl_text = 'void bar();',
      })

      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar(int);',
        range = {
          start = { line = 0, character = 0 },
          ['end'] = range_end,
        },
        true_start = { line = 0, character = 0 },
      })
      decl_sym.declaration_end = nil

      local captured_range
      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
        counterpart_doc = {
          get_symbol_at_position = function() return decl_sym end,
          replace_text = function(_, range, text)
            captured_range = range
          end,
        },
      })

      saved.fs_new = FunctionSignature.new
      FunctionSignature.new = function()
        return make_sig({ equals = false })
      end

      update_signature.execute()

      eq(range_end, captured_range['end'])
    end)
  end)

  -----------------------------------------------------------------------
  -- Direction detection
  -----------------------------------------------------------------------
  describe('direction detection', function()
    it('should use find_declaration when cursor is on a definition', function()
      mock_notify()

      local find_decl_called = false
      local def_sym = make_symbol({
        is_function = true,
        is_definition = true,
        is_declaration = false,
        text = 'void Foo::bar() { }',
        decl_location = function()
          find_decl_called = true
          return nil
        end,
      })
      def_sym.find_declaration = function()
        find_decl_called = true
        return nil
      end

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return def_sym end,
        },
      })

      update_signature.execute()

      assert.is_true(find_decl_called)
    end)

    it('should use find_definition when cursor is on a declaration', function()
      mock_notify()

      local find_def_called = false
      local decl_sym = make_symbol({
        is_function = true,
        is_definition = false,
        is_declaration = true,
        text = 'void bar();',
      })
      decl_sym.find_definition = function()
        find_def_called = true
        return nil
      end

      setup_scenario({
        current_doc = {
          get_symbol_at_position = function() return decl_sym end,
        },
      })

      update_signature.execute()

      assert.is_true(find_def_called)
    end)
  end)
end)
