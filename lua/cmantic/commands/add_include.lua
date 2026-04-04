--- Add Include command for cmantic.nvim
--- Ported from vscode-cmantic src/commands/addInclude.ts
--- Adds #include directives with smart positioning.

local SourceDocument = require('cmantic.source_document')
local utils = require('cmantic.utils')

local M = {}

--- @param path string The include path (may or may not include delimiters)
--- @return boolean true if system include
local function is_system_include(path)
  if path:match('^<.*>$') then
    return true
  end
  if path:match('^".*"$') then
    return false
  end
  if not path:find('[/\\]') then
    local system_headers = {
      ['algorithm'] = true,
      ['array'] = true,
      ['atomic'] = true,
      ['bitset'] = true,
      ['chrono'] = true,
      ['cmath'] = true,
      ['complex'] = true,
      ['condition_variable'] = true,
      ['deque'] = true,
      ['exception'] = true,
      ['filesystem'] = true,
      ['forward_list'] = true,
      ['fstream'] = true,
      ['functional'] = true,
      ['future'] = true,
      ['initializer_list'] = true,
      ['iomanip'] = true,
      ['ios'] = true,
      ['iosfwd'] = true,
      ['iostream'] = true,
      ['istream'] = true,
      ['iterator'] = true,
      ['limits'] = true,
      ['list'] = true,
      ['locale'] = true,
      ['map'] = true,
      ['memory'] = true,
      ['mutex'] = true,
      ['new'] = true,
      ['numeric'] = true,
      ['optional'] = true,
      ['ostream'] = true,
      ['queue'] = true,
      ['random'] = true,
      ['ratio'] = true,
      ['regex'] = true,
      ['scoped_allocator'] = true,
      ['set'] = true,
      ['shared_mutex'] = true,
      ['sstream'] = true,
      ['stack'] = true,
      ['stdexcept'] = true,
      ['streambuf'] = true,
      ['string'] = true,
      ['string_view'] = true,
      ['system_error'] = true,
      ['thread'] = true,
      ['tuple'] = true,
      ['type_traits'] = true,
      ['typeindex'] = true,
      ['typeinfo'] = true,
      ['unordered_map'] = true,
      ['unordered_set'] = true,
      ['utility'] = true,
      ['valarray'] = true,
      ['variant'] = true,
      ['vector'] = true,
      ['cassert'] = true,
      ['cctype'] = true,
      ['cerrno'] = true,
      ['cfenv'] = true,
      ['cfloat'] = true,
      ['cinttypes'] = true,
      ['climits'] = true,
      ['clocale'] = true,
      ['cmath'] = true,
      ['csetjmp'] = true,
      ['csignal'] = true,
      ['cstdarg'] = true,
      ['cstddef'] = true,
      ['cstdint'] = true,
      ['cstdio'] = true,
      ['cstdlib'] = true,
      ['cstring'] = true,
      ['ctime'] = true,
      ['cuchar'] = true,
      ['cwchar'] = true,
      ['cwctype'] = true,
      ['assert.h'] = true,
      ['ctype.h'] = true,
      ['errno.h'] = true,
      ['fenv.h'] = true,
      ['float.h'] = true,
      ['inttypes.h'] = true,
      ['limits.h'] = true,
      ['locale.h'] = true,
      ['math.h'] = true,
      ['setjmp.h'] = true,
      ['signal.h'] = true,
      ['stdarg.h'] = true,
      ['stddef.h'] = true,
      ['stdint.h'] = true,
      ['stdio.h'] = true,
      ['stdlib.h'] = true,
      ['string.h'] = true,
      ['time.h'] = true,
      ['uchar.h'] = true,
      ['wchar.h'] = true,
      ['wctype.h'] = true,
      ['windows.h'] = true,
      ['pthread.h'] = true,
      ['unistd.h'] = true,
      ['sys/'] = true,
    }
    
    local base = path:match('^([^/\\]+)')
    if system_headers[path] or system_headers[base] then
      return true
    end
  end
  return false
end

--- @param path string The include path
--- @param is_system boolean Whether to use angle brackets
--- @return string The formatted #include directive
local function format_include(path, is_system)
  if path:match('^<.*>$') or path:match('^".*"$') then
    return '#include ' .. path
  end
  
  if is_system then
    return '#include <' .. path .. '>'
  else
    return '#include "' .. path .. '"'
  end
end

function M.execute()
  local bufnr = vim.api.nvim_get_current_buf()
  local doc = SourceDocument.new(bufnr)
  
  vim.ui.input({
    prompt = 'Include path: ',
    completion = 'file_in_path',
    default = '',
  }, function(input)
    if not input or input == '' then
      return
    end
    
    local include_path = vim.trim(input)
    if include_path == '' then
      return
    end
    
    local is_system = is_system_include(include_path)
    local directive = format_include(include_path, is_system)
    
    local included_files = doc:get_included_files()
    local check_path = include_path:match('^<(.+)>$') 
      or include_path:match('^"(.+)"$') 
      or include_path
    
    for _, existing in ipairs(included_files) do
      if existing == check_path then
        utils.notify('File already included: ' .. check_path, 'warn')
        return
      end
    end
    
    local positions = doc:find_position_for_new_include()
    local pos = is_system and positions.system or positions.project
    
    if not pos then
      pos = { line = 0, character = 0 }
    end
    
    doc:insert_lines(pos.line, { directive })
    
    utils.notify('Added: ' .. directive, 'info')
  end)
end

return M
