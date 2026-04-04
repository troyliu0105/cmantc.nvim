--- Core C++ semantic engine for cmantic.nvim
--- Ported from vscode-cmantic src/CSymbol.ts
--- Extends SourceSymbol with document-awareness, declaration/definition detection,
--- specifier detection, template handling, scope computation, and access specifier management.

local SourceSymbol = require('cmantic.source_symbol')
local parse = require('cmantic.parsing')
local utils = require('cmantic.utils')
local config = require('cmantic.config')

local M = {}
M.__index = M
setmetatable(M, { __index = SourceSymbol })

local AccessLevel = utils.AccessLevel

--------------------------------------------------------------------------------
-- Constructor and Text Access
--------------------------------------------------------------------------------

--- Create a new CSymbol instance
--- @param symbol table Raw LSP DocumentSymbol
--- @param document table SourceDocument with get_text(range) and offset_at(position) methods
--- @return table CSymbol instance
function M.new(symbol, document)
  -- Initialize as SourceSymbol first
  local self = SourceSymbol.new(symbol, document.uri, symbol.parent)
  -- Override metatable to CSymbol
  setmetatable(self, M)

  -- Store document reference
  self.document = document

  -- Cache fields
  self._parsable_text = nil
  self._access_specifiers = nil
  self._true_start = nil

  return self
end

--- Get text from document for this symbol's range
--- @return string Text content of this symbol
function M:text()
  return self.document:get_text(self.range)
end

--- Lazy-compute masked text with non-source elements replaced by spaces
--- @return string Masked text for safe regex matching
function M:get_parsable_text()
  if not self._parsable_text then
    self._parsable_text = parse.mask_non_source_text(self:text())
  end
  return self._parsable_text
end

--- Get masked text from range start to selection range start
--- This is the "leading text" before the symbol's name/identifier
--- @return string Masked leading text
function M:parsable_leading_text()
  local parsable = self:get_parsable_text()
  -- Calculate offset of selection_range.start relative to range.start
  local offset = self.document:offset_at(self.selection_range.start)
    - self.document:offset_at(self.range.start)
  if offset > 0 and offset <= #parsable then
    return parsable:sub(1, offset)
  end
  return ''
end

--- Get masked text from selection range end to range end
--- This is the "trailing text" after the symbol's name/identifier
--- @return string Masked trailing text
function M:parsable_trailing_text()
  local parsable = self:get_parsable_text()
  -- Calculate offset of selection_range.end relative to range.start
  local offset = self.document:offset_at(self.selection_range['end'])
    - self.document:offset_at(self.range.start)
  if offset >= 0 and offset < #parsable then
    return parsable:sub(offset + 1)
  end
  return ''
end

--------------------------------------------------------------------------------
-- Declaration/Definition Detection
--------------------------------------------------------------------------------

--- Check if this is a function declaration (not a definition)
--- A declaration does NOT have a body (no { } block)
--- @return boolean
function M:is_function_declaration()
  if not self:is_function() then
    return false
  end

  local text = self:get_parsable_text()

  -- Check if it ends with } followed by optional ;
  if text:match('}%s*;*$') then
    return false
  end

  -- Check for deleted/defaulted functions
  if self:is_deleted_or_defaulted() then
    return false
  end

  -- Check for pure virtual
  if self:is_pure_virtual() then
    return false
  end

  return true
end

--- Check if this is a function definition (has a body)
--- @return boolean
function M:is_function_definition()
  if not self:is_function() then
    return false
  end

  local text = self:get_parsable_text()

  -- Must end with } followed by optional ;
  if not text:match('}%s*;*$') then
    return false
  end

  -- Check for deleted/defaulted functions (they have = delete/default, not a real body)
  if self:is_deleted_or_defaulted() then
    return false
  end

  -- Check for pure virtual
  if self:is_pure_virtual() then
    return false
  end

  return true
end

--------------------------------------------------------------------------------
-- Specifier Detection
--------------------------------------------------------------------------------

--- Check if this symbol has the 'virtual' keyword or override/final specifier
--- @return boolean
function M:is_virtual()
  local leading = self:parsable_leading_text()
  -- Check for virtual keyword with word boundary
  if leading:match('%f[%w]virtual%f[%W]') then
    return true
  end

  -- Also check trailing text for override/final (which imply virtual)
  local trailing = self:parsable_trailing_text()
  if trailing:match('%f[%w]override%f[%W]') or trailing:match('%f[%w]final%f[%W]') then
    return true
  end

  return false
end

--- Check if this symbol has the 'inline' keyword
--- @return boolean
function M:is_inline()
  local leading = self:parsable_leading_text()
  return leading:match('%f[%w]inline%f[%W]') ~= nil
