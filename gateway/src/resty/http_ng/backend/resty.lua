------------
--- HTTP
-- HTTP client
-- @module http_ng.backend

local backend = {}
local response = require 'resty.http_ng.response'
local http = require 'resty.resolver.http'
local proxy = require 'resty.http_ng.proxy'
local resty_url = require 'resty.url'
local format = string.format

local function send(httpc, params)
  params.path = params.path or params.uri.path

  local res, err = httpc:request(params)
  if not res then return nil, err end

  res.body, err = res:read_body()

  if not res.body then
    return nil, err
  end

  local ok

  ok, err = httpc:close()

  if not ok then
    ngx.log(ngx.ERR, 'failed to close connection: ', err)
  end

  return res
end

local function connect(httpc, request)
  local uri = request.uri
  local ok, err = httpc:connect(uri.host, uri.port)

  if not ok then return nil, err end

  return httpc
end

local function _connect_proxy_https(httpc, request, host, port)
  local uri = request.uri

  local ok, err = httpc:request({
    method = 'CONNECT',
    path = format('%s:%s', host, port),
    headers = {
      ['Host'] = request.headers.host or format('%s:%s', uri.host, uri.port),
    }
  })
  if not ok then return nil, err end

  ok, err = httpc:ssl_handshake(nil, uri.host, request.ssl_verify)
  if not ok then return nil, err end

  return httpc
end

local function connect_proxy(httpc, request)
  local uri = request.uri
  local host, port = httpc:resolve(uri.host, uri.port or resty_url.default_port(uri.scheme))
  local proxy_uri = request.proxy

  if proxy_uri.scheme ~= 'http' then
    return nil, 'proxy connection supports only http'
  end

  -- these options will make the connection pool scoped by "host" header
  -- that is required for https proxying
  local options = { pool = format('%s:%s:%s:%s', uri.host, uri.port, host, port) }
  local ok, err = httpc:connect(proxy_uri.host, proxy_uri.port, options)
  if not ok then return nil, err end

  if uri.scheme == 'http' then
    request.path = format('%s://%s:%s%s', uri.scheme, host, port, uri.path)
    return httpc

  elseif uri.scheme == 'https' then
    return _connect_proxy_https(httpc, request, host, port)

  else
    return nil, 'invalid scheme'
  end
end

local function connect_http(request)
  local httpc = http.new()

  -- PERFORMANCE: `set_proxy_options` deep clones the table internally, this could be optimized to
  -- just shove it into `httpc.proxy_opts` by reference.
  httpc:set_proxy_options(proxy.options())

  local uri = resty_url.parse(request.url)
  local proxy_url = httpc:get_proxy_uri(uri.scheme, uri.host)

  request.ssl_verify = request.options and request.options.ssl and request.options.ssl.verify
  request.proxy = resty_url.parse(proxy_url)
  request.uri = uri

  local ok, err

  if proxy_url then
    return connect_proxy(httpc, request)
  else
    return connect(httpc, request)
  end
end

--- Send request and return the response
-- @tparam http_ng.request request
-- @treturn http_ng.response
backend.send = function(_, request)
  local res
  local httpc, err = connect_http(request)

  if httpc then
    res, err = send(httpc, request)
  end

  if res then
    return response.new(request, res.status, res.headers, res.body)
  else
    return response.error(request, err)
  end
end


return backend
