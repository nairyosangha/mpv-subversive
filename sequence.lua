local seq = {}
local seq_mt = {
	__index = seq,
	__tostring = function(x) return "{ " .. table.concat(x.items, ", ") .. " }" end
}

function Sequence(args)
	return setmetatable({ items = args, size = #args }, seq_mt)
end

function seq:filter(predicate)
	local filtered = {}
	for k,v in pairs(self.items) do
		if predicate(v) then
			filtered[k] = v
		end
	end
	return Sequence(filtered)
end

function seq:map(mapper)
	local mapped = {}
	for k,v in pairs(self.items) do
		mapped[k] = mapper(v)
	end
	return Sequence(mapped)
end

function seq:foreach(habbening)
	for _,v in pairs(self.items) do
		local _ = habbening(v)
	end
end

function seq:find_first(predicate)
	for k,v in pairs(self.items) do
		if predicate(v) == true then
			return k,v
		end
	end
end
