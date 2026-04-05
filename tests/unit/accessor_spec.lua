local accessor = require('cmantic.accessor')
local config = require('cmantic.config')
local eq = assert.are.same

--- Create a mock CSymbol for member variable testing
--- @param opts table { name, leading_text, is_static, is_pointer, base_name, getter_name, setter_name }
--- @return table Mock CSymbol
local function mock_member_var(opts)
  return {
    name = opts.name or 'value',
    parsable_leading_text = function()
      return opts.leading_text or 'int'
    end,
    is_static = function()
      return opts.is_static or false
    end,
    is_pointer = function()
      return opts.is_pointer or false
    end,
    base_name = function()
      return opts.base_name or opts.name or 'value'
    end,
    getter_name = function()
      return opts.getter_name or 'get_value'
    end,
    setter_name = function()
      return opts.setter_name or 'set_value'
    end,
  }
end

local DEFAULTS = {
  use_explicit_this_pointer = false,
}

--- Restore config defaults after each test
local function restore_config()
  config.merge(DEFAULTS)
end

describe('accessor', function()
  describe('create_getter', function()
    after_each(restore_config)

    it('returns correct name, return_type, parameter, body for int member', function()
      config.merge({ use_explicit_this_pointer = false })
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
        getter_name = 'get_count',
      })
      local getter = accessor.create_getter(mv)

      eq('get_count', getter.name)
      eq('int', getter.return_type)
      eq('', getter.parameter)
      eq('return count;', getter.body)
    end)

    it('adds const qualifier for non-static members', function()
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
        is_static = false,
      })
      local getter = accessor.create_getter(mv)

      eq(' const', getter.qualifier)
    end)

    it('does NOT add const qualifier for static members', function()
      local mv = mock_member_var({
        name = 'instance_count',
        leading_text = 'static int',
        is_static = true,
      })
      local getter = accessor.create_getter(mv)

      eq('', getter.qualifier)
    end)

    it('uses this-> prefix when use_explicit_this_pointer is true', function()
      config.merge({ use_explicit_this_pointer = true })
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
      })
      local getter = accessor.create_getter(mv)

      eq('return this->count;', getter.body)
    end)

    it('does NOT use this-> prefix when use_explicit_this_pointer is false', function()
      config.merge({ use_explicit_this_pointer = false })
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
      })
      local getter = accessor.create_getter(mv)

      eq('return count;', getter.body)
    end)

    it('does NOT use this-> prefix for static members even when use_explicit_this_pointer is true', function()
      config.merge({ use_explicit_this_pointer = true })
      local mv = mock_member_var({
        name = 'instance_count',
        leading_text = 'static int',
        is_static = true,
      })
      local getter = accessor.create_getter(mv)

      eq('return instance_count;', getter.body)
    end)

    it('strips static specifier from return type', function()
      local mv = mock_member_var({
        name = 'instance_count',
        leading_text = 'static int',
        is_static = true,
      })
      local getter = accessor.create_getter(mv)

      eq('int', getter.return_type)
    end)

    it('strips mutable specifier from return type', function()
      local mv = mock_member_var({
        name = 'data',
        leading_text = 'mutable int',
      })
      local getter = accessor.create_getter(mv)

      eq('int', getter.return_type)
    end)

    it('strips constexpr specifier from return type', function()
      local mv = mock_member_var({
        name = 'max_size',
        leading_text = 'constexpr int',
      })
      local getter = accessor.create_getter(mv)

      eq('int', getter.return_type)
    end)

    it('handles complex type like std::string', function()
      local mv = mock_member_var({
        name = 'name',
        leading_text = 'std::string',
        getter_name = 'get_name',
      })
      local getter = accessor.create_getter(mv)

      eq('std::string', getter.return_type)
    end)

    it('handles const reference type', function()
      local mv = mock_member_var({
        name = 'items',
        leading_text = 'const std::vector<int>&',
        getter_name = 'get_items',
      })
      local getter = accessor.create_getter(mv)

      eq('const std::vector<int>&', getter.return_type)
    end)

    it('strips inline specifier from return type', function()
      local mv = mock_member_var({
        name = 'data',
        leading_text = 'inline int',
      })
      local getter = accessor.create_getter(mv)

      eq('int', getter.return_type)
    end)

    it('strips volatile specifier from return type', function()
      local mv = mock_member_var({
        name = 'flag',
        leading_text = 'volatile bool',
      })
      local getter = accessor.create_getter(mv)

      eq('bool', getter.return_type)
    end)

    it('strips register specifier from return type', function()
      local mv = mock_member_var({
        name = 'idx',
        leading_text = 'register int',
      })
      local getter = accessor.create_getter(mv)

      eq('int', getter.return_type)
    end)

    it('strips multiple specifiers from return type', function()
      local mv = mock_member_var({
        name = 'val',
        leading_text = 'static constexpr inline int',
        is_static = true,
      })
      local getter = accessor.create_getter(mv)

      eq('int', getter.return_type)
    end)
  end)

  describe('create_setter', function()
    after_each(restore_config)

    it('returns void return type', function()
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
        base_name = 'count',
        setter_name = 'set_count',
      })
      local setter = accessor.create_setter(mv)

      eq('void', setter.return_type)
    end)

    it('passes primitive type by value', function()
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
        base_name = 'count',
        setter_name = 'set_count',
      })
      local setter = accessor.create_setter(mv)

      eq('int count', setter.parameter)
    end)

    it('uses const Type& for non-primitive, non-pointer types', function()
      local mv = mock_member_var({
        name = 'name',
        leading_text = 'std::string',
        base_name = 'name',
        setter_name = 'set_name',
      })
      local setter = accessor.create_setter(mv)

      eq('const std::string& name', setter.parameter)
    end)

    it('passes pointer type by value', function()
      local mv = mock_member_var({
        name = 'ptr',
        leading_text = 'int*',
        base_name = 'ptr',
        setter_name = 'set_ptr',
        is_pointer = true,
      })
      local setter = accessor.create_setter(mv)

      eq('int* ptr', setter.parameter)
    end)

    it('uses this-> in body when use_explicit_this_pointer is true', function()
      config.merge({ use_explicit_this_pointer = true })
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
        base_name = 'count',
        setter_name = 'set_count',
      })
      local setter = accessor.create_setter(mv)

      eq('this->count = count;', setter.body)
    end)

    it('does NOT use this-> in body when use_explicit_this_pointer is false', function()
      config.merge({ use_explicit_this_pointer = false })
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
        base_name = 'count',
        setter_name = 'set_count',
      })
      local setter = accessor.create_setter(mv)

      eq('count = count;', setter.body)
    end)

    it('returns empty qualifier', function()
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
        base_name = 'count',
        setter_name = 'set_count',
      })
      local setter = accessor.create_setter(mv)

      eq('', setter.qualifier)
    end)

    it('uses safe param name to avoid C++ keywords', function()
      local mv = mock_member_var({
        name = 'int',
        leading_text = 'int',
        base_name = 'int',
        setter_name = 'set_int',
      })
      local setter = accessor.create_setter(mv)

      eq('int int_', setter.parameter)
    end)

    it('handles member with m_ prefix using base_name', function()
      local mv = mock_member_var({
        name = 'm_data',
        leading_text = 'int',
        base_name = 'data',
        setter_name = 'set_data',
      })
      local setter = accessor.create_setter(mv)

      eq('int data', setter.parameter)
      eq('m_data = data;', setter.body)
    end)

    it('uses const ref for const std::string type', function()
      local mv = mock_member_var({
        name = 'label',
        leading_text = 'std::string',
        base_name = 'label',
        setter_name = 'set_label',
      })
      local setter = accessor.create_setter(mv)

      eq('const std::string& label', setter.parameter)
    end)

    it('handles double (primitive) by value', function()
      local mv = mock_member_var({
        name = 'ratio',
        leading_text = 'double',
        base_name = 'ratio',
        setter_name = 'set_ratio',
      })
      local setter = accessor.create_setter(mv)

      eq('double ratio', setter.parameter)
    end)

    it('handles bool (primitive) by value', function()
      local mv = mock_member_var({
        name = 'enabled',
        leading_text = 'bool',
        base_name = 'enabled',
        setter_name = 'set_enabled',
      })
      local setter = accessor.create_setter(mv)

      eq('bool enabled', setter.parameter)
    end)

    it('handles void* pointer by value', function()
      local mv = mock_member_var({
        name = 'handle',
        leading_text = 'void*',
        base_name = 'handle',
        setter_name = 'set_handle',
        is_pointer = true,
      })
      local setter = accessor.create_setter(mv)

      eq('void* handle', setter.parameter)
    end)
  end)

  describe('_extract_type', function()
    it('strips static specifier', function()
      local mv = mock_member_var({ leading_text = 'static int' })
      eq('int', accessor._extract_type(mv))
    end)

    it('strips mutable specifier', function()
      local mv = mock_member_var({ leading_text = 'mutable std::string' })
      eq('std::string', accessor._extract_type(mv))
    end)

    it('strips constexpr specifier', function()
      local mv = mock_member_var({ leading_text = 'constexpr int' })
      eq('int', accessor._extract_type(mv))
    end)

    it('strips inline specifier', function()
      local mv = mock_member_var({ leading_text = 'inline int' })
      eq('int', accessor._extract_type(mv))
    end)

    it('strips volatile specifier', function()
      local mv = mock_member_var({ leading_text = 'volatile bool' })
      eq('bool', accessor._extract_type(mv))
    end)

    it('strips register specifier', function()
      local mv = mock_member_var({ leading_text = 'register int' })
      eq('int', accessor._extract_type(mv))
    end)

    it('strips extern specifier', function()
      local mv = mock_member_var({ leading_text = 'extern int' })
      eq('int', accessor._extract_type(mv))
    end)

    it('strips thread_local specifier', function()
      local mv = mock_member_var({ leading_text = 'thread_local int' })
      eq('int', accessor._extract_type(mv))
    end)

    it('strips multiple specifiers at once', function()
      local mv = mock_member_var({ leading_text = 'static constexpr mutable int' })
      eq('int', accessor._extract_type(mv))
    end)

    it('strips specifiers with extra whitespace', function()
      local mv = mock_member_var({ leading_text = 'static   constexpr   int' })
      eq('int', accessor._extract_type(mv))
    end)

    it('normalizes whitespace in result', function()
      local mv = mock_member_var({ leading_text = '  static   int  ' })
      eq('int', accessor._extract_type(mv))
    end)

    it('preserves const qualifier in type', function()
      local mv = mock_member_var({ leading_text = 'const int' })
      eq('const int', accessor._extract_type(mv))
    end)

    it('preserves pointer and reference modifiers', function()
      local mv = mock_member_var({ leading_text = 'int*' })
      eq('int*', accessor._extract_type(mv))
    end)

    it('preserves template types', function()
      local mv = mock_member_var({ leading_text = 'std::vector<int>' })
      eq('std::vector<int>', accessor._extract_type(mv))
    end)

    it('preserves complex const ref type', function()
      local mv = mock_member_var({ leading_text = 'const std::string&' })
      eq('const std::string&', accessor._extract_type(mv))
    end)

    it('strips specifier followed by underscore', function()
      -- Frontier pattern %f[%W] treats _ as word boundary differently
      -- "volatile_t" - the "volatile" part is stripped, leaving "_t"
      local mv = mock_member_var({ leading_text = 'volatile_t' })
      eq('_t', accessor._extract_type(mv))
    end)

    it('returns empty string for empty leading text', function()
      local mv = mock_member_var({ leading_text = '' })
      eq('', accessor._extract_type(mv))
    end)

    it('handles type with only specifiers stripped', function()
      local mv = mock_member_var({ leading_text = 'inline static unsigned long' })
      eq('unsigned long', accessor._extract_type(mv))
    end)
  end)

  describe('_safe_param_name', function()
    it('returns base name unchanged for non-keyword', function()
      eq('count', accessor._safe_param_name('count'))
    end)

    it('appends underscore for C++ keyword "int"', function()
      eq('int_', accessor._safe_param_name('int'))
    end)

    it('appends underscore for C++ keyword "class"', function()
      eq('class_', accessor._safe_param_name('class'))
    end)

    it('appends underscore for C++ keyword "return"', function()
      eq('return_', accessor._safe_param_name('return'))
    end)

    it('appends underscore for C++ keyword "delete"', function()
      eq('delete_', accessor._safe_param_name('delete'))
    end)

    it('appends underscore for C++ keyword "new"', function()
      eq('new_', accessor._safe_param_name('new'))
    end)

    it('appends underscore for C++ keyword "void"', function()
      eq('void_', accessor._safe_param_name('void'))
    end)

    it('appends underscore for C++ keyword "float"', function()
      eq('float_', accessor._safe_param_name('float'))
    end)

    it('appends underscore for C++ keyword "bool"', function()
      eq('bool_', accessor._safe_param_name('bool'))
    end)

    it('appends underscore for C++ keyword "auto"', function()
      eq('auto_', accessor._safe_param_name('auto'))
    end)

    it('appends underscore for C++ keyword "this"', function()
      eq('this_', accessor._safe_param_name('this'))
    end)

    it('appends underscore for C++ keyword "template"', function()
      eq('template_', accessor._safe_param_name('template'))
    end)

    it('does NOT modify non-keyword names like data', function()
      eq('data', accessor._safe_param_name('data'))
    end)

    it('does NOT modify non-keyword names like value', function()
      eq('value', accessor._safe_param_name('value'))
    end)

    it('does NOT modify non-keyword names like name', function()
      eq('name', accessor._safe_param_name('name'))
    end)

    it('handles empty string', function()
      eq('', accessor._safe_param_name(''))
    end)

    it('handles and/or/xor keywords', function()
      eq('and_', accessor._safe_param_name('and'))
      eq('or_', accessor._safe_param_name('or'))
      eq('xor_', accessor._safe_param_name('xor'))
    end)

    it('handles noexcept keyword', function()
      eq('noexcept_', accessor._safe_param_name('noexcept'))
    end)

    it('handles nullptr keyword', function()
      eq('nullptr_', accessor._safe_param_name('nullptr'))
    end)

    it('handles operator keyword', function()
      eq('operator_', accessor._safe_param_name('operator'))
    end)
  end)

  describe('format_getter_declaration', function()
    it('formats as ReturnType name() const; with no scope', function()
      local getter = {
        name = 'get_count',
        return_type = 'int',
        parameter = '',
        body = 'return count;',
        qualifier = ' const',
      }
      eq('int get_count() const;', accessor.format_getter_declaration(getter))
    end)

    it('includes scope prefix when provided', function()
      local getter = {
        name = 'get_count',
        return_type = 'int',
        parameter = '',
        body = 'return count;',
        qualifier = ' const',
      }
      eq('int MyClass::get_count() const;', accessor.format_getter_declaration(getter, 'MyClass::'))
    end)

    it('omits const when qualifier is empty (static getter)', function()
      local getter = {
        name = 'get_instance_count',
        return_type = 'int',
        parameter = '',
        body = 'return instance_count;',
        qualifier = '',
      }
      eq('int get_instance_count();', accessor.format_getter_declaration(getter))
    end)

    it('handles complex return type', function()
      local getter = {
        name = 'get_name',
        return_type = 'const std::string&',
        parameter = '',
        body = 'return name;',
        qualifier = ' const',
      }
      eq('const std::string& get_name() const;', accessor.format_getter_declaration(getter))
    end)

    it('defaults scope to empty string when nil', function()
      local getter = {
        name = 'get_val',
        return_type = 'int',
        parameter = '',
        body = 'return val;',
        qualifier = ' const',
      }
      eq('int get_val() const;', accessor.format_getter_declaration(getter, nil))
    end)
  end)

  describe('format_setter_declaration', function()
    it('formats as void name(Type param);', function()
      local setter = {
        name = 'set_count',
        return_type = 'void',
        parameter = 'int count',
        body = 'count = count;',
        qualifier = '',
      }
      eq('void set_count(int count);', accessor.format_setter_declaration(setter))
    end)

    it('includes scope prefix when provided', function()
      local setter = {
        name = 'set_count',
        return_type = 'void',
        parameter = 'int count',
        body = 'count = count;',
        qualifier = '',
      }
      eq('void MyClass::set_count(int count);', accessor.format_setter_declaration(setter, 'MyClass::'))
    end)

    it('handles const ref parameter', function()
      local setter = {
        name = 'set_name',
        return_type = 'void',
        parameter = 'const std::string& name',
        body = 'name = name;',
        qualifier = '',
      }
      eq('void set_name(const std::string& name);', accessor.format_setter_declaration(setter))
    end)

    it('defaults scope to empty string when nil', function()
      local setter = {
        name = 'set_val',
        return_type = 'void',
        parameter = 'int val',
        body = 'val = val;',
        qualifier = '',
      }
      eq('void set_val(int val);', accessor.format_setter_declaration(setter, nil))
    end)
  end)

  describe('format_getter_definition', function()
    it('formats multi-line definition with braces', function()
      local getter = {
        name = 'get_count',
        return_type = 'int',
        parameter = '',
        body = 'return count;',
        qualifier = ' const',
      }
      local expected = 'int get_count() const\n{\n  return count;\n}'
      eq(expected, accessor.format_getter_definition(getter))
    end)

    it('includes scope prefix', function()
      local getter = {
        name = 'get_count',
        return_type = 'int',
        parameter = '',
        body = 'return count;',
        qualifier = ' const',
      }
      local expected = 'int MyClass::get_count() const\n{\n  return count;\n}'
      eq(expected, accessor.format_getter_definition(getter, 'MyClass::'))
    end)

    it('applies indentation to body and closing brace', function()
      local getter = {
        name = 'get_count',
        return_type = 'int',
        parameter = '',
        body = 'return count;',
        qualifier = ' const',
      }
      local expected = 'int get_count() const\n  {\n    return count;\n  }'
      eq(expected, accessor.format_getter_definition(getter, '', '  '))
    end)

    it('handles scope and indent together', function()
      local getter = {
        name = 'get_count',
        return_type = 'int',
        parameter = '',
        body = 'return count;',
        qualifier = ' const',
      }
      local expected = 'int MyClass::get_count() const\n    {\n      return count;\n    }'
      eq(expected, accessor.format_getter_definition(getter, 'MyClass::', '    '))
    end)

    it('formats without qualifier for static getter', function()
      local getter = {
        name = 'get_instance_count',
        return_type = 'int',
        parameter = '',
        body = 'return instance_count;',
        qualifier = '',
      }
      local expected = 'int get_instance_count()\n{\n  return instance_count;\n}'
      eq(expected, accessor.format_getter_definition(getter))
    end)

    it('handles this-> in body', function()
      local getter = {
        name = 'get_count',
        return_type = 'int',
        parameter = '',
        body = 'return this->count;',
        qualifier = ' const',
      }
      local expected = 'int get_count() const\n{\n  return this->count;\n}'
      eq(expected, accessor.format_getter_definition(getter))
    end)

    it('defaults scope and indent to empty strings when nil', function()
      local getter = {
        name = 'get_val',
        return_type = 'int',
        parameter = '',
        body = 'return val;',
        qualifier = ' const',
      }
      local expected = 'int get_val() const\n{\n  return val;\n}'
      eq(expected, accessor.format_getter_definition(getter, nil, nil))
    end)
  end)

  describe('format_setter_definition', function()
    it('formats multi-line definition with braces', function()
      local setter = {
        name = 'set_count',
        return_type = 'void',
        parameter = 'int count',
        body = 'count = count;',
        qualifier = '',
      }
      local expected = 'void set_count(int count)\n{\n  count = count;\n}'
      eq(expected, accessor.format_setter_definition(setter))
    end)

    it('includes scope prefix', function()
      local setter = {
        name = 'set_count',
        return_type = 'void',
        parameter = 'int count',
        body = 'count = count;',
        qualifier = '',
      }
      local expected = 'void MyClass::set_count(int count)\n{\n  count = count;\n}'
      eq(expected, accessor.format_setter_definition(setter, 'MyClass::'))
    end)

    it('applies indentation to body and closing brace', function()
      local setter = {
        name = 'set_count',
        return_type = 'void',
        parameter = 'int count',
        body = 'count = count;',
        qualifier = '',
      }
      local expected = 'void set_count(int count)\n  {\n    count = count;\n  }'
      eq(expected, accessor.format_setter_definition(setter, '', '  '))
    end)

    it('handles scope and indent together', function()
      local setter = {
        name = 'set_count',
        return_type = 'void',
        parameter = 'int count',
        body = 'count = count;',
        qualifier = '',
      }
      local expected = 'void MyClass::set_count(int count)\n    {\n      count = count;\n    }'
      eq(expected, accessor.format_setter_definition(setter, 'MyClass::', '    '))
    end)

    it('handles const ref parameter', function()
      local setter = {
        name = 'set_name',
        return_type = 'void',
        parameter = 'const std::string& name',
        body = 'name = name;',
        qualifier = '',
      }
      local expected = 'void set_name(const std::string& name)\n{\n  name = name;\n}'
      eq(expected, accessor.format_setter_definition(setter))
    end)

    it('handles this-> in body', function()
      local setter = {
        name = 'set_count',
        return_type = 'void',
        parameter = 'int count',
        body = 'this->count = count;',
        qualifier = '',
      }
      local expected = 'void set_count(int count)\n{\n  this->count = count;\n}'
      eq(expected, accessor.format_setter_definition(setter))
    end)

    it('defaults scope and indent to empty strings when nil', function()
      local setter = {
        name = 'set_val',
        return_type = 'void',
        parameter = 'int val',
        body = 'val = val;',
        qualifier = '',
      }
      local expected = 'void set_val(int val)\n{\n  val = val;\n}'
      eq(expected, accessor.format_setter_definition(setter, nil, nil))
    end)
  end)

  describe('end-to-end: create + format', function()
    after_each(restore_config)

    it('creates and formats a complete getter for int member', function()
      config.merge({ use_explicit_this_pointer = false })
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
        getter_name = 'get_count',
      })
      local getter = accessor.create_getter(mv)

      eq('int get_count() const;', accessor.format_getter_declaration(getter))
      eq('int MyClass::get_count() const\n{\n  return count;\n}',
        accessor.format_getter_definition(getter, 'MyClass::'))
    end)

    it('creates and formats a complete setter for int member', function()
      config.merge({ use_explicit_this_pointer = false })
      local mv = mock_member_var({
        name = 'count',
        leading_text = 'int',
        base_name = 'count',
        setter_name = 'set_count',
      })
      local setter = accessor.create_setter(mv)

      eq('void set_count(int count);', accessor.format_setter_declaration(setter))
      eq('void MyClass::set_count(int count)\n{\n  count = count;\n}',
        accessor.format_setter_definition(setter, 'MyClass::'))
    end)

    it('creates and formats getter+setter for string member with this->', function()
      config.merge({ use_explicit_this_pointer = true })
      local mv = mock_member_var({
        name = 'm_name',
        leading_text = 'std::string',
        base_name = 'name',
        getter_name = 'get_name',
        setter_name = 'set_name',
      })
      local getter = accessor.create_getter(mv)
      local setter = accessor.create_setter(mv)

      eq('std::string get_name() const;', accessor.format_getter_declaration(getter))
      eq('std::string get_name() const\n{\n  return this->m_name;\n}',
        accessor.format_getter_definition(getter))

      eq('void set_name(const std::string& name);', accessor.format_setter_declaration(setter))
      eq('void set_name(const std::string& name)\n{\n  this->m_name = name;\n}',
        accessor.format_setter_definition(setter))
    end)

    it('creates and formats getter for static member', function()
      local mv = mock_member_var({
        name = 's_instance',
        leading_text = 'static int',
        is_static = true,
        getter_name = 'get_instance',
      })
      local getter = accessor.create_getter(mv)

      eq('int get_instance();', accessor.format_getter_declaration(getter))
      eq('int get_instance()\n{\n  return s_instance;\n}',
        accessor.format_getter_definition(getter))
    end)
  end)
end)
