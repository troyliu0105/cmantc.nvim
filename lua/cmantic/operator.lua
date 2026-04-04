--- Operator generation for cmantic.nvim
--- Ported from vscode-cmantic src/Operator.ts
--- Generates comparison operators (==, !=, <, >, <=, >=) and stream output (<<)

local M = {}

local config = require('cmantic.config')

--------------------------------------------------------------------------------
-- Equal Operator (== and !=)
--------------------------------------------------------------------------------

--- Create equality operators (== and !=) for a class
--- @param parent_class table CSymbol for the class
--- @param operands table[] Array of CSymbol member variables to compare
--- @return table { equal = { declaration, definition }, not_equal = { declaration, definition } }
function M.create_equal(parent_class, operands)
  local class_name = parent_class.name
  local friend = config.values.friend_comparison_operators

  -- Build comparison expressions for the body
  local comparisons = {}
  for _, op in ipairs(operands) do
    if friend then
      table.insert(comparisons, 'lhs.' .. op.name .. ' == rhs.' .. op.name)
    else
      table.insert(comparisons, op.name .. ' == other.' .. op.name)
    end
  end

  local comparison_expr
  if #comparisons == 0 then
    comparison_expr = 'true'
  elseif #comparisons == 1 then
    comparison_expr = comparisons[1]
  else
    -- Multi-line comparison with proper alignment
    local indent = string.rep(' ', 9) -- align after "return "
    comparison_expr = comparisons[1] .. ' &&\n' .. indent .. table.concat(comparisons, ' &&\n' .. indent, 2)
  end

  local eq_decl, eq_def
  local neq_decl, neq_def

  if friend then
    -- Friend operator== declaration and definition
    eq_decl = 'friend bool operator==(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs);'
    eq_def = 'bool operator==(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs)\n'
      .. '{\n'
      .. '  return ' .. comparison_expr .. ';\n'
      .. '}'

    -- Friend operator!= declaration and definition (negation of ==)
    neq_decl = 'friend bool operator!=(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs);'
    neq_def = 'bool operator!=(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs)\n'
      .. '{\n'
      .. '  return !(lhs == rhs);\n'
      .. '}'
  else
    -- Member operator== declaration and definition
    eq_decl = 'bool operator==(const ' .. class_name .. '& other) const;'
    eq_def = 'bool ' .. class_name .. '::operator==(const ' .. class_name .. '& other) const\n'
      .. '{\n'
      .. '  return ' .. comparison_expr .. ';\n'
      .. '}'

    -- Member operator!= declaration and definition (negation of ==)
    neq_decl = 'bool operator!=(const ' .. class_name .. '& other) const;'
    neq_def = 'bool ' .. class_name .. '::operator!=(const ' .. class_name .. '& other) const\n'
      .. '{\n'
      .. '  return !(*this == other);\n'
      .. '}'
  end

  return {
    equal = { declaration = eq_decl, definition = eq_def },
    not_equal = { declaration = neq_decl, definition = neq_def },
  }
end

--------------------------------------------------------------------------------
-- Less Than Operator (<)
--------------------------------------------------------------------------------

--- Create less-than operator (<) with cascading comparisons
--- @param parent_class table CSymbol for the class
--- @param operands table[] Array of CSymbol member variables to compare
--- @return table { declaration, definition }
function M.create_less_than(parent_class, operands)
  local class_name = parent_class.name
  local friend = config.values.friend_comparison_operators

  -- Build cascading comparison body
  local body_lines = {}
  if #operands == 0 then
    table.insert(body_lines, 'return false;')
  else
    for _, op in ipairs(operands) do
      if friend then
        table.insert(body_lines, 'if (lhs.' .. op.name .. ' != rhs.' .. op.name .. ') return lhs.' .. op.name .. ' < rhs.' .. op.name .. ';')
      else
        table.insert(body_lines, 'if (' .. op.name .. ' != other.' .. op.name .. ') return ' .. op.name .. ' < other.' .. op.name .. ';')
      end
    end
    table.insert(body_lines, 'return false;')
  end

  local body = table.concat(body_lines, '\n  ')

  local lt_decl, lt_def

  if friend then
    lt_decl = 'friend bool operator<(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs);'
    lt_def = 'bool operator<(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs)\n'
      .. '{\n'
      .. '  ' .. body .. '\n'
      .. '}'
  else
    lt_decl = 'bool operator<(const ' .. class_name .. '& other) const;'
    lt_def = 'bool ' .. class_name .. '::operator<(const ' .. class_name .. '& other) const\n'
      .. '{\n'
      .. '  ' .. body .. '\n'
      .. '}'
  end

  return { declaration = lt_decl, definition = lt_def }
end

--------------------------------------------------------------------------------
-- Greater Than Operator (>)
--------------------------------------------------------------------------------

