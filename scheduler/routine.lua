---@class Routine<T> a workload executed in a coroutine
---@field protected create_coroutine_func function
---@field protected on_complete_cb function
---@field protected on_incomplete_cb function
---@field private id string
---@field co thread
---@field private polling_type string
---| 'callback' the coroutine completes itself when doing callback, so when coroutine is dead we're done
---| 'checked' the coroutine should be resumed until it stops yielding and completes fully
---@field thread Thread
---@field private callback_result table|nil contains the result of the callback, only used when polling_type == 'callback'
---@field on_complete fun(self: Routine, function): Routine
---@field on_incomplete fun(self: Routine, function): Routine
local Routine = {}

---@return Routine
function Routine:new(opts)
    local r = {}
    r.id = opts.id
    r.polling_type = opts.polling_type
    r.create_coroutine_func = assert(opts.create_coroutine_func, "Missing init function for new Routine")
    -- takes in the result, returns boolean indicating if the result was valid or not
    r.on_complete_cb = opts.on_complete_cb or function() return true end
    -- takes in the result, which is still incomplete, this can be used to check the headers to get a % downloaded
    r.on_incomplete_cb = opts.on_incomplete_cb or function() end
    return setmetatable(r, { __index = self, __tostring = self.__tostring })
end

---@return any|nil result of the routine, or nil when routine wasn't finished yet
function Routine:run()
    if not self.thread then
        return nil
    end
    if not self.co then
        self.co = coroutine.create(function() return self.create_coroutine_func(self) end)
        if self.polling_type == 'callback' then
            coroutine.resume(self.co, self)
        end
    end

    local result = nil
    if self.polling_type == 'checked' then
        local ok, result_if_ok = coroutine.resume(self.co, self)
        assert(ok, ("Error during running of coroutine: %s"):format(tostring(result_if_ok) or ""))
        if coroutine.status(self.co) == "suspended" then
            return self.on_incomplete_cb(result_if_ok)
        end
        result = result_if_ok
    elseif self.polling_type == 'callback' then
        if coroutine.status(self.co) ~= "dead" then
            return nil
        end
        result = self.callback_result
    else
        error(("Invalid polling type %s"):format(self.polling_type))
    end

    self:unassign()
    print(("Finished running routine %s"):format(tostring(self)))
    return result
end

function Routine:unassign()
    self.thread:free()
    self.thread = nil
    self.co = nil
end

---@param func fun(result: Response): boolean
---@return Routine<Response>
function Routine:on_complete(func)
    self.on_complete_cb = func
    return self
end

function Routine:on_incomplete(func)
    self.on_incomplete_cb = func
    return self
end

function Routine.__tostring(x)
    return ("Routine<ID:%s STATUS:%s>"):format(x.id or "N/A", x.co and coroutine.status(x.co) or "init")
end



return Routine