end

--- Check if this symbol has the 'constexpr' keyword
--- @return boolean
function M:is_constexpr()
  local leading = self:parsable_leading_text()
  return leading:match('%f[%w]constexpr%f[%W]') ~= nil
end

--- Check if this symbol has the 'consteval' keyword
--- @return boolean
function M:is_consteval()
  local leading = self:parsable_leading_text()
  return leading:match('%f[%w]consteval%f[%W]') ~= nil
end

--- Check if this symbol has the 'static' keyword
--- Overrides parent's implementation with document-aware check
--- @return boolean
function M:is_static()
  local leading = self:parsable_leading_text()
  return leading:match('%f[%w]static%f[%W]') ~= nil
end

--- Check if this symbol has the 'const' qualifier
--- Must mask angle brackets first to avoid matching inside templates
--- @return boolean
function M:is_const()
  local leading = self:parsable_leading_text()
  -- Mask angle brackets to avoid false positives from template parameters
  local masked = parse.mask_angle_brackets(leading, true)
  -- Look for const keyword, but not const* or const& patterns without space
  return masked:match('%f[%w]const%f[%W]') ~= nil
end

--- Check if this is a pointer type (contains * in leading text)
--- Must mask angle brackets first
--- @return boolean
function M:is_pointer()
  local leading = self:parsable_leading_text()
  -- Mask angle brackets to avoid matching inside templates
  local masked = parse.mask_angle_brackets(leading, true)
  return masked:find('%*') ~= nil
end

--- Check if this is a reference type (contains & in leading text)
--- Must mask angle brackets first
--- @return boolean
function M:is_reference()
  local leading = self:parsable_leading_text()
  -- Mask angle brackets to avoid matching inside templates
  local masked = parse.mask_angle_brackets(leading, true)
  -- Need to be careful: && is rvalue reference, & is lvalue reference
  return masked:find('%f[&]&') ~= nil
end

--- Check if this is a template (text starts with 'template')
--- @return boolean
function M:is_template()
  local text = self:text()
  return text:match('^%s*template') ~= nil
end

--- Check if this is a pure virtual function (= 0)
--- @return boolean
function M:is_pure_virtual()
  if not self:is_virtual() then
    return false
  end
  local text = self:get_parsable_text()
  return text:match('=%s*0%s*;?$') ~= nil
end

--- Check if this function is deleted or defaulted (= delete or = default)
--- @return boolean
function M:is_deleted_or_defaulted()
  local text = self:get_parsable_text()
  return text:match('=%s*delete%s*;?$') ~= nil or text:match('=%s*default%s*;?$') ~= nil
end

--------------------------------------------------------------------------------
-- Template Handling
--------------------------------------------------------------------------------

--- Find template statements before this symbol
--- clangd ranges don't include template<> prefix, so we need to look backwards
--- @param remove_default_args boolean If true, strip default type arguments
--- @return string Template statement(s) or empty string
function M:template_statements(remove_default_args)
  local lines = self.document:get_lines()
  if not lines then
    return ''
  end

  local start_line = self.range.start.line
  local start_char = self.range.start.character

  -- Walk backwards line by line
  local template_lines = {}
  local line_idx = start_line

  while line_idx >= 0 do
    local line = lines[line_idx + 1] or '' -- Lua is 1-indexed
    local check_start = (line_idx == start_line) and start_char or #line
    local text_to_check = line:sub(1, check_start)
    local masked = parse.mask_non_source_text(text_to_check)

    -- Look for template< at the end
    local template_start = masked:find('template%s*<')
    if template_start then
      -- Found template<, now find the complete template statement
      local template_text = self:_extract_template_statement(lines, line_idx, template_start)
      if template_text then
        if remove_default_args then
          template_text = self:_remove_template_default_args(template_text)
        end
        table.insert(template_lines, 1, template_text)
      end
    else
      -- Check if line is just whitespace (continue looking back)
      if not masked:match('^%s*$') then
        -- Non-whitespace, non-template content - stop looking
        break
      end
    end
    line_idx = line_idx - 1
  end

  return table.concat(template_lines, '\n')
end

