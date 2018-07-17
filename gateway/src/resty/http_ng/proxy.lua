local next = next
local format = string.format
local tostring = tostring

local resty_env = require 'resty.env'
local http = require 'resty.resolver.http'
local resty_url = require "resty.url"
local resty_resolver = require 'resty.resolver'
local round_robin = require 'resty.balancer.round_robin'

local proxy_options

local _M = { }

function _M.options()
    _M.init()
    return proxy_options
end

function _M.init()
    if not proxy_options then
        _M.reset()
    end

    return _M
end

function _M.resolve(host, port)
    if _M.dns_resolution == 'proxy' then
        return host, port
    end

    local resolver = _M.resolver:instance()
    local balancer = _M.balancer

    if not resolver or not balancer then
        return nil, 'not initialized'
    end

    local servers = resolver:get_servers(host, { port = port })
    local peers = balancer:peers(servers)
    local peer = balancer:select_peer(peers)

    local ip = host

    if peer then
        ip = peer[1]
        port = peer[2]
    end

    return ip, port
end

function _M.set(options)
    proxy_options = options
    _M.active = not not next(options)
    _M.http_backend = require('resty.http_ng.backend.resty')
    _M.balancer = round_robin.new()
    _M.resolver = resty_resolver
    _M.dns_resolution = 'apicast' -- can be set to 'proxy' to let proxy do the name resolution
end

function _M.env()
    local all_proxy = resty_env.value('all_proxy') or resty_env.value('ALL_PROXY')

    return {
        http_proxy = resty_env.value('http_proxy') or resty_env.value('HTTP_PROXY') or all_proxy,
        https_proxy = resty_env.value('https_proxy') or resty_env.value('HTTPS_PROXY') or all_proxy,
        no_proxy = resty_env.value('no_proxy') or resty_env.value('NO_PROXY'),
    }
end

function _M.reset()
    _M.set(_M.env())

    return _M
end

local function upstream_server()
    local u = ngx.ctx.upstream_server
    local port = u.port
    local server = u.server

    if port == resty_url.default_port(u.scheme) then
        port = ''
    else
        port = format(':%s', port)
    end

    local path = u.path

    if path == '' or path == nil then
        path = format('%s%s%s', ngx.var.uri, ngx.var.is_args, ngx.var.query_string)
    end

    return format('%s://%s%s%s', u.scheme, server, port, path or '/'), path
end

local function resolve_uri(uri)
    local host, port = _M.resolve(uri.host, uri.port)

    uri.host = host
    uri.port = port or resty_url.default_port(uri.scheme)

    local url = format('%s://%s:%s%s', uri.scheme, uri.host, uri.port, uri.path)

    return resty_url.parse(url)
end

local function rewrite_for_http_proxy(uri, proxy_uri)
    ngx.ctx.upstream_server.server = proxy_uri.host
    ngx.ctx.upstream_server.port = proxy_uri.port

    ngx.ctx.upstream = _M.resolver:instance():get_servers(proxy_uri.host, { port = proxy_uri.port })

    ngx.req.set_uri(tostring(uri))
    ngx.exec(ngx.ctx.upstream_server.name)
end

local function forward_https_request(uri, proxy_uri, path)
    local httpc = http.new()

    local ok, err = httpc:connect_proxy(proxy_uri, uri.scheme, uri.host, uri.port or resty_url.default_port(uri.scheme))

    if not ok then
        ngx.log(ngx.ERR, 'could not connect to proxy: ',  proxy_uri, ' err: ', err)

        return ngx.exit(ngx.HTTP_SERVICE_UNAVAILABLE)
    end

    ok, err = httpc:ssl_handshake(nil, ngx.ctx.upstream_server.host, true)
    if not ok then
        ngx.log(ngx.ERR, 'could not connect to proxy: ',  proxy_uri, ' err: ', err)
        return ngx.exit(ngx.HTTP_BAD_GATEWAY)
    end

    httpc:proxy_response(assert(httpc:request{
        method = ngx.req.get_method(),
        headers = ngx.req.get_headers(0, true),
        path = path,
        body = httpc:get_client_body_reader(),
    }))

    httpc:close()
end

local function get_proxy_uri(uri)
    local self = { proxy_opts = _M.options() }

    local proxy_url = http.get_proxy_uri(self, uri.scheme, uri.host)
    if not proxy_url then return nil, 'no_proxy' end

    local proxy_uri  = resty_url.parse(proxy_url)
    if not proxy_uri then return nil, 'invalid proxy url' end

    if not proxy_uri.port then
        proxy_uri.port = resty_url.default_port(proxy_uri.scheme)
    end

    return proxy_uri
end

function _M.request()
    local url, path = upstream_server()
    local uri = resty_url.parse(url)
    local proxy_uri = get_proxy_uri(uri)

    if uri and proxy_uri then
        uri = resolve_uri(uri)
    end

    if uri.scheme == 'http' then -- rewrite the reqeust to use http_proxy
        return rewrite_for_http_proxy(uri, proxy_uri)
    elseif uri.scheme == 'https' then
        return forward_https_request(uri, proxy_uri, path)
    else
        ngx.log(ngx.ERR, 'could not connect to proxy: ',  proxy_uri, ' err: ', 'invalid request scheme')
        return ngx.exit(ngx.HTTP_BAD_GATEWAY)
    end
end

return _M
