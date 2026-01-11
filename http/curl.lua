local mp = require 'mp'
local scheduler = require("scheduler.scheduler")
local Routine = require("scheduler.routine")

---@class CURL : HTTPClient curl-backed implementation
---@field schedulers table<string,Scheduler> scheduler instance for each host:port string
---@field default_headers table<string,string> headers to add to all HTTP requests
local CURL = {
    schedulers = {},
    default_headers = {
        ["Connection"] = "close",
        ["Accept"] = "application/json"
    }
}

---@return Scheduler scheduler
function CURL:get_scheduler(host, port)
    local key = host .. ':' .. port
    if not self.schedulers[key] then
        self.schedulers[key] = scheduler.new {
            carrier = "curl",
            host = host,
            port = port,
            thread_count = 3,
        }
    end
    return self.schedulers[key]
end

---@param request Request
---@return string[]
function CURL:build_curl_cmd(request, method)
    local request_headers = { ["Host"] = request.host }
    for k, v in pairs(self.default_headers) do request_headers[k] = v end
    for k, v in pairs(request.headers) do request_headers[k] = v end
    local curl_args = {}
    local function add_args(...)
        for _, arg in ipairs({ ... }) do table.insert(curl_args, arg) end
    end
    local function add_header(k, v) add_args("--header", ("%s: %s"):format(k, v)) end
    add_args("curl", "-i", "--http1.1", "--raw")
    add_args("-X", (assert(method, "Missing method! Expected GET or POST")))
    if method == "POST" then
        add_args("--data", (assert(request.body, "Missing data for POST request")))
    end
    for k, v in pairs(request_headers) do add_header(k, v) end
    add_args(request.url)
    print(table.concat(curl_args, " "))
    return curl_args
end

---@param request Request
---@return Response response
function CURL:sync_GET(request)
    request = self:unpack_url(request)
    local result, error = mp.command_native({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        args = CURL:build_curl_cmd(request, "GET")
    })
    assert(result, ("Could not complete curl command! %s"):format(error))
    local response = self:parse_response(result.stdout)
    return response
end

---@param request Request
---@return Routine<Response> response
function CURL:async_GET(request)
    request = self:unpack_url(request)
    local init_func = function(routine)
        mp.command_native_async({
            name = "subprocess",
            capture_stdout = true,
            capture_stderr = true,
            args = CURL:build_curl_cmd(request, "GET")
        }, function(success, result, error)
            assert(success, ("Could not complete curl command! %s"):format(error))
            routine.callback_result = self:parse_response(result.stdout)
            coroutine.resume(routine.co) -- this should end the coroutine
        end)
        coroutine.yield()
    end
    local routine = Routine:new {
        id = assert(request.id or request.path),
        polling_type = 'callback',
        create_coroutine_func = init_func,
    }
    return CURL:get_scheduler(request.host, request.port):schedule(routine)
end

---@param request Request
---@return Response response
function CURL:POST(request)
    request = self:unpack_url(request)
    local result, error = mp.command_native({
        name = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        args = CURL:build_curl_cmd(request, "POST")
    })
    assert(result, ("Could not complete curl command! %s"):format(error or ""))
    return self:parse_response(result.stdout)
end

return CURL