--- Extract complete template statement starting from a position
--- @param lines table Array of lines
--- @param start_line number 0-indexed line number
--- @param start_char number Character position of 'template'
--- @return string|nil Complete template statement or nil
function M:_extract_template_statement(lines, start_line, start_char)
  local line = lines[start_line + 1] or ''
  local text = line:sub(start_char)

  -- Find the matching > for the template<
  local depth = 0
  local found_open = false
  local result = {}

  for i = 1, #text do
    local c = text:sub(i, i)
    if c == '<' then
      depth = depth + 1
      found_open = true
    elseif c == '>' then
      depth = depth - 1
      if found_open and depth == 0 then
        -- Found the closing >
        return parse.trim(text:sub(1, i))
      end
    end
  end

  -- Template spans multiple lines - collect until we find matching >
  table.insert(result, parse.trim(text))
  local line_idx = start_line + 1

  while line_idx < #lines do
    line_idx = line_idx + 1
    local next_line = lines[line_idx]
    table.insert(result, next_line)

    for i = 1, #next_line do
      local c = next_line:sub(i, i)
      if c == '<' then
        depth = depth + 1
      elseif c == '>' then
        depth = depth - 1
        if found_open and depth == 0 then
          return table.concat(result, '\n')
        end
      end
    end
  end

  return nil
end

--- Remove default arguments from template parameters
--- @param template_text string Template statement
--- @return string Template with defaults removed
function M:_remove_template_default_args(template_text)
  -- Find the < and > positions
  local open_pos = template_text:find('<')
  if not open_pos then
    return template_text
  end

  local prefix = template_text:sub(1, open_pos)
  local params_text = template_text:sub(open_pos + 1)

  -- Find matching >
  local depth = 1
  local close_pos = nil
  for i = 1, #params_text do
    local c = params_text:sub(i, i)
    if c == '<' then
      depth = depth + 1
    elseif c == '>' then
      depth = depth - 1
      if depth == 0 then
        close_pos = i
        break
      end
    end
  end

  if not close_pos then
    return template_text
  end

  local suffix = params_text:sub(close_pos)
  params_text = params_text:sub(1, close_pos - 1)

  -- Strip default arguments from parameters
  params_text = parse.strip_default_values(params_text)

  return prefix .. params_text .. suffix
end

--- Collect template statements from all ancestor scopes
--- @param remove_default_args boolean If true, strip default type arguments
--- @param separator string Separator between template statements (default '\n')
--- @return string Combined template statements
function M:combined_template_statements(remove_default_args, separator)
  separator = separator or '\n'
  local templates = {}

  -- Collect from ancestors
  local ancestors = self:scopes()
  for _, ancestor in ipairs(ancestors) do
    if ancestor.template_statements then
      local ts = ancestor:template_statements(remove_default_args)
      if ts and ts ~= '' then
        table.insert(templates, ts)
      end
    end
  end

  -- Add own template statements
  local own_ts = self:template_statements(remove_default_args)
  if own_ts and own_ts ~= '' then
    table.insert(templates, own_ts)
  end

  return table.concat(templates, separator)
end

--- Extract just the parameter list from template statement
--- @return string Template parameter list like "<T, U>" or empty string
function M:template_parameters()
  local ts = self:template_statements(false)
  if ts == '' then
    return ''
  end

  -- Find < and >
  local open_pos = ts:find('<')
  if not open_pos then
    return ''
  end

  -- Find matching >
  local depth = 0
  local close_pos = nil
  for i = open_pos, #ts do
    local c = ts:sub(i, i)
    if c == '<' then
      depth = depth + 1
    elseif c == '>' then
      depth = depth - 1
      if depth == 0 then
        close_pos = i
        break
      end
    end
  end

  if not close_pos then
    return ''
  end

  -- Extract parameters and normalize
  local params = ts:sub(open_pos + 1, close_pos - 1)
  params = parse.normalize_whitespace(params)

  -- Extract just the parameter names (not types)
  local names = {}
  local masked = parse.mask_non_source_text(params)
  masked = parse.mask_angle_brackets(masked, false)

  -- Split on commas
  local current_start = 1
  for i = 1, #masked do
    if masked:sub(i, i) == ',' then
      local param = parse.trim(params:sub(current_start, i - 1))
      table.insert(names, self:_extract_template_param_name(param))
      current_start = i + 1
    end
  end
  -- Last parameter
  if current_start <= #params then
    local param = parse.trim(params:sub(current_start))
    table.insert(names, self:_extract_template_param_name(param))
  end

  if #names == 0 then
    return ''
  end

  return '<' .. table.concat(names, ', ') .. '>'
end

