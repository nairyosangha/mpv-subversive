local regex = {}
function Regex(pattern, capture_groups)
	return setmetatable({ pattern = pattern, capture_groups = capture_groups }, { __index = regex })
end

function regex:match(str)
	local function _group(packed_matches)
		local function _get_capture_idx(idx)
			return self.capture_groups and string.byte(self.capture_groups, idx, idx) or idx
		end
		local groups = {}
		for idx, match in ipairs(packed_matches) do
			groups[_get_capture_idx(idx)] = match
		end
		return groups
	end
	self.matches = _group(table.pack(str:match(self.pattern)))
	return #self.matches > 0
end

function regex:groups()
	return table.unpack(self.matches)
end

function regex:count_capture_groups()
	local sum = 0
	for _ in string.gmatch(self.pattern, "%(..-[^%%]%)") do
		sum = sum + 1
	end
	return sum
end
