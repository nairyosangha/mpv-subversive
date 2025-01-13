local Thread = require("scheduler.thread")
local socket
local ok, res = pcall(require, "socket")
if ok then
    socket = res
end

---@class Scheduler responsible for running routines on threads
---@field threads table containing all threads, this number should be limited
---@field routines table containing all routines that still need to be run, only #threads number of routines run 'concurrently'
local Scheduler = {}

function Scheduler.new(opts)
    local new = {
        threads = {},
        routines = {}
    }
    for i=1, assert(opts.thread_count, "Missing opt thread_count") do
        table.insert(new.threads, Thread:new { id = i })
        if opts.init_thread_func then opts.init_thread_func(new.threads[#new.threads]) end
    end
    return setmetatable(new, { __index = function(t, k) return rawget(t, k) or Scheduler[k] end })
end

function Scheduler:schedule(routine)
    table.insert(self.routines, routine)
    return routine
end

function Scheduler:assign_thread(routine)
    for _,thread in ipairs(self.threads) do
        if thread:assign(routine) then
            --print(("Assigned routine %s to thread %s"):format(tostring(routine), tostring(thread)))
            return thread
        end
    end
end

function Scheduler:poll()
    if self:is_timed_out() then
        print(("We have to wait for %d more seconds!"):format(self.timeout_reset - self:get_time()))
        return {}
    end
    local finished_results = {}
    for _, routine in ipairs(self.routines) do
        if not routine.thread then self:assign_thread(routine) end
    end
    for i=#self.routines, 1, -1 do
        local finished_result = self.routines[i]:run()
        if finished_result then
            local cb_res, err = self.routines[i].on_complete_cb(finished_result)
            assert(type(cb_res) == "boolean", ("%s did not return boolean in on_complete_cb() (got %s=%s)"):format(tostring(self), type(cb_res), tostring(cb_res)))
            if cb_res then
                table.insert(finished_results, finished_result)
                table.remove(self.routines, i)
            else
                print(err)
            end
            if self:is_rate_limited(finished_result.headers) then break end
        end
    end
    return finished_results
end

function Scheduler:quit()
    print("Closing all sockets")
    for _,th in ipairs(self.threads or {}) do
        if th.sock then th.sock:close() end
    end
end

function Scheduler:is_rate_limited(headers)
    local current_time = self:get_time()
    -- subtract the amount of threads because at the time we see this, there might be already #threads more requests in progress
    local requests_left = (tonumber(headers['x-ratelimit-remaining']) or #self.threads+2) - #self.threads
    local reset_time    = headers['x-ratelimit-reset']
    local reset_offset  = headers['x-ratelimit-reset-after']
    -- print(("current_time: %f, reqs left: %d, reset time: %d, reset_offset: %d"):format(current_time, requests_left or -1, reset_time or -1, reset_offset or -1))
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
function Scheduler:is_timed_out() return self.timeout_reset and self.timeout_reset > self:get_time() end

function Scheduler:set_timeout(reset_time, current_time)
    current_time = current_time or self:get_time()
    if reset_time < current_time then
        return print(("Tried setting timeout %d which is before the current time %d!"):format(reset_time, current_time))
    end
    if self.timeout_reset and self.timeout_reset > reset_time then
        return print("skipping, we already have a higher reset time set")
    end
    self.timeout_reset = reset_time
    print(("Set timeout_reset to %d (current time: %d)"):format(self.timeout_reset, current_time))
end

function Scheduler:get_time()
    if socket
        then return socket:gettime()
    end
    return os.time()
end


return Scheduler
