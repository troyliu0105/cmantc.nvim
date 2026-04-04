--- Text masking engine for C/C++ source code analysis
--- Ported from vscode-cmantic src/parsing.ts
---
--- Core concept: Replace non-source text (comments, strings, attributes) with spaces,
--- preserving character positions. This makes all subsequent regex matching position-accurate.

local M = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

--- Primitive C/C++ types (including common combinations)
local PRIMITIVE_TYPES = {
  -- Single-word types
  ['void'] = true,
  ['bool'] = true,
  ['char'] = true,
  ['int'] = true,
  ['short'] = true,
  ['long'] = true,
  ['float'] = true,
  ['double'] = true,
  ['signed'] = true,
  ['unsigned'] = true,
  ['_Bool'] = true,
  ['_Complex'] = true,
  ['_Imaginary'] = true,
  ['int8_t'] = true,
  ['int16_t'] = true,
  ['int32_t'] = true,
  ['int64_t'] = true,
  ['uint8_t'] = true,
  ['uint16_t'] = true,
  ['uint32_t'] = true,
  ['uint64_t'] = true,
  ['intptr_t'] = true,
  ['uintptr_t'] = true,
  ['intmax_t'] = true,
  ['uintmax_t'] = true,
  ['size_t'] = true,
  ['ptrdiff_t'] = true,
  ['wchar_t'] = true,
  ['char16_t'] = true,
  ['char32_t'] = true,
  ['char8_t'] = true,
  ['auto'] = true,
}

--- Multi-word type patterns (normalized to lowercase, space-separated)
local MULTI_WORD_TYPES = {
  ['unsigned char'] = true,
  ['signed char'] = true,
  ['unsigned short'] = true,
  ['signed short'] = true,
  ['unsigned int'] = true,
  ['signed int'] = true,
  ['unsigned long'] = true,
  ['signed long'] = true,
  ['long long'] = true,
  ['unsigned long long'] = true,
  ['signed long long'] = true,
  ['long double'] = true,
  ['long int'] = true,
  ['short int'] = true,
}

--------------------------------------------------------------------------------
-- Helper Functions
--------------------------------------------------------------------------------

--- Check if text is nil, empty, or only whitespace
--- @param text string|nil Text to check
--- @return boolean true if blank
function M.is_blank(text)
  if text == nil then
    return true
  end
  return text:match('^%s*$') ~= nil
end

--- Trim leading and trailing whitespace
--- @param text string Text to trim
--- @return string Trimmed text
function M.trim(text)
  if not text then
    return ''
  end
  return text:match('^%s*(.-)%s*$') or ''
end

