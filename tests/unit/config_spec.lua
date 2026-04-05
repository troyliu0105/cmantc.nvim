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
  end)
end)
