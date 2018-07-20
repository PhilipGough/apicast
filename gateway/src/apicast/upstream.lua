local setmetatable = setmetatable
local tonumber = tonumber
local str_format = string.format

local resty_resolver = require('resty.resolver')
local resty_url = require('resty.url')
local core_base = require('resty.core.base')
local new_tab = core_base.new_tab

local _M = {

}

local function proxy_pass(upstream)
    local uri = upstream.uri

    return str_format('%s://%s%s%s%s',
            uri.scheme,
            upstream.upstream_name,
            uri.path or ngx.var.uri,
            ngx.var.is_args,
            ngx.var.query_string or '')
end

local mt = {
    __index = _M
}


local function parse_url(url)
    local parsed, err = resty_url.split(url)

    if err then return nil, err end

    local uri = new_tab(0, 6)

    uri.scheme = parsed[1]
    uri.user = parsed[2]
    uri.password = parsed[3]
    uri.host = parsed[4]
    uri.port = tonumber(parsed[5])
    uri.path = parsed[6]

    return uri
end

function _M.new(url)
    local uri, err = parse_url(url)

    if err then
        return nil, 'invalid upstream'
    end

    return setmetatable({
        uri = uri,
        location_name = '@upstream',
        upstream_name = 'upstream',
        resolver = resty_resolver:instance(),
    }, mt)
end

function _M:resolve(servers)
    local resolver = self.resolver
    local uri = self.uri

    if servers then
        self.servers = servers
        return servers
    end

    if not resolver or not uri then return nil, 'not initialized' end

    local res, err = resolver:get_servers(uri.host, { port = uri.port or resty_url.default_port(uri.scheme) })

    if err then
        return nil, err
    end

    self.servers = res

    return res
end

function _M:port()
    if not self or not self.uri then
        return nil, 'not initialized'
    end

    return self.uri.port or resty_url.default_port(self.uri.scheme)
end

function _M:rewrite(host)
    ngx.req.set_header('Host', host or self.uri.host)
end

local function exec(self)
    ngx.var.proxy_pass = proxy_pass(self)

    if self.location_name then
        ngx.exec(self.location_name)
    end
end

function _M:call(context)
    if ngx.headers_sent then return nil, 'response sent already' end

    if not self.servers then self:resolve() end

    context[self.upstream_name] = self

    return exec(self)
end

return _M
