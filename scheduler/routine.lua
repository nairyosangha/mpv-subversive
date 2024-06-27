local Routine = {}

function Routine:new(opts)
    local r = {}
    r.id = opts.id
    r.create_coroutine_func = assert(opts.create_coroutine_func, "Missing init function for new Routine")
    r.on_complete_cb = opts.on_complete_cb or function(result) return result end
    return setmetatable(r, { __index = self, __tostring = self.__tostring })
end

function Routine:run()
    if not self.thread then
        return
    end
    if not self.co then
        self.co = coroutine.create(function() return self.create_coroutine_func(self.thread) end)
    end
    return self.thread:resume()
end

function Routine:unassign()
    self.thread = nil
    self.co = nil
end

function Routine:on_complete(func)
    self.on_complete_cb = func
end

function Routine.__tostring(x)
    return ("Routine<ID:%s STATUS:%s>"):format(x.id or "N/A", x.co and coroutine.status(x.co) or "init")
end



return Routine
