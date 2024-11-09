local headers = require("socket.headers")
local socket = require("socket")
local ssl = require("ssl")
local scheduler = require("scheduler.scheduler")
local Routine = require("scheduler.routine")


---@class SOCKET : HTTPClient socket-backed implementation
---@field schedulers table<string,Scheduler> scheduler instance for each host:port string
---@field sync_default_headers table<string,string> headers to add to all sync HTTP requests
---@field async_default_headers table<string,string> headers to add to all async HTTP requests
---@field ssl_params table<string,string|string[]> table used to configure SSL for HTTPS requests
local SOCKET = {
    schedulers = {},
    sync_default_headers = {
        ["Connection"] = "close",
        ["Accept"] = "application/json"
    },
    async_default_headers = {
        ["Connection"] = "keep-alive",
        ["Accept"] = "application/json"
    },
    err_msg = "Invalid %s request: %s",
    ssl_params = {
        mode = "client",
        protocol = "tlsv1_3",
        verify = "none",
        cafile = "/etc/ssl/certs/ca-certificates.crt",
        options = {"all", "no_sslv2", "no_sslv3", "no_tlsv1" }
    },
}

---@return Scheduler scheduler
function SOCKET:get_scheduler(host, port)
    local key = host..':'..port
    if not self.schedulers[key] then
        self.schedulers[key] = scheduler.new {
            carrier = "socket",
            host = host,
            port = port,
            thread_count = 3,
            init_thread_func = function(th)
                -- set timout to 0, to make it so the receive call returns immediately, 
                -- instead of blocking, this means we can get a timeout ('wantread')
                th.sock = self:create_socket(host, port, 0)
            end
        }
    end
    return self.schedulers[key]
end

---@return table socket HTTP(S) client socket
function SOCKET:create_socket(host, port, timeout)
    local client_socket = assert(socket.tcp(), "Could not create TCP client socket")
    assert(client_socket:connect(host, port), "Could not connect to host")
    if port == 443 then
        client_socket = assert(ssl.wrap(client_socket, self.ssl_params), "Could not create SSL connection")
        client_socket:sni(host)
        local ok, msg = client_socket:dohandshake()
        assert(ok, ("SSL handshake failed: %s"):format(msg))
    end
    client_socket:settimeout(timeout)

    return client_socket
end

---@param request Request
---@param method method
---@param default_headers table<string,string>
---@return string HTTP_message
function SOCKET:build_request(request, method, default_headers)
    local request_headers = { ["Host"] = request.host }
    for k,v in pairs(default_headers) do request.headers[k] = v end
    for k,v in pairs(request.headers) do request_headers[k] = v end
    if method == "POST" then
        request_headers["Content-Type"] = "application/json"
        request_headers["Content-Length"] = #request.body
    end
    local request_table = {}
    table.insert(request_table, ("%s %s HTTP/1.1\r\n"):format(method, request.path))
    for k,v in pairs(request_headers) do
        table.insert(request_table, ("%s: %s\r\n"):format(headers.canonic[k] or k, v))
    end
    table.insert(request_table, "\r\n")
    if method == "POST" then
        table.insert(request_table, request.body)
    end
    return table.concat(request_table, "")
end

---@param request Request
---@return Response result
function SOCKET:sync_GET(request)
    request = self:unpack_url(request)
    local client_socket = self:create_socket(request.host, request.port, nil)
    local http_get_body = self:build_request(request, "GET", self.sync_default_headers)
    client_socket:send(http_get_body)
    local response = self:parse_response(client_socket:receive("*a"))
    client_socket:close()
    return self:validate(response, "GET")
end

---@param request Request
---@return Routine<Response> result
function SOCKET:async_GET(request)
    request = self:unpack_url(request)
    local init_func = function(routine)
        routine.thread.sock:send(self:build_request(request, "GET", self.async_default_headers))
        local parser, status_parser, header_parser, response_parser
        local partials = {}

        local response = { headers = {} }

        ---@param pattern string request data from socket
        ---@param id string to store/identify partial content
        ---@return boolean indicating if we're done
        ---@return string with the read data (if we're done)
        local function read(pattern, id)
            local result, status, partial = routine.thread.sock:receive(pattern)
            if status then
                if partial and #partial > 0 then
                    --print(("Got partial (size %d), requested %s (current size: %d)"):format(#partial, pattern, partials[id] and #partials[id] or 0))
                    partials[id] = (partials[id] or '') .. partial
                end
                return false, status
            end
            if partials[id] then
                result = partials[id] .. result
                partials[id] = nil
            end
            return true, result
        end

        function status_parser()
            local is_done, status_line = read("*l", "status_line")
            if is_done then
                local _, _, status_code, status_message = status_line:find("^HTTP/1.1 (%d+) ([%s%w]+)$")
                response['status_code'] = tonumber(status_code)
                response['status_message'] = status_message
                parser = header_parser
            end
            return is_done
        end

        function header_parser()
            local is_done, header = read("*l", "header")
            if is_done then
                if #header == 0 then
                    parser = response_parser
                else
                    local _, _, key, value = header:find("^([^:]+): (.+)$")
                    response['headers'][key] = value
                end
                return true
            end
        end

        function response_parser()
            local already_read = partials['response'] and #partials['response'] or 0
            local is_done, data = read(response.headers['content-length'] - already_read, 'response')
            -- we pass in incomplete data, the coroutine can return incomplete results so we can tell how much we downloaded so far
            response['data'] = partials['response']
            if is_done then
                response['data'] = data
                parser = nil
                return true
            end
        end

        parser = status_parser
        while parser do
            if not parser() then
                coroutine.yield(response)
            end
        end
        return self:validate(response, "GET")
    end
    local routine = Routine:new {
        id = assert(request.path, "Missing required 'path'"),
        polling_type = 'checked',
        create_coroutine_func = init_func,
    }
    return self:get_scheduler(request.host, request.port):schedule(routine)
end

---@param request Request
---@return Response result
function SOCKET:POST(request)
    request = self:unpack_url(request)
    local client_socket = self:create_socket(request.host, request.port, nil)
    local send_res, send_err = client_socket:send(self:build_request(request, "POST", self.sync_default_headers))
    assert(send_res, ("Error while sending data to socket: %s"):format(send_err))
    local recv_res, recv_err = client_socket:receive("*a")
    assert(recv_res, ("Error while sending data to socket: %s"):format(recv_err))
    local response = self:parse_response(recv_res)
    client_socket:close()
    return self:validate(response, "POST")
end

return SOCKET
