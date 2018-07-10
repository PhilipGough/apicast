local re_gsub = ngx.re.gsub
local re_match = ngx.re.match
local re_gmatch = ngx.re.gmatch
local re_split = require('ngx.re').split
local insert = table.insert
local unpack = unpack
local ipairs = ipairs

local _M = {}

-- Returns a list of named args extracted from a match_rule.
-- For example, for the rule /{abc}/{def}?{ghi}=1, it returns this list:
-- { "abc", "def", "ghi" }.
local function extract_named_args(match_rule)
  local iterator, err = re_gmatch(match_rule, [[\{(.+?)\}]], 'oj')

  if not iterator then
    return nil, err
  end

  local named_args = {}

  while true do
    local m, err_iter = iterator()
    if err_iter then
      return nil, err_iter
    end

    if not m then
      break
    end

    insert(named_args, m[1])
  end

  return named_args
end

-- Rules contain {} for named args. This function replaces those with "()" to
-- be able to capture those args when matching the regex.
local function transform_rule_to_regex(match_rule)
  return re_gsub(
    match_rule,
    [[\{.+?\}]],
    [[([\w-.~%!$$&'()*+,;=@:]+)]], -- Same as in the MappingRule module
    'oj'
  )
end

-- Transforms a string representing the args of a query like:
-- "a=1&b=2&c=3" into a table: { a = "1", b = "2", c = "3" }.
local function string_params_to_table(string_params)
  local res = {}

  local params_split = re_split(string_params, '&')

  for _, param in ipairs(params_split) do
    local name, val = unpack(re_split(param, '='))
    res[name] = val
  end

  return res
end

local function replace_in_template(args, vals, template)
  local res = template

  for i, arg in ipairs(args) do
    res = re_gsub(res, "{" .. arg .. "}", vals[i], 'oj')
  end

  return res
end

--- Replace named args
-- Matches a rule with named args (identified between "{ }") against a URL path
-- and replaces those named args in the given template.
-- The function returns two values, the new path and a table with the new args.
-- For example, if:
--   * path = "/abc/def"
--   * match_rule = "/{var_1}/{var_2}"
--   * template = "/{var_2}?{var_1}=1"
-- The result would be: "/def" (new path), { abc = "1"} (new args)
-- @tparam string path The URL path
-- @tparam string match_rule The match rule with named args (between "{}")
-- @tparam string template The template with named args to be replaced
-- @treturn string The new path
-- @treturn table The new args
function _M.replace(path, match_rule, template)
  local named_args = extract_named_args(match_rule)
  local regex_rule = transform_rule_to_regex(match_rule)

  local matches = re_match(path, regex_rule, 'oj') or {}

  if #named_args ~= #matches then
    return path, {}
  end

  local replaced_template = replace_in_template(named_args, matches, template)

  local uri, raw_params = unpack(re_split(replaced_template, '\\?'))

  return uri, string_params_to_table(raw_params)
end

return _M
