local utils = require "utils.utils"

---@class Response
---@field data string (byte)string containing result of the REST call, or the error message in case of non-200
---@field headers table<string,string>
---@field status_code number status code of the REST call, e.g. 200, 404, ...
---@field status_message string? message corresponding with status_code, e.g. OK, ...

---@class Request
---@field url string URL to query, WITHOUT query parameters
---@field host string? optional if URL is present
---@field path string? optional if URL is present
---@field port number? optional if URL is present
---@field params table<string,string>? query params to pass along
---@field body string? only expected for POST requests
---@field headers table<string,string> HTTP request headers to pass along
---@field path_to_file string? directory to save result of the request in

---@alias method
---| "GET"
---| "POST"

---@class HTTPClient
---@field sync_GET fun(self: HTTPClient, req: Request): Response
---@field async_GET fun(self: HTTPClient, req: Request): Routine<Response>
---@field POST fun(self: HTTPClient, req: Request): Response
local HTTPClient = {
    err_msg = "Invalid %s request: %s",
}
local ok, carrier = pcall(require, "http.socket")
if not ok then
    local result_code = os.execute("curl --version 2>&1 1>/dev/null")
    assert(result_code == 0, "curl command was not found! Unable to initialize")
    carrier = require("http.curl")
end

---@param request Request
---@return Request request with host/path/port added
function HTTPClient:unpack_url(request)
    local _, _, protocol, host, path = request.url:find("(http[s]?)://([^/]+)(.*)$")
    local port = protocol == "https" and 443 or 80
    local query_params = self:get_query_params(request)
    request.url = request.url .. (query_params or "")
    request.host = host
    request.port = port
    request.path = #path > 0 and path  .. query_params or "/"
    return request
end

---@param response string raw HTTP response
---@return Response result containing parsed HTTP resonse
function HTTPClient:parse_response(response)
    local state = 1 -- 1:header, 2:data
    local chunk_size, chunk_data = nil, "" -- only used when we're dealing with chunks
    local response_headers, data = {}, nil
    local function print_headers()
        local header_str = {}
        for k,v in pairs(response_headers) do
            header_str[#header_str+1] = ("%s=\"%s\""):format(k, v)
        end
        return table.concat(header_str, "\n\t - ")
    end
    local _, e, status_code, status_reason = response:find("^HTTP/[.1-3]+ (%d+)%s?([%s%w]*)\r?\n")
    assert(type(e) == "number", ("Could not parse HTTP header from response: \"%s\""):format(({response:find("^(.+)\r?\n")})[3] or response))
    local init_idx = e + 1
    while not data do
        local start_idx, end_idx = response:find("(\r?\n)", init_idx)
        local line = response:sub(init_idx, start_idx and start_idx-1 or #response)
        if #line == 0 then
            state = 2
        elseif state == 1 then
            local _, _, key, value = line:find("^([^:]+): (.+)$")
            response_headers[key:lower()] = value
        elseif state == 2 then
            -- done parsing headers, next up is data
            if response_headers["content-length"] then
                data = response:sub(init_idx, #response)
                assert(#data == tonumber(response_headers["content-length"]), "Read content NOT equal to Content-Length!")
            elseif response_headers["transfer-encoding"] == "chunked" then
                if chunk_size then
                    assert(chunk_size == #line, "Invalid chunk size!")
                    chunk_data = chunk_data .. line
                    chunk_size = nil
                else
                    chunk_size = tonumber(line, 16)
                    if chunk_size == 0 then
                        data = chunk_data
                    end
                end
            else
                error(("Unable to parse response. headers: \n\t - [ %s ],\n remaining response data:\n \"%s\""):format(print_headers(), response:sub(init_idx, #response)))
            end
        end
        init_idx = end_idx and end_idx +1 or #response
    end
    return {
        data = data,
        headers = response_headers,
        status_code = tonumber(status_code),
        status_message = status_reason
    }
end

-- copied from https://github.com/lunarmodules/luasocket/blob/1fad1626900a128be724cba9e9c19a6b2fe2bf6b/src/url.lua#L30C1-L34C4
function HTTPClient.escape(s)
    return (string.gsub(s, "([^A-Za-z0-9_])", function(c)
        return string.format("%%%02x", string.byte(c))
    end))
end

function HTTPClient:get_query_params(request)
    local encoded_params = {}
    for k,v in pairs(request.params or {}) do
        table.insert(encoded_params, ("%s=%s"):format(k, self.escape(v)))
    end
    return #encoded_params > 0 and '?' .. table.concat(encoded_params, '&') or ""
end

---@param response Response
---@param method method
---@return Response response
function HTTPClient:validate(response, method)
    local function get_err()
        if type(response.status_code) == 'string' then -- luasocket failure case
            error(response.status_code)
        end
        return ("[HTTP %d ERROR]: %s => %s"):format(response.status_code, response.status_message, response.data)
    end
    assert(response.status_code == 200, self.err_msg:format(method, get_err()))
    return response
end

---@param request Request
function HTTPClient:sync_save(request)
    local result = self:sync_GET(request)
    utils.open_file(assert(request.path_to_file, "Missing path to file!"), 'wb', function(f) f:write(result.data) end)
end

---@param request Request
---@return Routine<nil>
function HTTPClient:async_save(request)
    return self:async_GET(request):on_complete(function(result)
        utils.open_file(assert(request.path_to_file, "Missing path to file!"), 'wb', function(f) f:write(result.data) end)
    end)
end

return setmetatable(HTTPClient, { __index = function(t, k) return rawget(t, k) or carrier[k] end })