--- Normalize whitespace: collapse multiple spaces to single, trim edges
--- Preserves intentional spacing (doesn't collapse 'int *' to 'int*')
--- @param text string Text to normalize
--- @return string Normalized text
function M.normalize_whitespace(text)
  if not text then
    return ''
  end
  -- Trim first
  text = M.trim(text)
  -- Collapse multiple spaces to single space
  text = text:gsub('%s+', ' ')
  return text
end

--- Create a string of spaces with given length
--- @param len number Length of space string
--- @return string String of spaces
local function spaces(len)
  return string.rep(' ', len)
end

--------------------------------------------------------------------------------
-- Masking Functions
--------------------------------------------------------------------------------

--- Mask single-line and block comments with spaces (preserving positions)
--- Handles: // comment and /* block comment */
--- @param text string Source text
--- @return string Text with comments replaced by spaces
function M.mask_comments(text)
  if not text then
    return ''
  end

  -- Convert to table of chars for in-place modification
  local chars = {}
  for i = 1, #text do
    chars[i] = text:sub(i, i)
  end

  local i = 1
  local len = #text

  while i <= len do
    -- Check for single-line comment //
    if i < len and chars[i] == '/' and chars[i + 1] == '/' then
      -- Mask until end of line
      local j = i
      while j <= len and chars[j] ~= '\n' do
        chars[j] = ' '
        j = j + 1
      end
      i = j
    -- Check for block comment /*
    elseif i < len and chars[i] == '/' and chars[i + 1] == '*' then
      -- Mask until */
      chars[i] = ' '
      chars[i + 1] = ' '
      i = i + 2
      while i <= len do
        if i < len and chars[i] == '*' and chars[i + 1] == '/' then
          chars[i] = ' '
          chars[i + 1] = ' '
          i = i + 2
          break
        end
        chars[i] = ' '
        i = i + 1
      end
    else
      i = i + 1
    end
  end

  return table.concat(chars)
end

--- Mask C++ raw string literals: R"delim(...)delim"
--- Uses manual scanning since Lua patterns lack backreferences
--- @param text string Source text
--- @return string Text with raw strings replaced by spaces
function M.mask_raw_strings(text)
  if not text then
    return ''
  end

  local chars = {}
  for i = 1, #text do
    chars[i] = text:sub(i, i)
  end

  local i = 1
  local len = #text

  while i <= len do
    -- Look for R"
    if chars[i] == 'R' and i < len and chars[i + 1] == '"' then
      local start = i
      i = i + 2 -- skip R"

      -- Extract delimiter between " and (
      local delim = ''
      while i <= len and chars[i] ~= '(' do
        if chars[i] ~= ' ' then -- delimiters shouldn't have spaces, but be safe
          delim = delim .. chars[i]
        end
        i = i + 1
      end

      -- Now find )delimiter"
      if i <= len and chars[i] == '(' then
        i = i + 1 -- skip (

        -- Search for )delimiter"
        local end_pattern = ')' .. delim .. '"'
        local pattern_len = #end_pattern
        local found = false

        while i <= len - pattern_len + 1 and not found do
          local match = true
          for j = 1, pattern_len do
            if chars[i + j - 1] ~= end_pattern:sub(j, j) then
              match = false
              break
            end
          end

          if match then
            -- Found the end, mask from start to here + pattern_len
            for k = start, i + pattern_len - 1 do
              if k <= len then
                chars[k] = ' '
              end
            end
            i = i + pattern_len
            found = true
          else
            i = i + 1
          end
        end

        -- If not found, just mask from start to current position (incomplete raw string)
        if not found then
          for k = start, len do
            chars[k] = ' '
          end
          i = len + 1
        end
      else
        -- Incomplete raw string, mask what we have
        for k = start, i - 1 do
          chars[k] = ' '
        end
      end
    else
      i = i + 1
    end
  end

  return table.concat(chars)
end

--- Mask double-quoted strings and single-quoted chars with spaces
--- Handles escaped quotes: \" and \'
--- @param text string Source text
--- @return string Text with string/char literals replaced by spaces
function M.mask_quotes(text)
  if not text then
    return ''
  end

  local chars = {}
  for i = 1, #text do
    chars[i] = text:sub(i, i)
  end

  local i = 1
  local len = #text

  while i <= len do
    local c = chars[i]

    -- Check for double-quoted string
    if c == '"' then
      local start = i
      i = i + 1 -- skip opening quote

      while i <= len do
        if chars[i] == '\\' and i < len then
          -- Skip escaped character
          i = i + 2
        elseif chars[i] == '"' then
          -- End of string
          i = i + 1
          break
        else
          i = i + 1
        end
      end

      -- Mask the entire string
      for k = start, i - 1 do
        chars[k] = ' '
      end

    -- Check for single-quoted char
    elseif c == "'" then
      local start = i
      i = i + 1 -- skip opening quote

      while i <= len do
        if chars[i] == '\\' and i < len then
          -- Skip escaped character
          i = i + 2
        elseif chars[i] == "'" then
          -- End of char
          i = i + 1
          break
        else
          i = i + 1
        end
      end

      -- Mask the entire char literal
      for k = start, i - 1 do
        chars[k] = ' '
      end
    else
      i = i + 1
    end
  end

  return table.concat(chars)
end

