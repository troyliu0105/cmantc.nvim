local config = require('cmantic.config')
local eq = assert.are.same

local saved_values

describe('config', function()
  before_each(function()
    saved_values = vim.deepcopy(config.values)
    config.values.case_style = 'camelCase'
  end)

  after_each(function()
    config.values = saved_values
  end)

  describe('defaults', function()
    it('has header_extensions', function()
      eq({ 'h', 'hpp', 'hh', 'hxx' }, config.header_extensions())
    end)
    it('has source_extensions', function()
      eq({ 'c', 'cpp', 'cc', 'cxx' }, config.source_extensions())
    end)

    it('has default c_curly_brace_function = new_line', function()
      eq('new_line', config.values.c_curly_brace_function)
    end)

    it('has default cpp_curly_brace_function = new_line_for_ctors', function()
      eq('new_line_for_ctors', config.values.cpp_curly_brace_function)
    end)

    it('has default cpp_curly_brace_namespace = auto', function()
      eq('auto', config.values.cpp_curly_brace_namespace)
    end)

    it('has default case_style = camelCase', function()
      eq('camelCase', config.values.case_style)
    end)

    it('has default generate_namespaces = true', function()
      eq(true, config.values.generate_namespaces)
    end)

    it('has default bool_getter_is_prefix = false', function()
      eq(false, config.values.bool_getter_is_prefix)
    end)

    it('has default getter_definition_location = inline', function()
      eq('inline', config.values.getter_definition_location)
    end)

    it('has default setter_definition_location = inline', function()
      eq('inline', config.values.setter_definition_location)
    end)

    it('has default resolve_types = false', function()
      eq(false, config.values.resolve_types)
    end)

    it('has default braced_initialization = false', function()
      eq(false, config.values.braced_initialization)
    end)

    it('has default use_explicit_this_pointer = false', function()
      eq(false, config.values.use_explicit_this_pointer)
    end)

    it('has default friend_comparison_operators = false', function()
      eq(false, config.values.friend_comparison_operators)
    end)

    it('has default header_guard_style = define', function()
      eq('define', config.values.header_guard_style)
    end)

    it('has default header_guard_format = ${FILE_NAME}_${EXT}', function()
      eq('${FILE_NAME}_${EXT}', config.values.header_guard_format)
    end)

    it('has default reveal_new_definition = true', function()
      eq(true, config.values.reveal_new_definition)
    end)

    it('has default always_move_comments = true', function()
      eq(true, config.values.always_move_comments)
    end)

    it('has default alert_level = info', function()
      eq('info', config.values.alert_level)
    end)
  end)

  describe('merge', function()
    it('overrides specific values', function()
      config.merge({ case_style = 'snake_case' })
      eq('snake_case', config.values.case_style)
    end)

    it('preserves non-merged values', function()
      local orig_style = config.values.header_guard_style
      config.merge({ case_style = 'snake_case' })
      eq(orig_style, config.values.header_guard_style)
    end)

    it('handles merge with empty table (no-op)', function()
      local before = vim.deepcopy(config.values)
      config.merge({})
      eq(before, config.values)
    end)

    it('handles multiple keys in one merge call', function()
      config.merge({
        case_style = 'snake_case',
        resolve_types = true,
        alert_level = 'warn',
      })
      eq('snake_case', config.values.case_style)
      eq(true, config.values.resolve_types)
      eq('warn', config.values.alert_level)
    end)
  end)

  describe('format_to_case_style', function()
    it('camelCase: converts snake_case to camelCase', function()
      config.values.case_style = 'camelCase'
      eq('myVariable', config.format_to_case_style('my_variable'))
    end)

    it('camelCase: converts PascalCase to camelCase', function()
      config.values.case_style = 'camelCase'
      eq('myVariable', config.format_to_case_style('MyVariable'))
    end)

    it('snake_case: converts camelCase to snake_case', function()
      config.values.case_style = 'snake_case'
      eq('my_variable', config.format_to_case_style('myVariable'))
    end)

    it('snake_case: converts PascalCase to snake_case', function()
      config.values.case_style = 'snake_case'
      eq('my_class', config.format_to_case_style('MyClass'))
    end)

    it('PascalCase: converts snake_case to PascalCase', function()
      config.values.case_style = 'PascalCase'
      eq('MyVariable', config.format_to_case_style('my_variable'))
    end)

    it('returns nil for nil input', function()
      eq(nil, config.format_to_case_style(nil))
    end)

    it('returns empty for empty input', function()
      eq('', config.format_to_case_style(''))
    end)

    it('snake_case: HTTPRequest -> http_request', function()
      config.values.case_style = 'snake_case'
      eq('http_request', config.format_to_case_style('HTTPRequest'))
    end)

    it('snake_case: FooBarBaz -> foo_bar_baz', function()
      config.values.case_style = 'snake_case'
      eq('foo_bar_baz', config.format_to_case_style('FooBarBaz'))
    end)

    it('snake_case: A -> a', function()
      config.values.case_style = 'snake_case'
      eq('a', config.format_to_case_style('A'))
    end)

    it('snake_case: getURL -> get_url', function()
      config.values.case_style = 'snake_case'
      eq('get_url', config.format_to_case_style('getURL'))
    end)

    it('snake_case: XMLParser -> xml_parser', function()
      config.values.case_style = 'snake_case'
      eq('xml_parser', config.format_to_case_style('XMLParser'))
    end)

    it('returns input unchanged for unrecognized case_style', function()
      config.values.case_style = 'kebab-case'
      eq('myVariable', config.format_to_case_style('myVariable'))
    end)

    it('camelCase: handles already-lowercase single word', function()
      config.values.case_style = 'camelCase'
      eq('count', config.format_to_case_style('count'))
    end)

    it('camelCase: handles name starting with underscore "_private"', function()
      config.values.case_style = 'camelCase'
      eq('private', config.format_to_case_style('_private'))
    end)

    it('camelCase: handles double underscore "__internal"', function()
      config.values.case_style = 'camelCase'
      eq('internal', config.format_to_case_style('__internal'))
    end)

    it('camelCase: handles name with numbers "test2Case"', function()
      config.values.case_style = 'camelCase'
      eq('test2Case', config.format_to_case_style('test2Case'))
    end)

    it('snake_case: handles name with numbers "test2Case"', function()
      config.values.case_style = 'snake_case'
      eq('test2case', config.format_to_case_style('test2Case'))
    end)
  end)
end)
