local busted = require('busted')
local assert = require('luassert.assert')
local util = require ('luassert.util')
local say = require('say')

do -- set up reverting stubs
  local state = require("luassert.state")

  local function snapshot()
    --- creates a snapshot and adds it to a stack
    state.snapshot()
    return nil, true -- to not stop the chain
  end

  local function revert()
    --- reverts state of the current snapshot and removes it from the stack
    state.revert()
    return nil, true
  end

  for _, phase in ipairs({ 'suite', 'file', 'describe', 'it'}) do
    busted.subscribe({ phase, 'start' }, snapshot)
    busted.subscribe({ phase, 'end' }, revert)
  end

  busted.before_each(snapshot)
  busted.after_each(revert)
end

do -- adding gt matcher: assert.spy(something).was_called_with(match.is_gt(4))
  local function is_gt(_, arguments)
    local expected = arguments[1]
    return function(value)
      return value > expected
    end
  end

  assert:register("matcher", "gt", is_gt)
end

do -- adding assert.returns_error(error_text, ok, ret) : assert.returns_error('not initialized', _M:call())
  local tostring = tostring
  local tonumber = tonumber
  local s = require('say')

  local function returns_error(state, arguments, level)
    local argc = arguments.n
    assert(argc == 3, say("assertion.internal.argtolittle", { "error_matches", 3, tostring(argc) }), level)

    local expected = tonumber(arguments[1])
    local ok = tonumber(arguments[2])
    local actual = tonumber(arguments[3])

    local result = not ok and expected == actual
    -- switch arguments for proper output message
    util.tinsert(arguments, 1, util.tremove(arguments, 3))
    state.failure_message = arguments[3]
    return result
  end

  assert:register("assertion", "returns_error", returns_error, "assertion.error.positive", "assertion.error.negative")

  local function contains_left(left, right)
    if type(left) == 'table' then
      for k,v in pairs(left) do
        local same, crumbs = contains_left(v, right[k])

        if not same then
          crumbs = crumbs or { }
          table.insert(crumbs,  k)
          return false, crumbs
        end
      end

      return true
    elseif left == right then
      return true
    else
      return false
    end
  end


  local function set_failure_message(state, message)
    if message ~= nil then
      state.failure_message = message
    end
  end

  local function contains(state, arguments, level)
    local argcnt = arguments.n

    assert(argcnt > 1, s("assertion.internal.argtolittle", { "same", 2, tostring(argcnt) }), (level or 1) + 1)

    local expected = arguments[1]
    local actual = arguments[2]
    assert.is_table(expected)
    assert.is_table(actual)

    local result, crumbs = contains_left(expected, actual)
    util.tinsert(arguments, 1, util.tremove(arguments, 2))
    arguments.fmtargs = arguments.fmtargs or {}
    arguments.fmtargs[1] = { crumbs = crumbs }
    arguments.fmtargs[2] = { crumbs = crumbs }
    set_failure_message(state, arguments[3])

    return result
  end

  s:set("assertion.contains.positive", "Expected object to contain another.\nPassed in:\n%s\nExpected:\n%s")
  s:set("assertion.contains.negative", "Expected objects to not contain another.\nPassed in:\n%s\nDid not expect:\n%s")

  assert:register("assertion", "contains", contains, "assertion.contains.positive", "assertion.contains.negative")
end
