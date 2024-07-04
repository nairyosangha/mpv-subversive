local socket = require("socket")
local requests = require("requests")
local Thread = require("scheduler.thread")
local Routine = require("scheduler.routine")

local Scheduler = {}
local STATUS = { BUSY = 1, IDLE = 2 }
for k,v in pairs(STATUS) do STATUS[v] = k end

function Scheduler.new(host, port, thread_count, default_headers)
    local sched = { threads = {}, sockets = {}, routines = {} }
    for i=1, thread_count do
        -- make it so the receive call returns immediately, instead of blocking, this means we can get a timeout ('wantread')
        local sock = requests:create_socket(host, port, 0)
        table.insert(sched.threads, Thread:new { sock = sock, id = i })
        table.insert(sched.sockets, sock)
    end
    sched.default_headers = {}
    for k,v in pairs(default_headers) do sched.default_headers[k] = v end
    return setmetatable(sched, { __index = function(t, k) return rawget(t, k) or Scheduler[k] end })
end

function Scheduler:schedule(opts)
    local all_headers = {}
    for k,v in pairs(self.default_headers) do all_headers[k] = v end
    for k,v in pairs(opts.headers or {}) do all_headers[k] = v end
    local init_func = function(thread)
        while true do
            thread.sock:send(requests:build_GET_request(opts.path, all_headers))
            local _, res = requests.async:GET(thread.sock)
            return res
        end
    end
    local routine = Routine:new {
        id = assert(opts.path, "Missing required 'path'"),
        create_coroutine_func = init_func,
        on_complete_cb = opts.on_complete_cb,
        on_incomplete_cb = opts.on_incomplete_cb
    }
    table.insert(self.routines, routine)
    return routine
end

function Scheduler:assign_thread(routine)
    for _,thread in ipairs(self.threads) do
        if thread:assign(routine) then
            print(("Assigned routine %s to thread %s"):format(tostring(routine), tostring(thread)))
            return thread
        end
    end
end

function Scheduler:poll()
    if self:is_timed_out() then
        print(("We have to wait for %d more seconds!"):format(self.timeout_reset - socket.gettime()))
        return {}
    end
    local finished_results = {}
    for _, routine in ipairs(self.routines) do
        if not routine.thread then self:assign_thread(routine) end
    end
    for i=#self.routines, 1, -1 do
        local routine = self.routines[i]
        local finished_result = routine:run()
        if finished_result then
            if routine.on_complete_cb(finished_result) then
                table.insert(finished_results, finished_result)
                table.remove(self.routines, i)
            end
            if self:is_rate_limited(finished_result.headers) then break end
        end
    end
    return finished_results
end

function Scheduler:wait()
    local all_finished = {}
    while true do
        for _,res in ipairs(self:poll()) do
            table.insert(all_finished, res)
        end
        if not self:has_remaining() then
            break
        end
        socket.select(self.sockets, {}, 1)
    end
    return all_finished
end

function Scheduler:quit()
    print("Closing all sockets")
    for _,sock in ipairs(self.sockets) do sock:close() end
end

function Scheduler:is_rate_limited(headers)
    local current_time = socket.gettime()
    -- subtract the amount of threads because at the time we see this, there might be already #threads more requests in progress
    local requests_left = (tonumber(headers['x-ratelimit-remaining']) or #self.threads+2) - #self.threads
    local reset_time    = headers['x-ratelimit-reset']
    local reset_offset  = headers['x-ratelimit-reset-after']
    if requests_left <= 1 then
        if reset_offset then
            self:set_timeout((self.timeout_reset or current_time) + tonumber(reset_offset))
        else
            self:set_timeout(tonumber(reset_time) or current_time)
        end
        return true
    end
end
function Scheduler:has_remaining() return #self.routines > 0 end
function Scheduler:is_timed_out() return self.timeout_reset and self.timeout_reset > socket.gettime() end

function Scheduler:set_timeout(reset_time, current_time)
    current_time = current_time or socket.gettime()
    if reset_time < current_time then
        return print(("Tried setting timeout %d which is before the current time %d!"):format(reset_time, current_time))
    end
    if self.timeout_reset and self.timeout_reset > reset_time then
        return print("skipping, we already have a higher reset time set")
    end
    self.timeout_reset = reset_time
    print(("Set timeout_reset to %d (current time: %d)"):format(self.timeout_reset, current_time))
end

return Scheduler
