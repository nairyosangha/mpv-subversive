---@class Thread a runner that runs a Routine
---@field private id string
---@field status status
---@field sock thread|nil this is only present when using the socket backed carrier
---@field routine Routine the workload being run by this thread
local Thread = {}

---@enum status
local STATUS = {
    BUSY = 1,
    IDLE = 2
}
for k,v in pairs(STATUS) do STATUS[v] = k end

function Thread:new(opts)
    local t = {}
    t.id = opts.id
    t.status = STATUS.IDLE
    t.sock = opts.sock
    t.routine = opts.routine
    return setmetatable(t, { __index = self, __tostring = self.__tostring })
end

---@param routine Routine
---@return boolean was_assigned routine was assigned to the current thread
function Thread:assign(routine)
    if self.status ~= STATUS.IDLE then
        return false
    end
    if self.routine and self.routine.co then
        assert(coroutine.status(self.routine.co) == "dead", "Thread marked as IDLE still had non-dead coroutine assigned!")
    end
    self.routine = routine
    routine.thread = self
    self.status = STATUS.BUSY
    return true
end

function Thread:free()
    self.status = STATUS.IDLE
end

function Thread.__tostring(x) return ("Thread<ID:%s STATUS:%s>"):format(x.id or 'N/A', STATUS[x.status]) end


return Thread
