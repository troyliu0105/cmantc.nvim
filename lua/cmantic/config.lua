local M = {}

local defaults = {
  header_extensions = { 'h', 'hpp', 'hh', 'hxx' },
  source_extensions = { 'c', 'cpp', 'cc', 'cxx' },
  c_curly_brace_function = 'new_line', -- 'new_line' | 'same_line'
  cpp_curly_brace_function = 'new_line_for_ctors', -- 'new_line' | 'new_line_for_ctors' | 'same_line'
  cpp_curly_brace_namespace = 'auto', -- 'auto' | 'new_line' | 'same_line'
  case_style = 'camelCase', -- 'camelCase' | 'snake_case' | 'PascalCase'
  generate_namespaces = true,
  bool_getter_is_prefix = false,
  getter_definition_location = 'inline', -- 'inline' | 'below_class' | 'source_file'
  setter_definition_location = 'inline', -- 'inline' | 'below_class' | 'source_file'
  resolve_types = false,
  braced_initialization = false,
  use_explicit_this_pointer = false,
  friend_comparison_operators = false,
  header_guard_style = 'define', -- 'define' | 'pragma_once' | 'both'
  header_guard_format = '${FILE_NAME}_${EXT}',
  reveal_new_definition = true,
  always_move_comments = true,
  alert_level = 'info', -- 'error' | 'warn' | 'info'
}

M.values = vim.deepcopy(defaults)

function M.merge(opts)
  M.values = vim.tbl_deep_extend('force', M.values, opts)
end

function M.header_extensions()
  return M.values.header_extensions
end

function M.source_extensions()
  return M.values.source_extensions
end

local function split_into_words(name)
  local words = {}
  for word in name:gmatch('[^_]+') do
    local sub_words = {}
    local current = ''
    for char in word:gmatch('.') do
      if char:match('%u') and #current > 0 and not current:sub(-1):match('%u') then
        table.insert(sub_words, current:lower())
        current = char
      else
        current = current .. char
      end
    end
    if #current > 0 then
      table.insert(sub_words, current:lower())
    end
    for _, w in ipairs(sub_words) do
      table.insert(words, w)
    end
  end
  return words
end

function M.format_to_case_style(name)
  if not name or name == '' then
    return name
  end

  local style = M.values.case_style

  if style == 'camelCase' then
    local words = split_into_words(name)
    if #words == 0 then
      return name
    end
    local result = words[1]
    for i = 2, #words do
      result = result .. words[i]:sub(1, 1):upper() .. words[i]:sub(2)
    end
    return result

  elseif style == 'snake_case' then
    local result = name
    result = result:gsub('(%u)(%u%l)', '%1_%2')
    result = result:gsub('(%l)(%u)', '%1_%2')
    result = result:lower()
    result = result:gsub('[%s%-]+', '_')
    result = result:gsub('_+', '_')
    result = result:gsub('^_', ''):gsub('_$', '')
    return result

  elseif style == 'PascalCase' then
    local words = split_into_words(name)
    if #words == 0 then
      return name
    end
    local result = ''
    for _, word in ipairs(words) do
      result = result .. word:sub(1, 1):upper() .. word:sub(2)
    end
    return result
  end

  return name
end

return M