--- Extract just the name from a template parameter
--- @param param string Full parameter like "typename T = int"
--- @return string Just the name "T"
function M:_extract_template_param_name(param)
  -- Strip default value
  local eq_pos = param:find('=')
  if eq_pos then
    param = parse.trim(param:sub(1, eq_pos - 1))
  end

  -- The name is the last word
  local words = {}
  for word in param:gmatch('%S+') do
    table.insert(words, word)
  end

  if #words > 0 then
    return words[#words]
  end

  return ''
end

--- Return name with template parameters appended
--- @param normalize boolean If true, normalize whitespace
--- @return string Name with template params like "MyClass<T, U>"
function M:templated_name(normalize)
  local name = self.name
  local params = self:template_parameters()

  if params ~= '' then
    name = name .. params
  end

  if normalize then
    name = parse.normalize_whitespace(name)
  end

  return name
end

--------------------------------------------------------------------------------
-- Scope Computation
--------------------------------------------------------------------------------

--- Compute scope string for a position in a target document
--- Walks ancestor scopes and builds prefix like "Namespace::Class::"
--- @param target_doc table Target SourceDocument
--- @param position table Position in target document
--- @param namespaces_only boolean If true, only include namespace scopes
--- @return string Scope prefix string
function M:scope_string(target_doc, position, namespaces_only)
  local scopes = self:scopes()
  local result = {}

  for _, scope in ipairs(scopes) do
    if namespaces_only and not scope:is_namespace() then
      -- Skip non-namespace scopes when namespaces_only is true
    else
      -- Check if target_doc has a matching block at/around position
      local in_scope = self:_is_position_in_scope_block(target_doc, position, scope)

      if not in_scope then
        -- Not inside this scope in target, so we need to add it to prefix
        table.insert(result, scope.name .. '::')
      end
    end
  end

  return table.concat(result)
end

--- Check if a position is inside a scope's block in the target document
--- @param target_doc table Target SourceDocument
--- @param position table Position to check
--- @param scope table Scope to check against
--- @return boolean
function M:_is_position_in_scope_block(target_doc, position, scope)
  -- Get symbols from target document at position
  if not target_doc.get_symbols_at_position then
    return false
  end

  local symbols_at_pos = target_doc:get_symbols_at_position(position)
  for _, sym in ipairs(symbols_at_pos) do
    if sym.name == scope.name and sym:is_class_type() == scope:is_class_type() then
      return true
    end
    -- Check if any parent matches
    local s = sym.parent
    while s do
      if s.name == scope.name and s:is_class_type() == scope:is_class_type() then
        return true
      end
      s = s.parent
    end
  end

  return false
end

--- Return array of all named ancestor scopes (names only, excluding anonymous)
--- @return table Array of scope names
function M:named_scopes()
  local scopes = self:scopes()
  local result = {}

  for _, scope in ipairs(scopes) do
    if not scope:is_anonymous() then
      table.insert(result, scope.name)
    end
  end

  return result
end

--- Return array of all ancestor scopes (including anonymous)
--- @return table Array of all scope SourceSymbols
function M:all_scopes()
  return self:scopes()
end

--------------------------------------------------------------------------------
-- Declaration Formatting
--------------------------------------------------------------------------------

--- Format a function definition from a declaration
--- This is the most complex method - generates a definition string
--- @param target_doc table Target SourceDocument where definition will be inserted
--- @param position table Position in target document
--- @param scope_string string|nil Pre-computed scope string (nil to compute)
--- @param check_for_inline boolean If true, add 'inline' for header files outside class
--- @return string Formatted function definition
function M:format_declaration(target_doc, position, scope_string, check_for_inline)
  -- 1. Get the declaration text from range start to opening { or ;
  local decl_end = self:declaration_end()
  local text = self.document:get_text({
    start = self:true_start(),
    ['end'] = decl_end,
  })

  -- Strip trailing semicolon
  text = text:gsub('%s*;+%s*$', '')

  -- 2. Get parameters, strip default values
  local params = self:_extract_parameters(text)
  if params then
    params = parse.strip_default_values(params)
    text = self:_replace_parameters(text, params)
  end

  -- 3. Compute scope string prefix
  local scope = scope_string
  if not scope then
    scope = self:scope_string(target_doc, position, false)
  end

  -- 4. Strip virtual/override/final/static/explicit/friend from leading text
  local leading = self:parsable_leading_text()
  text = self:_strip_specifiers(text, leading)

  -- 5. Prepend scope string before function name
  if scope ~= '' then
    text = self:_prepend_scope(text, scope)
  end

  -- 6. Add 'inline' keyword if needed
  if check_for_inline then
    local is_header = self:_is_header_file(target_doc.uri)
    local in_class = self:_is_inside_class(target_doc, position)

    if is_header and not in_class and not self:is_inline() then
      text = 'inline ' .. text
    end
  end

  -- 7. Prepend template statements
  local templates = self:combined_template_statements(true, '\n')
  if templates ~= '' then
    text = templates .. '\n' .. text
  end

  -- 8. Format the body opening brace according to config
  local curly_style = self:_get_curly_brace_style(target_doc, position)
  text = self:_format_opening_brace(text, curly_style)

  return text
end

--- Extract parameter list from declaration text
--- @param text string Declaration text
--- @return string|nil Parameter text or nil
function M:_extract_parameters(text)
  -- Find the ( after function name
  local masked = parse.mask_non_source_text(text)

  -- Find opening paren (but not inside template<>)
  local depth = 0
  local paren_start = nil
  for i = 1, #masked do
    local c = masked:sub(i, i)
    if c == '<' then
      depth = depth + 1
    elseif c == '>' then
      depth = depth - 1
    elseif c == '(' and depth == 0 then
      paren_start = i
      break
    end
  end

  if not paren_start then
    return nil
  end

  -- Find matching closing paren
  depth = 1
  local paren_end = nil
  for i = paren_start + 1, #masked do
    local c = masked:sub(i, i)
    if c == '(' then
      depth = depth + 1
    elseif c == ')' then
      depth = depth - 1
      if depth == 0 then
        paren_end = i
        break
      end
    end
  end

  if not paren_end then
    return nil
  end

  return text:sub(paren_start, paren_end)
end

--- Replace parameters in declaration text
--- @param text string Full declaration text
--- @param new_params string New parameter text
--- @return string Text with replaced parameters
function M:_replace_parameters(text, new_params)
  local masked = parse.mask_non_source_text(text)

  -- Find opening paren
  local depth = 0
  local paren_start = nil
  for i = 1, #masked do
    local c = masked:sub(i, i)
    if c == '<' then
      depth = depth + 1
    elseif c == '>' then
      depth = depth - 1
    elseif c == '(' and depth == 0 then
      paren_start = i
      break
    end
  end

  if not paren_start then
    return text
  end

  -- Find matching closing paren
  depth = 1
  local paren_end = nil
  for i = paren_start + 1, #masked do
    local c = masked:sub(i, i)
    if c == '(' then
      depth = depth + 1
    elseif c == ')' then
      depth = depth - 1
      if depth == 0 then
        paren_end = i
        break
      end
    end
  end

  if not paren_end then
    return text
  end

  return text:sub(1, paren_start - 1) .. new_params .. text:sub(paren_end + 1)
end

--- Strip virtual, override, final, static, explicit, friend from text
--- @param text string Declaration text
--- @param leading string Leading text (masked)
--- @return string Text with specifiers stripped
function M:_strip_specifiers(text, leading)
  local keywords = { 'virtual', 'override', 'final', 'static', 'explicit', 'friend' }

  for _, kw in ipairs(keywords) do
    -- Match keyword with word boundaries
    local pattern = '%f[%w]' .. kw .. '%f[%W]%s*'
    text = text:gsub(pattern, '')
  end

  return text
end

--- Prepend scope string before function name
--- @param text string Declaration text
--- @param scope string Scope string like "Namespace::Class::"
--- @return string Text with scope prepended
function M:_prepend_scope(text, scope)
  -- Find the function name position
  local name = self.name
  local masked = parse.mask_non_source_text(text)

  -- Find the name in the text (before the opening paren)
  local paren_pos = masked:find('%(')
  if not paren_pos then
    return text
  end

  -- Search backwards from paren to find name
  local name_end = paren_pos - 1
  while name_end > 0 and masked:sub(name_end, name_end):match('%s') do
    name_end = name_end - 1
  end

  local name_start = name_end
  while name_start > 0 and not masked:sub(name_start, name_start):match('[%s%(<]') do
    name_start = name_start - 1
  end
  name_start = name_start + 1

  -- Insert scope before name
  return text:sub(1, name_start - 1) .. scope .. text:sub(name_start)
end

--- Check if URI is a header file
--- @param uri string File URI
--- @return boolean
function M:_is_header_file(uri)
  local ext = utils.file_extension(uri)
  local header_exts = config.header_extensions()
  for _, h in ipairs(header_exts) do
    if ext == h then
      return true
    end
  end
  return false
end

--- Check if position is inside a class in the target document
--- @param target_doc table Target SourceDocument
--- @param position table Position
--- @return boolean
function M:_is_inside_class(target_doc, position)
  if target_doc.get_symbols_at_position then
    local symbols = target_doc:get_symbols_at_position(position)
    for _, sym in ipairs(symbols) do
      if sym:is_class_type() then
        return true
      end
    end
  end
  return false
end

--- Get curly brace style based on config and context
--- @param target_doc table Target SourceDocument
--- @param position table Position
--- @return string 'new_line', 'same_line'
function M:_get_curly_brace_style(target_doc, position)
  local ext = utils.file_extension(target_doc.uri)
  local in_namespace = self:_is_inside_namespace(target_doc, position)
  local is_ctor = self:is_constructor()

  if ext == 'c' then
    return config.values.c_curly_brace_function
  end

  -- C++ file
  local style = config.values.cpp_curly_brace_function

  if style == 'new_line_for_ctors' and is_ctor then
    return 'new_line'
  end

  if in_namespace and config.values.cpp_curly_brace_namespace == 'new_line' then
    return 'new_line'
  end

  if style == 'new_line' or style == 'new_line_for_ctors' then
    return 'new_line'
  end

  return 'same_line'
end

--- Check if position is inside a namespace
--- @param target_doc table Target SourceDocument
--- @param position table Position
--- @return boolean
function M:_is_inside_namespace(target_doc, position)
  if target_doc.get_symbols_at_position then
    local symbols = target_doc:get_symbols_at_position(position)
    for _, sym in ipairs(symbols) do
      if sym:is_namespace() then
        return true
      end
    end
  end
  return false
end

--- Format opening brace according to style
--- @param text string Text before brace
--- @param style string 'new_line' or 'same_line'
--- @return string Text with opening brace
function M:_format_opening_brace(text, style)
  text = parse.trim(text)

  if style == 'new_line' then
    return text .. '\n{\n}'
  else
    return text .. ' {\n}'
  end
end

--- Generate new function definition from this declaration
--- @param target_doc table Target SourceDocument
--- @param position table Position in target
--- @return string Formatted definition or empty string
function M:new_function_definition(target_doc, position)
  if not self:is_function_declaration() then
    return ''
  end

  return self:format_declaration(target_doc, position, nil, true)
end

--- Generate new function declaration from this definition
--- @return string Formatted declaration or empty string
function M:new_function_declaration()
  if not self:is_function_definition() then
    return ''
  end

  local text = self.document:get_text({
    start = self:true_start(),
    ['end'] = self:declaration_end(),
  })

  text = parse.trim(text)
  text = text .. ';'

  return text
end

--------------------------------------------------------------------------------
-- True Start and Declaration End
--------------------------------------------------------------------------------

--- Get the actual start position including template<> prefix
--- clangd ranges don't include template prefix, so we look backwards
--- @return table Position { line, character }
function M:true_start()
  if self._true_start then
    return self._true_start
  end

  self._true_start = self:_compute_true_start()
  return self._true_start
end

--- Compute the true start position
--- @return table Position
function M:_compute_true_start()
  local lines = self.document:get_lines()
  if not lines then
    return self.range.start
  end

  local start_line = self.range.start.line
  local start_char = self.range.start.character

  -- Walk backwards to find template statements
  local found_template_line = nil
  local found_template_char = nil
  local line_idx = start_line

  while line_idx >= 0 do
    local line = lines[line_idx + 1] or ''
    local check_start = (line_idx == start_line) and start_char or #line
    local text_to_check = line:sub(1, check_start)
    local masked = parse.mask_non_source_text(text_to_check)

    -- Look for template< at the end
    if masked:find('template%s*<') then
      found_template_line = line_idx
      -- Find where template keyword starts
      found_template_char = masked:find('template') - 1
    else
      -- Check if line is just whitespace (continue looking back)
      if not masked:match('^%s*$') then
        -- Non-whitespace, non-template content - stop looking
        break
      end
    end
    line_idx = line_idx - 1
  end

  if found_template_line then
    return { line = found_template_line, character = found_template_char }
  end

  return self.range.start
end

--- Get the position where declaration ends (opening { or ;)
--- @return table Position
function M:declaration_end()
  if self:is_function() then
    local text = self:get_parsable_text()
    -- Find first { or ; outside of strings/comments (already masked)
    local brace_pos = text:find('{')
    local semi_pos = text:find(';')

    if brace_pos and semi_pos then
      -- Return whichever comes first
      local pos = math.min(brace_pos, semi_pos) - 1 -- Convert to 0-indexed position in text
      return self:_offset_to_position(pos)
    elseif brace_pos then
      return self:_offset_to_position(brace_pos - 1)
    elseif semi_pos then
      return self:_offset_to_position(semi_pos - 1)
    end
  end

  return self.range['end']
end

--- Convert character offset in text to LSP position
--- @param offset number Character offset (0-indexed)
--- @return table Position { line, character }
function M:_offset_to_position(offset)
  local lines = self.document:get_lines()
  if not lines then
    return self.range.start
  end

  local start_line = self.range.start.line
  local start_char = self.range.start.character
  local current_line = start_line
  local current_char = start_char

  -- Count characters through lines
  while offset > 0 and current_line < #lines do
    local line_len = #(lines[current_line + 1] or '')
    local remaining_on_line = line_len - current_char

    if offset >= remaining_on_line then
      -- Move to next line
      offset = offset - remaining_on_line - 1 -- -1 for newline
      current_line = current_line + 1
      current_char = 0
    else
      current_char = current_char + offset
      offset = 0
    end
  end

  return { line = current_line, character = current_char }
end

--------------------------------------------------------------------------------
-- Access Specifier Detection
--------------------------------------------------------------------------------

--- Get access specifiers for this class
--- @return table Array of { level = AccessLevel, range = Range }
function M:get_access_specifiers()
  if self._access_specifiers then
    return self._access_specifiers
  end

  self._access_specifiers = {}

  if not self:is_class_type() then
    return self._access_specifiers
  end

  -- Get class body text
  local body_text = self:_get_class_body_text()
  if not body_text or body_text == '' then
    return self._access_specifiers
  end

  -- Mask children symbols to avoid false positives
  local masked = self:_mask_children_symbols(body_text)

  -- Match access specifiers
  local patterns = {
    { pattern = 'public%s*:', level = AccessLevel.public },
    { pattern = 'protected%s*:', level = AccessLevel.protected },
    { pattern = 'private%s*:', level = AccessLevel.private },
  }

  for _, spec in ipairs(patterns) do
    local start = 1
    while true do
      local match_start, match_end = masked:find(spec.pattern, start)
      if not match_start then
        break
      end

      -- Convert to position
      local pos = self:_body_offset_to_position(match_start - 1)
      local end_pos = self:_body_offset_to_position(match_end)

      table.insert(self._access_specifiers, {
        level = spec.level,
        range = {
          start = pos,
          ['end'] = end_pos,
        },
      })

      start = match_end + 1
    end
  end

  -- Sort by position
  table.sort(self._access_specifiers, function(a, b)
    if a.range.start.line ~= b.range.start.line then
      return a.range.start.line < b.range.start.line
    end
    return a.range.start.character < b.range.start.character
  end)

  return self._access_specifiers
end

--- Get class body text (text between { and })
--- @return string|nil Body text or nil
function M:_get_class_body_text()
  local text = self:text()
  local masked = parse.mask_non_source_text(text)

  -- Find opening brace
  local brace_start = masked:find('{')
  if not brace_start then
    return nil
  end

  -- Find matching closing brace
  local depth = 1
  local brace_end = nil
  for i = brace_start + 1, #masked do
    local c = masked:sub(i, i)
    if c == '{' then
      depth = depth + 1
    elseif c == '}' then
      depth = depth - 1
      if depth == 0 then
        brace_end = i
        break
      end
    end
  end

  if not brace_end then
    return nil
  end

  return text:sub(brace_start + 1, brace_end - 1)
end

--- Mask regions occupied by children symbols
--- @param text string Body text
--- @return string Masked text
function M:_mask_children_symbols(text)
  local result = text

  for _, child in ipairs(self.children) do
    -- Get the offset of this child within the body
    local child_start = self:_position_to_body_offset(child.range.start)
    local child_end = self:_position_to_body_offset(child.range['end'])

    if child_start and child_end and child_start >= 1 and child_end <= #result then
      -- Mask this region
      local before = result:sub(1, child_start - 1)
      local after = result:sub(child_end + 1)
      local spaces = string.rep(' ', child_end - child_start + 1)
      result = before .. spaces .. after
    end
  end

  return result
end

--- Convert position to offset within class body
--- @param pos table Position
--- @return number|nil Offset or nil
function M:_position_to_body_offset(pos)
  local lines = self.document:get_lines()
  if not lines then
    return nil
  end

  local body_start_line = self.range.start.line
  local body_start_char = self.range.start.character

  -- Find opening brace position
  local text = self:text()
  local masked = parse.mask_non_source_text(text)
  local brace_offset = masked:find('{')
  if not brace_offset then
    return nil
  end

  -- Calculate offset from range start to body start
  local offset = 0
  for line_idx = 0, pos.line - body_start_line - 1 do
    local line = lines[body_start_line + line_idx + 1] or ''
    offset = offset + #line + 1 -- +1 for newline
  end

  offset = offset + pos.character - body_start_char

  -- Adjust for body start (after {)
  return offset - brace_offset
end

--- Convert offset in body text to position
--- @param offset number Offset in body text
--- @return table Position
function M:_body_offset_to_position(offset)
  local lines = self.document:get_lines()
  if not lines then
    return self.range.start
  end

  -- Find opening brace in the class
  local text = self:text()
  local masked = parse.mask_non_source_text(text)
  local brace_offset = masked:find('{')

  if not brace_offset then
    return self.range.start
  end

  -- Total offset from range start
  local total_offset = brace_offset + offset

  -- Convert to line/character
  local current_line = self.range.start.line
  local current_char = self.range.start.character
  local remaining = total_offset - 1

  while remaining > 0 and current_line < #lines do
    local line = lines[current_line + 1] or ''
    local line_remaining = #line - current_char

    if remaining > line_remaining then
      remaining = remaining - line_remaining - 1 -- -1 for newline
      current_line = current_line + 1
      current_char = 0
    else
      current_char = current_char + remaining
      remaining = 0
    end
  end

  return { line = current_line, character = current_char }
end

--- Find position for a new member function with given access level
--- @param access string AccessLevel value
--- @param relative_name string|nil Name of related function (place after)
--- @return table|nil ProposedPosition or nil
function M:find_position_for_new_member_function(access, relative_name)
  if not self:is_class_type() then
    return nil
  end

  local specifiers = self:get_access_specifiers()

  -- Find the access specifier section
  local target_spec = nil
  for i, spec in ipairs(specifiers) do
    if spec.level == access then
      target_spec = spec
      break
    end
  end

  -- If no specifier found, class uses default access (private for class, public for struct)
  if not target_spec then
    -- Use end of class as default
    local body_end = self:_find_body_end()
    return {
      position = body_end,
      insert_before = false,
    }
  end

  -- Look for existing member with matching name
  if relative_name then
    for _, child in ipairs(self.children) do
      if child.name == relative_name then
        return {
          position = child.range['end'],
          insert_before = false,
        }
      end
    end
  end

  -- Find end of this access section
  local section_end = self:_find_access_section_end(target_spec, specifiers)

  return {
    position = section_end,
    insert_before = false,
  }
end

--- Find the end position of an access section
--- @param target_spec table The access specifier
--- @param specifiers table All specifiers (sorted)
--- @return table Position
function M:_find_access_section_end(target_spec, specifiers)
  -- Find next specifier after this one
  local next_spec = nil
  for _, spec in ipairs(specifiers) do
    if utils.position_before(target_spec.range['end'], spec.range.start) then
      if not next_spec or utils.position_before(spec.range.start, next_spec.range.start) then
        next_spec = spec
      end
    end
  end

  if next_spec then
    -- End is just before next specifier
    return utils.position_before and next_spec.range.start or next_spec.range.start
  end

  -- No next specifier, use end of class body
  return self:_find_body_end()
end

--- Find the position just before the closing brace of the class
--- @return table Position
function M:_find_body_end()
  local lines = self.document:get_lines()
  if not lines then
    return self.range['end']
  end

  local end_line = self.range['end'].line
  local end_char = self.range['end'].character

  -- Look for closing brace on end line
  local line = lines[end_line + 1] or ''
  local brace_pos = line:find('}')
  if brace_pos then
    return { line = end_line, character = brace_pos - 1 }
  end

  return { line = end_line, character = end_char }
end

--------------------------------------------------------------------------------
-- Accessor Name Computation
--------------------------------------------------------------------------------

--- Get getter name for this member variable
--- @return string Getter function name or empty string
function M:getter_name()
  if not self:is_member_variable() then
    return ''
  end

  local base = self:base_name()
  local formatted = config.format_to_case_style(base)

  -- Check if this is a boolean type
  local is_bool = self:_is_bool_type()

  if config.values.bool_getter_is_prefix and is_bool then
    -- Use 'is_' prefix for booleans
    return 'is_' .. formatted
  end

  -- If formatted name differs from original, use it directly
  if formatted ~= base then
    return formatted
  end

  -- Otherwise prefix with 'get_'
  return 'get_' .. formatted
end

--- Get setter name for this member variable
--- @return string Setter function name or empty string
function M:setter_name()
  if not self:is_member_variable() then
    return ''
  end

  local base = self:base_name()
  return 'set_' .. config.format_to_case_style(base)
end

--- Check if this variable has boolean type
--- @return boolean
function M:_is_bool_type()
  local leading = self:parsable_leading_text()
  -- Simple check for bool keyword
  return leading:match('%f[%w]bool%f[%W]') ~= nil
end

--------------------------------------------------------------------------------
-- Utility Methods
--------------------------------------------------------------------------------

--- Get lines from document (convenience wrapper)
--- @return table|nil Array of lines
function M:get_lines()
  return self.document:get_lines()
end

return M
