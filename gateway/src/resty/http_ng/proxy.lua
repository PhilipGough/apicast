local next = next
local resty_env = require 'resty.env'

local proxy_options

local _M = { }

function _M.options()
    return proxy_options
end

function _M.set(options)
    proxy_options = options
    _M.active = not not next(options)
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

return _M.reset()
