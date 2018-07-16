local _M = {

}

local re_match = ngx.re.match
local tab_new = require('table.new')
local inspect = require('inspect')
local resty_url = require('resty.url')
local ngx_re_match = ngx.re.match
local str_lower = string.lower
local tonumber = tonumber
local format = string.format
local ceil = math.ceil

local inclusive = { inclusive = true }

local cr_lf = "\r\n"

local http_ok = 'HTTP/1.1 200 OK' .. cr_lf

local function send(socket, data)
    if ngx.config.debug then
        ngx.log(ngx.DEBUG, 'sending: ', inspect(data))
    end

    if not data or data == '' then
        ngx.log(ngx.DEBUG, 'skipping sending nil')
        return
    end

    -- ngx.flush()

    return socket:send(data)
end

local function read_stream(name, input, output)
    local data, err, partial

    local timeout = 1
    local exp = 1.3
    input:settimeouts(nil, nil, timeout)

    while true do
        data, err, partial = input:receive(4 * 1028) -- read any data
        send(output, data or partial)

        -- ngx.log(ngx.DEBUG, 'got data: ', data , ' partial: ', partial, ' socket: ', name)

        if err == 'closed' then
            ngx.log(ngx.DEBUG, "failed to read any data: ", err, ' socket: ', name)
            break

        elseif err == 'timeout' and partial == '' then
            timeout = ceil(timeout * exp)
            input:settimeouts(nil, nil, timeout)
            ngx.log(ngx.DEBUG, "failed to read any data: ", err, ' socket: ', name)
        end
    end

    if input.close then input:close() end
end

local function pipe_stream(sock, upstream)
    local read = ngx.thread.spawn(read_stream, 'INPUT READER', sock, upstream)
    local write = ngx.thread.spawn(read_stream, 'OUTPUT READER', upstream, sock)

    ngx.thread.wait(read, write)
end

local function _forward_chunked_body(sock, upstream)
    local length

    repeat
        -- Receive the chunk size
        local str, err = sock:receive("*l")

        if err then return nil, err end

        length = tonumber(str, 16)

        if not length then
            return nil, 'unable to read chunksize'
        end

        send(upstream, str .. cr_lf)

        if length > 0 then
            send(upstream, sock:receive(length) .. cr_lf)
        end

        sock:receive(2) -- last cr_lf
    until length == 0

    send(upstream, cr_lf)
end

local function _forward_body(sock, upstream, length)
    send(upstream, sock:receive(length))
end

local noop = function() end

local function forward_http_stream(sock, upstream)
    local read_header = sock:receiveuntil(cr_lf, inclusive)
    local body_length, header_line
    local body_reader = noop

    repeat
        header_line = read_header()
        send(upstream, header_line)

        local header = ngx_re_match(header_line, [[(?<name>[^:\s]+):\s*(?<value>.+)\r\n$]], "oj")

        if header and str_lower(header.name) == 'content-length' then
            body_length = tonumber(header.value)
            body_reader = _forward_body
        end

        if header and str_lower(header.name) == 'transfer-encoding' and str_lower(header.value) == 'chunked' then
            body_reader = _forward_chunked_body
        end
    until header_line == cr_lf

    body_reader(sock, upstream, body_length)
end

local function proxy_http_request(sock, method, url, http_version, upstream)
    local uri = resty_url.parse(url)
    local port = uri.port or resty_url.default_port(uri.scheme)
    local ok, err = upstream:connect(uri.host, port)

    if ok then
        ngx.log(ngx.DEBUG, 'connected to upstream ', uri.host, ':', port)
    else
        ngx.log(ngx.ERR, 'failed to connect to ', uri.host, ':', port, ' err: ', err)
        return nil, err
    end

    local req_line = format('%s %s %s%s', method, uri.path or '/', http_version, cr_lf)

    send(upstream, req_line)

    forward_http_stream(sock, upstream)
    send(upstream, cr_lf)
    send(upstream, cr_lf)
    forward_http_stream(upstream, sock)
end

local function proxy_connect_request(sock, connect, upstream)
    local ok, err = upstream:connect(connect.host, connect.port)

    if ok then
        ngx.log(ngx.DEBUG, 'connected to upstream ', connect.host, ':', connect.port)
    else
        ngx.log(ngx.ERR, 'failed to connect to ', connect.host, ':', connect.port, ' err: ', err)
        return nil, err
    end

    local header_line
    local read_request_header = sock:receiveuntil(cr_lf, inclusive)

    repeat
        header_line = read_request_header()
        ngx.log(ngx.DEBUG, 'got header line: ', inspect(header_line))
    until header_line == cr_lf

    send(sock, http_ok)
    send(sock, cr_lf)

    return pipe_stream(sock, upstream)
end

function _M.content()
    local client, err = ngx.req.socket(true)

    if not client then return nil, err end

    local readline = client:receiveuntil(cr_lf)
    local data, partial
    data, err, partial = readline()

    local match = tab_new(1,3)
    match, err = re_match(data, [[^(?<method>[A-Z]+)\s(?<uri>\S+)\s(?<http>\S+)$]], 'oj', nil, match)

    local upstream = ngx.socket.tcp()

    if match.method == 'CONNECT' then
        local connect = ngx_re_match(match.uri, [[^(?<host>[^:]+):(?<port>\d+)$]])

        proxy_connect_request(client, connect, upstream)
    else
        proxy_http_request(client, match.method, match.uri, match.http, upstream)
    end
end

function _M.preread()

end

function _M.log()

end

return _M
