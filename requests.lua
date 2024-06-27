local headers = require("socket.headers")
local http = require("socket.http")
local url = require("socket.url")
local socket = require("socket")
local ssl = require("ssl")
local ltn12 = require("ltn12")

local requests = {
    err_msg = "Invalid %s request: %s",
    ssl_params = {
        mode = "client",
        protocol = "tlsv1_2",
        verify = "peer",
        cafile = "/etc/ssl/certs/ca-certificates.crt",
        options = "all"
    },
    socket_hosts = {}
}


---@return string host,string path,number port
function requests:unpack_url(URI)
    local _, _, protocol, host, path = URI:find("(http[s]?)://([^/]+)(.+)$")
    local port = protocol == "https" and 443 or 80
    return host, path, port
end

---create a HTTP(S) client socket set up for the given URL
---@return table client_socket with SSL if necessary
function requests:create_socket(host, port, timeout)
    local client_socket = assert(socket.tcp(), "Could not create TCP client socket")
    assert(client_socket:connect(host, port), "Could not connect to host")
    if port == 443 then
        client_socket = assert(ssl.wrap(client_socket, self.ssl_params), "Could not create SSL connection")
        assert(client_socket:dohandshake(), "SSL handshake failed")
    end
    client_socket:settimeout(timeout)

    return client_socket
end

function requests:build_GET_request(path, request_headers)
    local request_table = {}
    table.insert(request_table, ("%s %s HTTP/1.1\r\n"):format('GET', path))
    for k,v in pairs(request_headers) do
        table.insert(request_table, ("%s: %s\r\n"):format(headers.canonic[k] or k, v))
    end
    if not request_headers['Accept'] then
        table.insert(request_table, ("Accept: application/json\r\n"))
    end
    table.insert(request_table, "\r\n")
    return table.concat(request_table, "")
end

function requests:parse_response(response)
    local response_headers, data = {}, nil
    local _, e, status_code, status_reason = response:find("^HTTP/1.1 (%d+) (%w+)\r?\n")
    local init_idx = e + 1
    while not data do
        local start_idx, end_idx = response:find("(\r?\n)", init_idx)
        local header_line = response:sub(init_idx, start_idx-1)
        if #header_line == 0 then
            -- done parsing headers, next up is data
            data = response:sub(end_idx+1, #response)
        else
            local _, _, key, value = header_line:find("^([^:]+): (.+)$")
            response_headers[key] = value
        end
        init_idx = end_idx +1
    end
    return {
        data = data,
        headers = response_headers,
        status_code = tonumber(status_code),
        status_message = status_reason
    }
end

---@param client_socket table socket which is ready to be read from
---@return boolean coroutine_result, table|nil response (if we finished)
function requests:GET_async(client_socket)
    local parser, parse_header, parse_data
    local response_headers, response_data = {}, ''
    local status_code, status_message
    function parse_header()
        local result, status, partial = client_socket:receive('*l')
        assert(not partial or #partial == 0, "INCOMPLETE HEADER") -- TODO?
        if status then
            return status
        end
        if #result == 0 then
            parser = parse_data
            return
        end
        local _, _, key, value = result:find("^([^:]+): (.+)$")
        if key then
            response_headers[key] = value
        else
            status_code, status_message = socket.skip(2, result:find("^HTTP/1.1 (%d+) ([%s%w]+)$"))
        end
    end

    function parse_data()
        local result, status, partial = client_socket:receive(response_headers['content-length'] - #response_data)
        if partial and #partial > 0 then
            response_data = response_data .. partial
            print(("Got partial data of length %d, we requested %d (current size: %d)"):format(#partial, response_headers['content-length'], #response_data))
        end
        if status then
            return status
        end
        response_data = response_data .. result
        parser = nil
    end

    parser = parse_header
    while parser do
        local status = parser()
        if status == "wantread" then
            coroutine.yield()
        end
    end
    return true, {
        data = response_data,
        headers = response_headers,
        status_code = tonumber(status_code),
        status_message = status_message
    }
end

function requests:GET(options)
    local host, path, port = self:unpack_url(options.url)
    local client_socket = self:create_socket(host, port, nil)
    local request_headers = {
        ["Connection"] = "close", -- each socket is only used once, so once we've received all data from the server it can close
        ["Host"] = host,
        ["Accept"] = "application/json"
    }
    for k,v in pairs(options.headers) do request_headers[k] = v end
    local http_get_body = self:build_GET_request(path, request_headers)
    client_socket:send(http_get_body)
    local result = self:parse_response(client_socket:receive("*a"))
    client_socket:close()
    return self:validate(result.status_code, result.status_message, result.data, "GET")
end

function requests:POST(options)
    local sink_table = {}
    local req = self:build_request {
        url = options.url,
        method = "POST",
        headers = options.headers,
        source = ltn12.source.string(assert(options.body, "missing 'body' for POST request")),
        sink = ltn12.sink.table(sink_table)
    }
    local return_code, _, status = socket.skip(1, http.request(req))
    return self:validate(return_code, status, table.concat(sink_table), "POST")
end

function requests:build_url(host, path, params)
    local encoded_params = {}
    for k,v in pairs(params or {}) do
        table.insert(encoded_params, ("%s=%s"):format(k, url.escape(v)))
    end
    return host .. path .. (#encoded_params > 0 and '?' .. table.concat(encoded_params, '&') or "")
end

function requests:build_request(options)
    return {
        url = assert(options.url, "Missing required 'url' opt"),
        method = options.method or "GET",
        headers = options.headers or {},
        sink = assert(options.sink, "Missing required 'sink' opt"),
        source = options.source
    }
end

function requests:validate(return_code, status, result, method)
    local function get_err()
        if type(return_code) == 'string' then -- luasocket failure case
            return return_code
        end
        return ("[HTTP %d ERROR]: %s => %s"):format(return_code, status, result)
    end
    assert(return_code == 200, self.err_msg:format(method, get_err()))
    return result
end

-- TODO we might be able to get away with only downloading when the user selects the sub
function requests:save(uri, path_to_file, headers)
    local sink = ltn12.sink.file(io.open(path_to_file, "wb"))
    local request = self:build_request {
        url = uri,
        method = "GET",
        headers = headers or {},
        sink = sink
    }
    local return_code, _, status = socket.skip(1, http.request(request))
    return self:validate(return_code, status, nil, "GET")
end

return requests
