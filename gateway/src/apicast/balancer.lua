local round_robin = require 'resty.balancer.round_robin'
local resty_url = require 'resty.url'

local _M = { default_balancer = round_robin.new() }

local function exit_service_unavailable()
  ngx.status = ngx.HTTP_SERVICE_UNAVAILABLE
  ngx.exit(ngx.status)
end

function _M:call(context, bal)
  if not context then
    return nil, 'missing context'
  end

  local host = ngx.var.proxy_host
  local balancer = bal or _M.default_balancer
  local upstream = context[host]

  if not upstream then
    return nil, 'missing upstream'
  end

  if context[upstream] then
    return nil, 'already set peer'
  end

  if host ~= upstream.upstream_name then
    ngx.log(ngx.ERR, 'upstream name: ', upstream.name, ' does not match proxy host: ', host)
    return nil, 'upstream host mismatch'
  end

  local peers = balancer:peers(upstream.servers)
  local peer, err = balancer:select_peer(peers)

  if not peer then
    ngx.log(ngx.ERR, 'could not select peer: ', err)
    return exit_service_unavailable(), err
  end

  local address, port = peer[1], peer[2]

  if not address then
    ngx.log(ngx.ERR, 'peer missing address')
    return exit_service_unavailable(), 'no address'
  end

  local ok
  ok, err = balancer:set_current_peer(address, port or resty_url.default_port(upstream.uri.scheme))

  if ok then
    -- I wish there would be a nicer way, but unfortunately ngx.exit(ngx.OK) does not
    -- terminate the current phase handler and will evaluate all remaining balancer phases.
    context[upstream] = peer
    return peer
  else
    ngx.log(ngx.ERR, 'failed to set current backend peer: ', err)
    return exit_service_unavailable(), err
  end
end

return _M
