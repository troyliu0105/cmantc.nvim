local operator = require('cmantic.operator')
local config = require('cmantic.config')
local eq = assert.are.same

describe('operator', function()
  local saved_friend

  before_each(function()
    saved_friend = config.values.friend_comparison_operators
    config.values.friend_comparison_operators = false
  end)

  after_each(function()
    config.values.friend_comparison_operators = saved_friend
  end)

  ---------------------------------------------------------------------------
  -- create_equal (member variant)
  ---------------------------------------------------------------------------
  describe('create_equal (member variant)', function()
    it('generates member operator== declaration and definition', function()
      local parent = { name = 'MyClass' }
      local ops = { { name = 'x' } }
      local result = operator.create_equal(parent, ops)

      eq('bool operator==(const MyClass& other) const;', result.equal.declaration)
      eq(
        'bool MyClass::operator==(const MyClass& other) const\n'
          .. '{\n'
          .. '  return x == other.x;\n'
          .. '}',
        result.equal.definition
      )
    end)

    it('generates member operator!= declaration and definition', function()
      local parent = { name = 'MyClass' }
      local ops = { { name = 'x' } }
      local result = operator.create_equal(parent, ops)

      eq('bool operator!=(const MyClass& other) const;', result.not_equal.declaration)
      eq(
        'bool MyClass::operator!=(const MyClass& other) const\n'
          .. '{\n'
          .. '  return !(*this == other);\n'
          .. '}',
        result.not_equal.definition
      )
    end)

    it('compares single operand with ==', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'value' } }
      local result = operator.create_equal(parent, ops)

      assert.is_true(result.equal.definition:find('return value == other%.value;') ~= nil)
    end)

    it('compares multiple operands with && chain', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'x' }, { name = 'y' }, { name = 'z' } }
      local result = operator.create_equal(parent, ops)

      assert.is_true(result.equal.definition:find('x == other%.x &&') ~= nil)
      assert.is_true(result.equal.definition:find('y == other%.y &&') ~= nil)
      assert.is_true(result.equal.definition:find('z == other%.z;') ~= nil)
    end)

    it('returns true for empty operands list', function()
      local parent = { name = 'Empty' }
      local result = operator.create_equal(parent, {})

      assert.is_true(result.equal.definition:find('return true;') ~= nil)
    end)

    it('uses other. prefix in member variant', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'data' } }
      local result = operator.create_equal(parent, ops)

      assert.is_true(result.equal.definition:find('other%.data') ~= nil)
      assert.is_true(result.equal.definition:find('data == other%.data') ~= nil)
    end)
  end)

  ---------------------------------------------------------------------------
  -- create_equal (friend variant)
  ---------------------------------------------------------------------------
  describe('create_equal (friend variant)', function()
    before_each(function()
      config.values.friend_comparison_operators = true
    end)

    it('generates friend operator== declaration and definition', function()
      local parent = { name = 'MyClass' }
      local ops = { { name = 'x' } }
      local result = operator.create_equal(parent, ops)

      eq('friend bool operator==(const MyClass& lhs, const MyClass& rhs);', result.equal.declaration)
      eq(
        'bool operator==(const MyClass& lhs, const MyClass& rhs)\n'
          .. '{\n'
          .. '  return lhs.x == rhs.x;\n'
          .. '}',
        result.equal.definition
      )
    end)

    it('generates friend operator!= declaration and definition', function()
      local parent = { name = 'MyClass' }
      local ops = { { name = 'x' } }
      local result = operator.create_equal(parent, ops)

      eq('friend bool operator!=(const MyClass& lhs, const MyClass& rhs);', result.not_equal.declaration)
      eq(
        'bool operator!=(const MyClass& lhs, const MyClass& rhs)\n'
          .. '{\n'
          .. '  return !(lhs == rhs);\n'
          .. '}',
        result.not_equal.definition
      )
    end)

    it('uses lhs. and rhs. prefix in friend variant', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'data' } }
      local result = operator.create_equal(parent, ops)

      assert.is_true(result.equal.definition:find('lhs%.data == rhs%.data') ~= nil)
    end)

    it('negates with !(lhs == rhs) in friend !=', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'x' } }
      local result = operator.create_equal(parent, ops)

      assert.is_true(result.not_equal.definition:find('return !%(lhs == rhs%)') ~= nil)
    end)

    it('uses friend keyword in declarations', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'a' } }
      local result = operator.create_equal(parent, ops)

      assert.is_true(result.equal.declaration:find('^friend ') ~= nil)
      assert.is_true(result.not_equal.declaration:find('^friend ') ~= nil)
    end)
  end)

  ---------------------------------------------------------------------------
  -- create_equal multi-operand formatting
  ---------------------------------------------------------------------------
  describe('create_equal (multi-operand formatting)', function()
    it('aligns multi-line && comparison with correct indent', function()
      local parent = { name = 'Vec' }
      local ops = { { name = 'x' }, { name = 'y' } }
      local result = operator.create_equal(parent, ops)

      -- Multi-line: first comparison, then &&\n + 9-space indent for subsequent
      local indent = string.rep(' ', 9)
      local expected = 'x == other.x &&\n' .. indent .. 'y == other.y;'
      assert.is_true(result.equal.definition:find(expected, 1, true) ~= nil)
    end)

    it('does NOT add newline for single comparison', function()
      local parent = { name = 'Vec' }
      local ops = { { name = 'x' } }
      local result = operator.create_equal(parent, ops)

      assert.is_true(result.equal.definition:find('return x == other%.x;') ~= nil)
      -- Should NOT have && in single-operand case
      assert.is_true(result.equal.definition:find('&&') == nil)
    end)
  end)

  ---------------------------------------------------------------------------
  -- create_less_than
  ---------------------------------------------------------------------------
  describe('create_less_than', function()
    it('generates cascading if-return comparison for multiple operands', function()
      local parent = { name = 'Point' }
      local ops = { { name = 'x' }, { name = 'y' } }
      local result = operator.create_less_than(parent, ops)

      assert.is_true(result.definition:find('if %(x != other%.x%) return x < other%.x;') ~= nil)
      assert.is_true(result.definition:find('if %(y != other%.y%) return y < other%.y;') ~= nil)
    end)

    it('returns return false for empty operands', function()
      local parent = { name = 'Empty' }
      local result = operator.create_less_than(parent, {})

      eq('bool operator<(const Empty& other) const;', result.declaration)
      -- Body should just be "return false;"
      assert.is_true(result.definition:find('return false;') ~= nil)
    end)

    it('uses other. prefix in member variant', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'val' } }
      local result = operator.create_less_than(parent, ops)

      assert.is_true(result.definition:find('other%.val') ~= nil)
    end)

    it('uses lhs. and rhs. prefix in friend variant', function()
      config.values.friend_comparison_operators = true
      local parent = { name = 'Foo' }
      local ops = { { name = 'val' } }
      local result = operator.create_less_than(parent, ops)

      assert.is_true(result.definition:find('lhs%.val != rhs%.val') ~= nil)
      assert.is_true(result.definition:find('lhs%.val < rhs%.val') ~= nil)
    end)

    it('includes return false at end of cascade', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'a' }, { name = 'b' }, { name = 'c' } }
      local result = operator.create_less_than(parent, ops)

      -- Should end cascade with "return false;"
      assert.is_true(result.definition:find('return false;') ~= nil)
      -- Count occurrences: 3 cascading + 1 final = 1 "return false;" (the final one)
      -- Actually all lines are "if ... return ...;" + final "return false;"
      local _, count = result.definition:gsub('return false;', '')
      eq(1, count)
    end)

    it('generates member declaration and definition format', function()
      local parent = { name = 'Widget' }
      local ops = { { name = 'size' } }
      local result = operator.create_less_than(parent, ops)

      eq('bool operator<(const Widget& other) const;', result.declaration)
      eq(
        'bool Widget::operator<(const Widget& other) const\n'
          .. '{\n'
          .. '  if (size != other.size) return size < other.size;\n'
          .. '  return false;\n'
          .. '}',
        result.definition
      )
    end)

    it('generates friend declaration and definition format', function()
      config.values.friend_comparison_operators = true
      local parent = { name = 'Widget' }
      local ops = { { name = 'size' } }
      local result = operator.create_less_than(parent, ops)

      eq('friend bool operator<(const Widget& lhs, const Widget& rhs);', result.declaration)
      eq(
        'bool operator<(const Widget& lhs, const Widget& rhs)\n'
          .. '{\n'
          .. '  if (lhs.size != rhs.size) return lhs.size < rhs.size;\n'
          .. '  return false;\n'
          .. '}',
        result.definition
      )
    end)
  end)

  ---------------------------------------------------------------------------
  -- create_greater_than
  ---------------------------------------------------------------------------
  describe('create_greater_than', function()
    it('delegates to other < *this in member variant', function()
      local parent = { name = 'Foo' }
      local result = operator.create_greater_than(parent)

      eq('bool operator>(const Foo& other) const;', result.declaration)
      eq(
        'bool Foo::operator>(const Foo& other) const\n'
          .. '{\n'
          .. '  return other < *this;\n'
          .. '}',
        result.definition
      )
    end)

    it('delegates to rhs < lhs in friend variant', function()
      config.values.friend_comparison_operators = true
      local parent = { name = 'Foo' }
      local result = operator.create_greater_than(parent)

      eq('friend bool operator>(const Foo& lhs, const Foo& rhs);', result.declaration)
      eq(
        'bool operator>(const Foo& lhs, const Foo& rhs)\n'
          .. '{\n'
          .. '  return rhs < lhs;\n'
          .. '}',
        result.definition
      )
    end)
  end)

  ---------------------------------------------------------------------------
  -- create_less_than_or_equal
  ---------------------------------------------------------------------------
  describe('create_less_than_or_equal', function()
    it('delegates to !(other < *this) in member variant', function()
      local parent = { name = 'Foo' }
      local result = operator.create_less_than_or_equal(parent)

      eq('bool operator<=(const Foo& other) const;', result.declaration)
      eq(
        'bool Foo::operator<=(const Foo& other) const\n'
          .. '{\n'
          .. '  return !(other < *this);\n'
          .. '}',
        result.definition
      )
    end)

    it('delegates to !(rhs < lhs) in friend variant', function()
      config.values.friend_comparison_operators = true
      local parent = { name = 'Foo' }
      local result = operator.create_less_than_or_equal(parent)

      eq('friend bool operator<=(const Foo& lhs, const Foo& rhs);', result.declaration)
      eq(
        'bool operator<=(const Foo& lhs, const Foo& rhs)\n'
          .. '{\n'
          .. '  return !(rhs < lhs);\n'
          .. '}',
        result.definition
      )
    end)
  end)

  ---------------------------------------------------------------------------
  -- create_greater_than_or_equal
  ---------------------------------------------------------------------------
  describe('create_greater_than_or_equal', function()
    it('delegates to !(*this < other) in member variant', function()
      local parent = { name = 'Foo' }
      local result = operator.create_greater_than_or_equal(parent)

      eq('bool operator>=(const Foo& other) const;', result.declaration)
      eq(
        'bool Foo::operator>=(const Foo& other) const\n'
          .. '{\n'
          .. '  return !(*this < other);\n'
          .. '}',
        result.definition
      )
    end)

    it('delegates to !(lhs < rhs) in friend variant', function()
      config.values.friend_comparison_operators = true
      local parent = { name = 'Foo' }
      local result = operator.create_greater_than_or_equal(parent)

      eq('friend bool operator>=(const Foo& lhs, const Foo& rhs);', result.declaration)
      eq(
        'bool operator>=(const Foo& lhs, const Foo& rhs)\n'
          .. '{\n'
          .. '  return !(lhs < rhs);\n'
          .. '}',
        result.definition
      )
    end)
  end)

  ---------------------------------------------------------------------------
  -- create_stream_output
  ---------------------------------------------------------------------------
  describe('create_stream_output', function()
    it('generates os << name: << obj.name for each member', function()
      local parent = { name = 'Point' }
      local ops = { { name = 'x' }, { name = 'y' } }
      local result = operator.create_stream_output(parent, ops)

      assert.is_true(result.definition:find('os << "x: " << obj%.x;') ~= nil)
      assert.is_true(result.definition:find('os << "y: " << obj%.y;') ~= nil)
    end)

    it('separates members with comma separator', function()
      local parent = { name = 'Point' }
      local ops = { { name = 'x' }, { name = 'y' } }
      local result = operator.create_stream_output(parent, ops)

      assert.is_true(result.definition:find('os << ", ";') ~= nil)
    end)

    it('uses friend declaration always', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'val' } }
      local result = operator.create_stream_output(parent, ops)

      assert.is_true(result.declaration:find('^friend ') ~= nil)
      eq('friend std::ostream& operator<<(std::ostream& os, const Foo& obj);', result.declaration)
    end)

    it('returns return os at end', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'val' } }
      local result = operator.create_stream_output(parent, ops)

      assert.is_true(result.definition:find('return os;') ~= nil)
    end)

    it('formats single-operand output without separator', function()
      local parent = { name = 'Single' }
      local ops = { { name = 'value' } }
      local result = operator.create_stream_output(parent, ops)

      eq(
        'std::ostream& operator<<(std::ostream& os, const Single& obj)\n'
          .. '{\n'
          .. '  os << "value: " << obj.value;\n'
          .. '  return os;\n'
          .. '}',
        result.definition
      )
      local _, comma_count = result.definition:gsub('os << ", ";', '')
      eq(0, comma_count)
    end)

    it('produces comment for empty operands', function()
      local parent = { name = 'Empty' }
      local result = operator.create_stream_output(parent, {})

      assert.is_true(result.definition:find('No members to output') ~= nil)
    end)

    it('generates multi-member output with correct formatting', function()
      local parent = { name = 'Vec3' }
      local ops = { { name = 'x' }, { name = 'y' }, { name = 'z' } }
      local result = operator.create_stream_output(parent, ops)

      eq(
        'std::ostream& operator<<(std::ostream& os, const Vec3& obj)\n'
          .. '{\n'
          .. '  os << "x: " << obj.x;\n'
          .. '  os << ", ";\n'
          .. '  os << "y: " << obj.y;\n'
          .. '  os << ", ";\n'
          .. '  os << "z: " << obj.z;\n'
          .. '  return os;\n'
          .. '}',
        result.definition
      )
    end)
  end)

  ---------------------------------------------------------------------------
  -- create_relational
  ---------------------------------------------------------------------------
  describe('create_relational', function()
    it('returns table with less, greater, less_equal, greater_equal', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'x' } }
      local result = operator.create_relational(parent, ops)

      assert.is_not_nil(result.less)
      assert.is_not_nil(result.greater)
      assert.is_not_nil(result.less_equal)
      assert.is_not_nil(result.greater_equal)
    end)

    it('passes operands to create_less_than', function()
      local parent = { name = 'Point' }
      local ops = { { name = 'x' }, { name = 'y' } }
      local result = operator.create_relational(parent, ops)

      local standalone = operator.create_less_than(parent, ops)
      eq(standalone, result.less)
    end)

    it('does NOT pass operands to derived operators', function()
      local parent = { name = 'Point' }
      local ops = { { name = 'x' }, { name = 'y' } }
      local result = operator.create_relational(parent, ops)

      -- greater_than, less_than_or_equal, greater_than_or_equal only take parent_class
      local gt = operator.create_greater_than(parent)
      local le = operator.create_less_than_or_equal(parent)
      local ge = operator.create_greater_than_or_equal(parent)

      eq(gt, result.greater)
      eq(le, result.less_equal)
      eq(ge, result.greater_equal)
    end)
  end)

  ---------------------------------------------------------------------------
  -- Config interaction
  ---------------------------------------------------------------------------
  describe('config interaction', function()
    it('reads friend_comparison_operators at call time (not cached)', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'x' } }

      -- Member variant
      config.values.friend_comparison_operators = false
      local member_result = operator.create_equal(parent, ops)
      assert.is_true(member_result.equal.declaration:find('^bool ') ~= nil)

      -- Switch to friend variant
      config.values.friend_comparison_operators = true
      local friend_result = operator.create_equal(parent, ops)
      assert.is_true(friend_result.equal.declaration:find('^friend ') ~= nil)
    end)

    it('produces member-style output when config is false', function()
      config.values.friend_comparison_operators = false
      local parent = { name = 'Bar' }
      local ops = { { name = 'v' } }
      local result = operator.create_equal(parent, ops)

      -- Member style: declaration has "other", no "friend"
      assert.is_true(result.equal.declaration:find('other') ~= nil)
      assert.is_true(result.equal.declaration:find('friend') == nil)
      -- Member style: definition has ClassName::
      assert.is_true(result.equal.definition:find('Bar::operator==') ~= nil)
    end)

    it('produces friend-style output when config is true', function()
      config.values.friend_comparison_operators = true
      local parent = { name = 'Bar' }
      local ops = { { name = 'v' } }
      local result = operator.create_equal(parent, ops)

      -- Friend style: declaration starts with "friend", has "lhs", "rhs"
      assert.is_true(result.equal.declaration:find('^friend ') ~= nil)
      assert.is_true(result.equal.declaration:find('lhs') ~= nil)
      assert.is_true(result.equal.declaration:find('rhs') ~= nil)
      -- Friend style: definition does NOT have ClassName::
      assert.is_true(result.equal.definition:find('Bar::') == nil)
    end)
  end)

  ---------------------------------------------------------------------------
  -- Edge cases
  ---------------------------------------------------------------------------
  describe('edge cases', function()
    it('create_equal handles class names with templates', function()
      local parent = { name = 'MyClass<T>' }
      local ops = { { name = 'data' } }
      local result = operator.create_equal(parent, ops)

      eq('bool operator==(const MyClass<T>& other) const;', result.equal.declaration)
      assert.is_true(result.equal.definition:find('MyClass<T>::operator==') ~= nil)
    end)

    it('create_equal handles template class in friend variant', function()
      config.values.friend_comparison_operators = true
      local parent = { name = 'Pair<K, V>' }
      local ops = { { name = 'first' } }
      local result = operator.create_equal(parent, ops)

      eq(
        'friend bool operator==(const Pair<K, V>& lhs, const Pair<K, V>& rhs);',
        result.equal.declaration
      )
    end)

    it('create_stream_output handles single-member class', function()
      local parent = { name = 'Wrapper' }
      local ops = { { name = 'inner' } }
      local result = operator.create_stream_output(parent, ops)

      -- Should have exactly one output line, no separator
      local _, comma_count = result.definition:gsub('os << ", ";', '')
      eq(0, comma_count)

      assert.is_true(result.definition:find('os << "inner: " << obj%.inner;') ~= nil)
    end)

    it('create_less_than handles template class name', function()
      local parent = { name = 'Container<T>' }
      local ops = { { name = 'size' } }
      local result = operator.create_less_than(parent, ops)

      assert.is_true(result.declaration:find('Container<T>') ~= nil)
      assert.is_true(result.definition:find('Container<T>::operator<') ~= nil)
    end)

    it('create_greater_than handles template class name', function()
      local parent = { name = 'Container<T>' }
      local result = operator.create_greater_than(parent)

      assert.is_true(result.declaration:find('Container<T>') ~= nil)
      assert.is_true(result.definition:find('Container<T>::operator>') ~= nil)
    end)

    it('create_equal handles operands with underscores in names', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'my_value' }, { name = 'other_val' } }
      local result = operator.create_equal(parent, ops)

      assert.is_true(result.equal.definition:find('my_value == other%.my_value') ~= nil)
      assert.is_true(result.equal.definition:find('other_val == other%.other_val') ~= nil)
    end)

    it('create_stream_output handles operands with underscores', function()
      local parent = { name = 'Foo' }
      local ops = { { name = 'my_value' } }
      local result = operator.create_stream_output(parent, ops)

      assert.is_true(result.definition:find('"my_value: " << obj%.my_value') ~= nil)
    end)
  end)
end)
