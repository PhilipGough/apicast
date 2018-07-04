------------
--- HTTP
-- HTTP client
-- @module http_ng.backend

local backend = {}
local response = require 'resty.http_ng.response'
local http = require 'resty.resolver.http'
local proxy = require 'resty.http_ng.proxy'

--- Send request and return the response
-- @tparam http_ng.request request
-- @treturn http_ng.response
backend.send = function(_, request)
  local httpc = http.new()
  local ssl_verify = request.options and request.options.ssl and request.options.ssl.verify

  -- PERFORMANCE: `set_proxy_options` deep clones the table internally, this could be optimized to
  -- just shove it into `httpc.proxy_opts` by reference.
  httpc:set_proxy_options(proxy.options())

  local res, err = httpc:request_uri(request.url, {
    method = request.method,
    body = request.body,
    headers = request.headers,
    ssl_verify = ssl_verify
  })

  if res then
    return response.new(request, res.status, res.headers, res.body)
  else
    return response.error(request, err)
  end
end


return backend