--- Mask C++11 attributes with spaces: [[nodiscard]], [[deprecated("msg")]]
--- @param text string Source text
--- @return string Text with attributes replaced by spaces
function M.mask_attributes(text)
  if not text then
    return ''
  end

  local chars = {}
  for i = 1, #text do
    chars[i] = text:sub(i, i)
  end

  local i = 1
  local len = #text

  while i <= len do
    -- Look for [[
    if chars[i] == '[' and i < len and chars[i + 1] == '[' then
      local start = i
      local depth = 2 -- We've seen [[
      i = i + 2

      -- Find matching ]]
      while i <= len and depth > 0 do
        if chars[i] == '[' and i < len and chars[i + 1] == '[' then
          -- Nested attribute (rare but possible)
          depth = depth + 2
          i = i + 2
        elseif chars[i] == ']' and i < len and chars[i + 1] == ']' then
          depth = depth - 2
          if depth == 0 then
            i = i + 2
            break
          end
          i = i + 2
        else
          i = i + 1
        end
      end

      -- Mask the attribute
      for k = start, i - 1 do
        chars[k] = ' '
      end
    else
      i = i + 1
    end
  end

  return table.concat(chars)
end

--- Chain all masks in order: comments → raw strings → quotes → attributes
--- This is the primary entry point for all text analysis
--- @param text string Source text
--- @return string Text with all non-source elements replaced by spaces
function M.mask_non_source_text(text)
  if not text then
    return ''
  end

  -- Order matters: comments first (they may contain quote-like chars)
  text = M.mask_comments(text)
  -- Then raw strings (they contain " which would confuse mask_quotes)
  text = M.mask_raw_strings(text)
  -- Then regular strings and chars
  text = M.mask_quotes(text)
  -- Finally attributes (may contain strings inside)
  text = M.mask_attributes(text)

  return text
end

--------------------------------------------------------------------------------
-- Balanced Bracket Matching
--------------------------------------------------------------------------------

--- Check if character at position is part of a comparison/operator
--- Used for angle bracket disambiguation
--- @param chars table Array of characters
--- @param i number Current position
--- @param char string Current character ('<' or '>')
--- @return boolean true if this is part of an operator (<=, >=, <<, >>, <->)
local function is_operator(chars, i, char)
  local next_char = chars[i + 1]

  if char == '<' then
    -- Check for <=, <<, <- (less common but possible)
    if next_char == '=' or next_char == '<' or next_char == '-' then
      return true
    end
    -- Check for <-> (bidirectional arrow)
    if next_char == '-' and chars[i + 2] == '>' then
      return true
    end
  elseif char == '>' then
    -- Check for >=, >>
    if next_char == '=' or next_char == '>' then
      return true
    end
  end

  return false
end

--- Mask balanced brackets using stack-based approach
--- @param text string Source text
--- @param left string Left delimiter character ('(', '{', '[', '<')
--- @param right string Right delimiter character (')', '}', ']', '>')
--- @param keep_enclosing boolean If true, keep delimiters and mask only content
--- @return string Text with balanced content masked
function M.mask_balanced(text, left, right, keep_enclosing)
  if not text then
    return ''
  end

  local chars = {}
  for i = 1, #text do
    chars[i] = text:sub(i, i)
  end

  local stack = {} -- Stack of opening positions
  local i = 1
  local len = #text

  while i <= len do
    local c = chars[i]

    -- Handle left delimiter
    if c == left then
      -- For angle brackets, check if it's actually an operator
      if left == '<' and is_operator(chars, i, '<') then
        i = i + 1
      else
        table.insert(stack, i)
        if not keep_enclosing then
          chars[i] = ' '
        end
        i = i + 1
      end

    -- Handle right delimiter
    elseif c == right then
      -- For angle brackets, check if it's actually an operator
      if right == '>' and is_operator(chars, i, '>') then
        i = i + 1
      elseif #stack > 0 then
        local start_pos = table.remove(stack)
        -- Mask content between start_pos and i
        if keep_enclosing then
          -- Mask only content between delimiters
          for k = start_pos + 1, i - 1 do
            chars[k] = ' '
          end
        else
          -- Mask everything including delimiters
          for k = start_pos, i do
            chars[k] = ' '
          end
        end
        i = i + 1
      else
        -- Unmatched right delimiter, skip
        i = i + 1
      end

    else
      i = i + 1
    end
  end

  -- Note: Any unmatched left delimiters remain in stack
  -- We don't mask them as they might be intentional or in incomplete code

  return table.concat(chars)
end

--- Mask balanced parentheses
--- @param text string Source text
--- @param keep_enclosing boolean If true, keep () and mask only content
--- @return string Text with parentheses content masked
function M.mask_parentheses(text, keep_enclosing)
  return M.mask_balanced(text, '(', ')', keep_enclosing)
end

--- Mask balanced braces
--- @param text string Source text
--- @param keep_enclosing boolean If true, keep {} and mask only content
--- @return string Text with braces content masked
function M.mask_braces(text, keep_enclosing)
  return M.mask_balanced(text, '{', '}', keep_enclosing)
end

--- Mask balanced brackets
--- @param text string Source text
--- @param keep_enclosing boolean If true, keep [] and mask only content
--- @return string Text with brackets content masked
function M.mask_brackets(text, keep_enclosing)
  return M.mask_balanced(text, '[', ']', keep_enclosing)
end

--- Mask balanced angle brackets with disambiguation
--- Distinguishes < from <=, << and > from >=, >>
--- @param text string Source text
--- @param keep_enclosing boolean If true, keep <> and mask only content
--- @return string Text with angle brackets content masked
function M.mask_angle_brackets(text, keep_enclosing)
  return M.mask_balanced(text, '<', '>', keep_enclosing)
end

--------------------------------------------------------------------------------
-- Parameter Processing
--------------------------------------------------------------------------------

--- Strip default parameter values from a parameter list
--- Example: "int x = 5, string y = "hello"" → "int x, string y"
--- @param params_text string Parameter list text
--- @return string Parameters without default values
function M.strip_default_values(params_text)
  if not params_text or M.is_blank(params_text) then
    return params_text or ''
  end

  -- First mask nested structures to safely split on commas
  local masked = M.mask_non_source_text(params_text)
  masked = M.mask_parentheses(masked, false)
  masked = M.mask_angle_brackets(masked, false)
  masked = M.mask_braces(masked, false)
  masked = M.mask_brackets(masked, false)

  -- Split on commas, but use original text for extraction
  local params = {}
  local current_start = 1
  local i = 1

  while i <= #params_text do
    if masked:sub(i, i) == ',' then
      table.insert(params, params_text:sub(current_start, i - 1))
      current_start = i + 1
    end
    i = i + 1
  end
  -- Don't forget the last parameter
  if current_start <= #params_text then
    table.insert(params, params_text:sub(current_start))
  end

  -- Process each parameter to strip default value
  local result = {}
  for _, param in ipairs(params) do
    param = M.trim(param)
    if param ~= '' then
      -- Find first unmasked '=' (outside of strings, brackets, etc.)
      local param_masked = M.mask_non_source_text(param)
      param_masked = M.mask_parentheses(param_masked, false)
      param_masked = M.mask_angle_brackets(param_masked, false)
      param_masked = M.mask_braces(param_masked, false)

      local eq_pos = param_masked:find('=', 1, true)
      if eq_pos then
        -- Keep only the part before '='
        param = M.trim(param:sub(1, eq_pos - 1))
      end

      table.insert(result, param)
    end
  end

  return table.concat(result, ', ')
end

--- Extract parameter types from a parameter list string
--- @param params_text string Parameter list text (e.g., "int x, const string& y")
--- @return table Array of type strings
function M.get_parameter_types(params_text)
  if not params_text or M.is_blank(params_text) then
    return {}
  end

  -- Strip default values first
  local cleaned = M.strip_default_values(params_text)

  -- Mask nested structures to safely split on commas
  local masked = M.mask_non_source_text(cleaned)
  masked = M.mask_parentheses(masked, false)
  masked = M.mask_angle_brackets(masked, false)
  masked = M.mask_braces(masked, false)

  -- Split on commas
  local params = {}
  local current_start = 1
  local i = 1

  while i <= #cleaned do
    if masked:sub(i, i) == ',' then
      table.insert(params, cleaned:sub(current_start, i - 1))
      current_start = i + 1
    end
    i = i + 1
  end
  if current_start <= #cleaned then
    table.insert(params, cleaned:sub(current_start))
  end

  -- Extract type from each parameter
  local types = {}
  for _, param in ipairs(params) do
    param = M.trim(param)
    if param ~= '' then
      -- The type is everything except the last word (parameter name)
      -- But we need to handle pointers, references, arrays

      -- Mask brackets to handle array declarations like int arr[10]
      local param_masked = M.mask_non_source_text(param)
      param_masked = M.mask_brackets(param_masked, false)

      -- Find the parameter name (last word before any array brackets)
      -- Work backwards from the end
      local j = #param
      local name_end = j

      -- Skip trailing whitespace
      while j >= 1 and param_masked:sub(j, j):match('%s') do
        j = j - 1
      end
      name_end = j

      -- Skip array brackets if present (already masked, look in original)
      while j >= 1 and param_masked:sub(j, j) == ' ' do
        -- Check if this is actually a bracket in original
        if param:sub(j, j) == ']' then
          -- Find matching [
          local bracket_depth = 1
          j = j - 1
          while j >= 1 and bracket_depth > 0 do
            if param:sub(j, j) == ']' then
              bracket_depth = bracket_depth + 1
            elseif param:sub(j, j) == '[' then
              bracket_depth = bracket_depth - 1
            end
            j = j - 1
          end
          -- Skip whitespace before [
          while j >= 1 and param_masked:sub(j, j):match('%s') do
            j = j - 1
          end
          name_end = j
        else
          break
        end
      end

      -- Find start of parameter name (identifier)
      while j >= 1 and not param_masked:sub(j, j):match('%s') do
        j = j - 1
      end
      local name_start = j + 1

      -- Handle pointer/reference modifiers attached to name
      -- e.g., "int* name" vs "int *name" vs "int & name"
      while j >= 1 do
        local c = param_masked:sub(j, j)
        if c == '*' or c == '&' or c:match('%s') then
          if c == '*' or c == '&' then
            -- Include the modifier with the name, not the type
            name_start = j + 1
          end
          j = j - 1
        else
          break
        end
      end

      -- Type is everything before name_start
      local type_part = M.trim(param:sub(1, name_start - 1))
      if type_part ~= '' then
        table.insert(types, type_part)
      end
    end
  end

  return types
end

--------------------------------------------------------------------------------
-- Type Checking
--------------------------------------------------------------------------------

--- Check if text matches a primitive C/C++ type
--- Must NOT match if text contains <> (template)
--- Handles multi-word types like "unsigned int", "long long"
--- @param text string Type text to check
--- @return boolean true if primitive type
function M.matches_primitive_type(text)
  if not text or M.is_blank(text) then
    return false
  end

  -- Normalize: lowercase, collapse whitespace
  local normalized = M.normalize_whitespace(text):lower()

  -- Reject if contains template brackets
  if normalized:find('<') or normalized:find('>') then
    return false
  end

  -- Remove pointer/reference modifiers for checking
  normalized = normalized:gsub('[%*&]+', '')
  normalized = normalized:gsub('%s+', ' ')
  normalized = M.trim(normalized)

  -- Check single-word types
  if PRIMITIVE_TYPES[normalized] then
    return true
  end

  -- Check multi-word types
  if MULTI_WORD_TYPES[normalized] then
    return true
  end

  return false
end

return M
