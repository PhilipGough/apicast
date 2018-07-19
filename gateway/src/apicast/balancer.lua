local round_robin = require 'resty.balancer.round_robin'
local resty_url = require 'resty.url'
local empty = {}

local _M = { default_balancer = round_robin.new() }

local function get_default_port(upstream_url)
  local url = resty_url.split(upstream_url) or empty
  local scheme = url[1] or 'http'
  return resty_url.default_port(scheme)
end

local function exit_service_unavailable()
  ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE
  ngx.exit(ngx.status)
end

function _M:call(context, bal)
  local balancer = bal or _M.default_balancer
  local upstream = context.upstream

  if context[upstream] then
    return nil, 'already set peer'
  end

  local host = ngx.var.proxy_host -- NYI: return to lower frame

  if host ~= upstream.upstream_name then
    ngx.log(ngx.ERR, 'upstream name: ', upstream.name, ' does not match proxy host: ', host)
    return nil, 'upstream host mismatch'
  end

  local peers = balancer:peers(upstream.servers)
  local peer, err = balancer:select_peer(peers)

  if not peer then
    ngx.log(ngx.ERR, 'could not select peer: ', err)
    return exit_service_unavailable()
  end

  local address, port = peer[1], peer[2]

  if not address then
    ngx.log(ngx.ERR, 'peer missing address')
    return exit_service_unavailable()
  end

  if not port then
    port = get_default_port(ngx.var.proxy_pass)
  end

  local ok
  ok, err = balancer.balancer.set_current_peer(address, port)

  if ok then
    ngx.log(ngx.INFO, 'balancer set peer ', address, ':', port)
    -- I wish there would be a nicer way, but unfortunately ngx.exit(ngx.OK) does not
    -- terminate the current phase handler and will evaluate all remaining balancer phases.
    context[upstream] = peer
  else
    ngx.log(ngx.ERR, 'failed to set current backend peer: ', err)
    return exit_service_unavailable()
  end
end

return _M
