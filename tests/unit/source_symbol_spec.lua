local SourceSymbol = require('cmantic.source_symbol')
local SK = SourceSymbol.SymbolKind

local eq = assert.are.same

local function mock_sym(name, kind, opts)
  opts = opts or {}
  return {
    name = name,
    kind = kind,
    range = opts.range or {
      start = { line = opts.start_line or 0, character = opts.start_char or 0 },
      ['end'] = { line = opts.end_line or 0, character = opts.end_char or 10 },
    },
    selectionRange = {
      start = { line = opts.start_line or 0, character = opts.start_char or 0 },
      ['end'] = { line = opts.end_line or 0, character = opts.end_char or 10 },
    },
    detail = opts.detail or '',
    children = opts.children or {},
  }
end

describe('source_symbol', function()
  describe('new', function()
    it('creates symbol with correct fields', function()
      local raw = mock_sym('MyClass', SK.Class)
      local sym = SourceSymbol.new(raw, 'file:///test.hpp', nil)
      eq('MyClass', sym.name)
      eq(SK.Class, sym.kind)
    end)

    it('strips scope resolution from name', function()
      local raw = mock_sym('MyClass::method', SK.Method)
      local sym = SourceSymbol.new(raw, 'file:///test.hpp', nil)
      eq('method', sym.name)
    end)

    it('strips global scope resolution ::method', function()
      local raw = mock_sym('::method', SK.Method)
      local sym = SourceSymbol.new(raw, 'file:///test.hpp', nil)
      eq('method', sym.name)
    end)

    it('strips nested scope resolution NS::Class::method', function()
      local raw = mock_sym('NS::Class::method', SK.Method)
      local sym = SourceSymbol.new(raw, 'file:///test.hpp', nil)
      eq('method', sym.name)
    end)

    it('preserves name without scope resolution', function()
      local raw = mock_sym('method', SK.Method)
      local sym = SourceSymbol.new(raw, 'file:///test.hpp', nil)
      eq('method', sym.name)
    end)

    it('sets parent reference', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('x', SK.Field) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      eq(parent, parent.children[1].parent)
    end)

    it('sorts children by range start position', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = {
          mock_sym('b', SK.Field, { start_line = 5 }),
          mock_sym('a', SK.Field, { start_line = 3 }),
          mock_sym('c', SK.Field, { start_line = 7 }),
        }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      eq('a', parent.children[1].name)
      eq('b', parent.children[2].name)
      eq('c', parent.children[3].name)
    end)

    it('handles nil name gracefully', function()
      local raw = mock_sym(nil, SK.Function)
      local sym = SourceSymbol.new(raw, 'file:///test.hpp', nil)
      eq('', sym.name)
    end)

    it('sorts children on same line by character position', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = {
          mock_sym('c', SK.Field, { start_line = 1, start_char = 20 }),
          mock_sym('a', SK.Field, { start_line = 1, start_char = 4 }),
          mock_sym('b', SK.Field, { start_line = 1, start_char = 10 }),
        }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      eq('a', parent.children[1].name)
      eq('b', parent.children[2].name)
      eq('c', parent.children[3].name)
    end)

    it('deep-copies children without mutating original', function()
      local child_raw = mock_sym('x', SK.Field)
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { child_raw }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      parent.children[1].name = 'modified'
      eq('x', child_raw.name)
    end)
  end)

  describe('is_function', function()
    it('returns true for Function', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Function), 'file:///test.hpp', nil)
      assert.is_true(sym:is_function())
    end)
    it('returns true for Method', function()
      local sym = SourceSymbol.new(mock_sym('method', SK.Method), 'file:///test.hpp', nil)
      assert.is_true(sym:is_function())
    end)
    it('returns true for Constructor', function()
      local sym = SourceSymbol.new(mock_sym('MyClass', SK.Constructor), 'file:///test.hpp', nil)
      assert.is_true(sym:is_function())
    end)
    it('returns true for Operator', function()
      local sym = SourceSymbol.new(mock_sym('operator==', SK.Operator), 'file:///test.hpp', nil)
      assert.is_true(sym:is_function())
    end)
    it('returns false for Field', function()
      local sym = SourceSymbol.new(mock_sym('x', SK.Field), 'file:///test.hpp', nil)
      assert.is_false(sym:is_function())
    end)
  end)

  describe('is_class_type', function()
    it('returns true for Class', function()
      local sym = SourceSymbol.new(mock_sym('Foo', SK.Class), 'file:///test.hpp', nil)
      assert.is_true(sym:is_class_type())
    end)
    it('returns true for Struct', function()
      local sym = SourceSymbol.new(mock_sym('Bar', SK.Struct), 'file:///test.hpp', nil)
      assert.is_true(sym:is_class_type())
    end)
    it('returns false for Namespace', function()
      local sym = SourceSymbol.new(mock_sym('ns', SK.Namespace), 'file:///test.hpp', nil)
      assert.is_false(sym:is_class_type())
    end)
  end)

  describe('is_class', function()
    it('returns true for Class kind', function()
      local sym = SourceSymbol.new(mock_sym('Foo', SK.Class), 'file:///test.hpp', nil)
      assert.is_true(sym:is_class())
    end)
    it('returns false for Struct kind', function()
      local sym = SourceSymbol.new(mock_sym('Bar', SK.Struct), 'file:///test.hpp', nil)
      assert.is_false(sym:is_class())
    end)
  end)

  describe('is_struct', function()
    it('returns true for Struct kind', function()
      local sym = SourceSymbol.new(mock_sym('Bar', SK.Struct), 'file:///test.hpp', nil)
      assert.is_true(sym:is_struct())
    end)
    it('returns false for Class kind', function()
      local sym = SourceSymbol.new(mock_sym('Foo', SK.Class), 'file:///test.hpp', nil)
      assert.is_false(sym:is_struct())
    end)
  end)

  describe('is_namespace', function()
    it('returns true for Namespace kind', function()
      local sym = SourceSymbol.new(mock_sym('ns', SK.Namespace), 'file:///test.hpp', nil)
      assert.is_true(sym:is_namespace())
    end)
    it('returns false for Class kind', function()
      local sym = SourceSymbol.new(mock_sym('Foo', SK.Class), 'file:///test.hpp', nil)
      assert.is_false(sym:is_namespace())
    end)
  end)

  describe('is_enum', function()
    it('returns true for Enum kind', function()
      local sym = SourceSymbol.new(mock_sym('Color', SK.Enum), 'file:///test.hpp', nil)
      assert.is_true(sym:is_enum())
    end)
    it('returns false for Struct kind', function()
      local sym = SourceSymbol.new(mock_sym('Bar', SK.Struct), 'file:///test.hpp', nil)
      assert.is_false(sym:is_enum())
    end)
  end)

  describe('is_enum_member', function()
    it('returns true for EnumMember kind', function()
      local sym = SourceSymbol.new(mock_sym('Red', SK.EnumMember), 'file:///test.hpp', nil)
      assert.is_true(sym:is_enum_member())
    end)
    it('returns false for Enum kind', function()
      local sym = SourceSymbol.new(mock_sym('Color', SK.Enum), 'file:///test.hpp', nil)
      assert.is_false(sym:is_enum_member())
    end)
  end)

  describe('is_member_variable', function()
    it('returns true for Field inside a class', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('x', SK.Field) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_true(parent.children[1]:is_member_variable())
    end)
    it('returns false for Field outside a class', function()
      local sym = SourceSymbol.new(mock_sym('x', SK.Field), 'file:///test.hpp', nil)
      assert.is_false(sym:is_member_variable())
    end)
    it('returns false for Method inside a class', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('foo', SK.Method) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_false(parent.children[1]:is_member_variable())
    end)
    it('returns true for Property kind inside a class', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('prop', SK.Property) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_true(parent.children[1]:is_member_variable())
    end)
    it('returns false for Field inside a namespace', function()
      local ns_raw = mock_sym('ns', SK.Namespace, {
        children = { mock_sym('x', SK.Field) }
      })
      local ns = SourceSymbol.new(ns_raw, 'file:///test.hpp', nil)
      assert.is_false(ns.children[1]:is_member_variable())
    end)
  end)

  describe('is_static', function()
    it('returns true when detail starts with static', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Function, { detail = 'static int foo()' }), 'file:///test.hpp', nil)
      assert.is_true(sym:is_static())
    end)
    it('returns false when detail does not contain static', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Function, { detail = 'int foo()' }), 'file:///test.hpp', nil)
      assert.is_false(sym:is_static())
    end)
    it('returns false when detail is nil', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Function, { detail = nil }), 'file:///test.hpp', nil)
      assert.is_false(sym:is_static())
    end)
    it('returns false when detail contains notstatic (substring, not word)', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Function, { detail = 'notstatic int foo()' }), 'file:///test.hpp', nil)
      assert.is_false(sym:is_static())
    end)
  end)

  describe('is_variable', function()
    it('returns true for top-level variable', function()
      local sym = SourceSymbol.new(mock_sym('value', SK.Variable), 'file:///test.hpp', nil)
      assert.is_true(sym:is_variable())
    end)
    it('returns false for field outside class', function()
      local sym = SourceSymbol.new(mock_sym('value', SK.Field), 'file:///test.hpp', nil)
      assert.is_false(sym:is_variable())
    end)
    it('returns true for field inside class', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('value', SK.Field) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_true(parent.children[1]:is_variable())
    end)
  end)

  describe('is_anonymous', function()
    it('returns true when name contains anonymous', function()
      local sym = SourceSymbol.new(mock_sym('anonymous struct', SK.Struct), 'file:///test.hpp', nil)
      assert.is_true(sym:is_anonymous())
    end)
    it('returns false for regular names', function()
      local sym = SourceSymbol.new(mock_sym('MyClass', SK.Class), 'file:///test.hpp', nil)
      assert.is_false(sym:is_anonymous())
    end)
  end)

  describe('is_constructor', function()
    it('returns true for Constructor kind inside class', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('MyClass', SK.Constructor) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_true(parent.children[1]:is_constructor())
    end)
    it('returns true when name matches parent name', function()
      local parent_raw = mock_sym('Foo', SK.Class, {
        children = { mock_sym('Foo', SK.Function) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      assert.is_true(parent.children[1]:is_constructor())
    end)
    it('returns false when not inside class', function()
      local sym = SourceSymbol.new(mock_sym('Foo', SK.Constructor), 'file:///test.hpp', nil)
      assert.is_false(sym:is_constructor())
    end)
  end)

  describe('is_destructor', function()
    it('returns true for ~Name', function()
      local sym = SourceSymbol.new(mock_sym('~MyClass', SK.Method), 'file:///test.hpp', nil)
      assert.is_true(sym:is_destructor())
    end)
    it('returns false for regular method', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Method), 'file:///test.hpp', nil)
      assert.is_false(sym:is_destructor())
    end)
  end)

  describe('base_name', function()
    it('strips leading underscores', function()
      local sym = SourceSymbol.new(mock_sym('_value', SK.Field), 'file:///test.hpp', nil)
      eq('value', sym:base_name())
    end)
    it('strips trailing underscores', function()
      local sym = SourceSymbol.new(mock_sym('value_', SK.Field), 'file:///test.hpp', nil)
      eq('value', sym:base_name())
    end)
    it('strips m_ prefix', function()
      local sym = SourceSymbol.new(mock_sym('m_name', SK.Field), 'file:///test.hpp', nil)
      eq('name', sym:base_name())
    end)
    it('strips s_ prefix', function()
      local sym = SourceSymbol.new(mock_sym('s_instance', SK.Field), 'file:///test.hpp', nil)
      eq('instance', sym:base_name())
    end)
    it('returns name as-is when no prefix', function()
      local sym = SourceSymbol.new(mock_sym('count', SK.Field), 'file:///test.hpp', nil)
      eq('count', sym:base_name())
    end)
    it('handles name that is all underscores', function()
      local sym = SourceSymbol.new(mock_sym('___', SK.Field), 'file:///test.hpp', nil)
      eq('', sym:base_name())
    end)
  end)

  describe('scopes', function()
    it('returns empty for root symbol', function()
      local sym = SourceSymbol.new(mock_sym('foo', SK.Function), 'file:///test.hpp', nil)
      eq(0, #sym:scopes())
    end)

    it('returns parent chain for nested symbols', function()
      local ns_raw = mock_sym('ns', SK.Namespace, {
        children = {
          mock_sym('MyClass', SK.Class, {
            children = { mock_sym('method', SK.Method) }
          })
        }
      })
      local ns = SourceSymbol.new(ns_raw, 'file:///test.hpp', nil)
      local class_sym = ns.children[1]
      local method = class_sym.children[1]

      local scopes = method:scopes()
      eq(2, #scopes)
      eq('ns', scopes[1].name)
      eq('MyClass', scopes[2].name)
    end)

    it('returns single parent for symbol with one ancestor', function()
      local parent_raw = mock_sym('MyClass', SK.Class, {
        children = { mock_sym('x', SK.Field) }
      })
      local parent = SourceSymbol.new(parent_raw, 'file:///test.hpp', nil)
      local field = parent.children[1]

      local scopes = field:scopes()
      eq(1, #scopes)
      eq('MyClass', scopes[1].name)
    end)

    it('maintains top-down order (namespace before class)', function()
      local ns_raw = mock_sym('myns', SK.Namespace, {
        children = {
          mock_sym('MyClass', SK.Class, {
            children = { mock_sym('foo', SK.Method) }
          })
        }
      })
      local ns = SourceSymbol.new(ns_raw, 'file:///test.hpp', nil)
      local method = ns.children[1].children[1]

      local scopes = method:scopes()
      eq(SK.Namespace, scopes[1].kind)
      eq(SK.Class, scopes[2].kind)
    end)
  end)

end)
