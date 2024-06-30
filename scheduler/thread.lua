local socket = require("socket")
local requests = require("requests")

local Thread = {}
local STATUS = { BUSY = 1, IDLE = 2 }
for k,v in pairs(STATUS) do STATUS[v] = k end

function Thread:new(opts)
    local t = {}
    t.id = opts.id
    t.status = STATUS.IDLE
    t.sock = opts.sock
    t.routine = opts.routine
    return setmetatable(t, { __index = self, __tostring = self.__tostring })
end

function Thread:assign(routine)
    if self.status ~= STATUS.IDLE then
        return nil
    end
    if self.routine then
        assert(coroutine.status(self.routine.co) == "dead", "Thread marked as IDLE still had non-dead coroutine assigned!")
    end
    self.routine = routine
    routine.thread = self
    self.status = STATUS.BUSY
    return true
end

function Thread:resume()
    if not self.routine then
        return
    end
    local ok, status, result = coroutine.resume(self.routine.co, self)
    assert(ok, ("Error during running of coroutine: %s"):format(status or ""))
    if status == STATUS.IDLE then
        self.status = STATUS.IDLE
        self.routine = self.routine:unassign()
        return result
    end
end

function Thread.__tostring(x) return ("Thread<ID:%s STATUS:%s>"):format(x.id or 'N/A', STATUS[x.status]) end


return Thread