--- Create greater-than operator (>) derived from <
--- @param parent_class table CSymbol for the class
--- @return table { declaration, definition }
function M.create_greater_than(parent_class)
  local class_name = parent_class.name
  local friend = config.values.friend_comparison_operators

  local gt_decl, gt_def

  if friend then
    gt_decl = 'friend bool operator>(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs);'
    gt_def = 'bool operator>(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs)\n'
      .. '{\n'
      .. '  return rhs < lhs;\n'
      .. '}'
  else
    gt_decl = 'bool operator>(const ' .. class_name .. '& other) const;'
    gt_def = 'bool ' .. class_name .. '::operator>(const ' .. class_name .. '& other) const\n'
      .. '{\n'
      .. '  return other < *this;\n'
      .. '}'
  end

  return { declaration = gt_decl, definition = gt_def }
end

--------------------------------------------------------------------------------
-- Less Than or Equal Operator (<=)
--------------------------------------------------------------------------------

--- Create less-than-or-equal operator (<=) derived from <
--- @param parent_class table CSymbol for the class
--- @return table { declaration, definition }
function M.create_less_than_or_equal(parent_class)
  local class_name = parent_class.name
  local friend = config.values.friend_comparison_operators

  local le_decl, le_def

  if friend then
    le_decl = 'friend bool operator<=(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs);'
    le_def = 'bool operator<=(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs)\n'
      .. '{\n'
      .. '  return !(rhs < lhs);\n'
      .. '}'
  else
    le_decl = 'bool operator<=(const ' .. class_name .. '& other) const;'
    le_def = 'bool ' .. class_name .. '::operator<=(const ' .. class_name .. '& other) const\n'
      .. '{\n'
      .. '  return !(other < *this);\n'
      .. '}'
  end

  return { declaration = le_decl, definition = le_def }
end

--------------------------------------------------------------------------------
-- Greater Than or Equal Operator (>=)
--------------------------------------------------------------------------------

--- Create greater-than-or-equal operator (>=) derived from <
--- @param parent_class table CSymbol for the class
--- @return table { declaration, definition }
function M.create_greater_than_or_equal(parent_class)
  local class_name = parent_class.name
  local friend = config.values.friend_comparison_operators

  local ge_decl, ge_def

  if friend then
    ge_decl = 'friend bool operator>=(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs);'
    ge_def = 'bool operator>=(const ' .. class_name .. '& lhs, const ' .. class_name .. '& rhs)\n'
      .. '{\n'
      .. '  return !(lhs < rhs);\n'
      .. '}'
  else
    ge_decl = 'bool operator>=(const ' .. class_name .. '& other) const;'
    ge_def = 'bool ' .. class_name .. '::operator>=(const ' .. class_name .. '& other) const\n'
      .. '{\n'
      .. '  return !(*this < other);\n'
      .. '}'
  end

  return { declaration = ge_decl, definition = ge_def }
end

--------------------------------------------------------------------------------
-- Stream Output Operator (<<)
--------------------------------------------------------------------------------

--- Create stream output operator (<<) for debugging
--- @param parent_class table CSymbol for the class
--- @param operands table[] Array of CSymbol member variables to output
--- @return table { declaration, definition }
function M.create_stream_output(parent_class, operands)
  local class_name = parent_class.name

  -- Build output parts
  local parts = {}
  for i, op in ipairs(operands) do
    if i > 1 then
      table.insert(parts, 'os << ", ";')
    end
    table.insert(parts, 'os << "' .. op.name .. ': " << obj.' .. op.name .. ';')
  end

  local body
  if #parts == 0 then
    body = '  // No members to output'
  else
    body = '  ' .. table.concat(parts, '\n  ')
  end

  local decl = 'friend std::ostream& operator<<(std::ostream& os, const ' .. class_name .. '& obj);'
  local def = 'std::ostream& operator<<(std::ostream& os, const ' .. class_name .. '& obj)\n'
    .. '{\n'
    .. body .. '\n'
    .. '  return os;\n'
    .. '}'

  return { declaration = decl, definition = def }
end

--------------------------------------------------------------------------------
-- Combined Operator Generation
--------------------------------------------------------------------------------

--- Create all relational operators (<, >, <=, >=) from member variables
--- @param parent_class table CSymbol for the class
--- @param operands table[] Array of CSymbol member variables to compare
--- @return table { less = { decl, def }, greater = {...}, less_equal = {...}, greater_equal = {...} }
function M.create_relational(parent_class, operands)
  return {
    less = M.create_less_than(parent_class, operands),
    greater = M.create_greater_than(parent_class),
    less_equal = M.create_less_than_or_equal(parent_class),
    greater_equal = M.create_greater_than_or_equal(parent_class),
  }
end

return M
