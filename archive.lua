local utils = require 'utils'

local archive = {}
local archive_mt = { __index = archive }
local ZIP = setmetatable({}, archive_mt)
local RAR = setmetatable({}, archive_mt)
local mapper = { ZIP = ZIP, RAR = RAR }

function archive:new(file_path)
	assert(utils.path_exists(file_path), "INVALID PATH!")
	self.ext = utils.get_extension(file_path) or ""
	self.path = file_path
	return setmetatable({}, { __index = mapper[self.ext:upper()] or self })
end

function archive:build_filter(filters)
	if filters == nil then return "*" end
	local str_builder = ""
	for _,f in pairs(filters) do
		str_builder = str_builder .. string.format(" %q ", f)
	end
	return str_builder
end

function ZIP:list_files(args)
	local cmd_str = 'unzip -Z -1 %q %s'
	local cmd = cmd_str:format(self.path, self:build_filter(args.filter))
	return utils.iterate_cmd(cmd)
end

function RAR:list_files(args)
	local cmd_str = 'unrar lb %q %s'
	local cmd = cmd_str:format(self.path, self:build_filter(args.filter))
	return utils.iterate_cmd(cmd)
end

function ZIP:extract(args)
	local cmd_str = 'unzip -jo %q %s -d %q'
	local cmd = cmd_str:format(self.path, self:build_filter(args.filter), args.target_path or ".")
	return utils.iterate_cmd(cmd)
end

function RAR:extract(args)
	local cmd_str = 'unrar e -o+ %q %s %q'
	local cmd = cmd_str:format(self.path, self:build_filter(args.filter), args.target_path or ".")
	return utils.iterate_cmd(cmd)
end
return archive
