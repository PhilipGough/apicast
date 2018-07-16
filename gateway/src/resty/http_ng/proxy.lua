local next = next
local resty_env = require 'resty.env'
local http = require 'resty.http'
local resty_url = require "resty.url"
local format = string.format

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

function _M.set(options)
    proxy_options = options
    _M.active = not not next(options)
    _M.http_backend = require('resty.http_ng.backend.resty')
end

function _M.env()
    return {
        http_proxy = resty_env.value('http_proxy') or resty_env.value('HTTP_PROXY'),
        https_proxy = resty_env.value('https_proxy') or resty_env.value('HTTPS_PROXY'),
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
    if port == resty_url.default_port(u.scheme) then
        port = ''
    else
        port = format(':%s', port)
    end

    local path = u.path

    if path == '' or path == nil then
        path = format('%s%s%s', ngx.var.uri, ngx.var.is_args, ngx.var.query_string)
    end

    return format('%s://%s%s%s', u.scheme, u.server, port, path or '/'), path
end

function _M.request()
    local httpc = http.new()

    httpc:set_proxy_options(_M.options())

    local url, path = upstream_server()
    local uri = resty_url.parse(url)
    local proxy_uri = httpc:get_proxy_uri(uri.scheme, uri.host)

    if not proxy_uri then return nil, 'no_proxy' end

    local ok, err = httpc:connect_proxy(proxy_uri, uri.scheme, uri.host, uri.port or resty_url.default_port(uri.scheme))

    if uri.scheme == 'https' then
        assert(httpc:ssl_handshake(nil, uri.host, true))
    end

    if ok then
        httpc:proxy_response(httpc:request{
            method = ngx.req.get_method(),
            headers = ngx.req.get_headers(0, true),
            path = uri.scheme == 'https' and path or url,
            body = httpc:get_client_body_reader(),
        })

        httpc:close()

        return true
    else
        ngx.log(ngx.ERR, 'could not connect to proxy: ',  proxy_uri, ' err: ', err)
        return ngx.exit(499)
    end
end

return _M
