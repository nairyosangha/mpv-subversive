local utils = {}
function utils.get_extension(filename)
	return filename:match("%.([%a]+)$")
end

function utils.path_exists(path)
	local f = io.open(path, 'r')
	if f then
		f:close()
		return true
	end
	return false
end

function utils.run_cmd(cmd)
	local output = {}
	local f = io.popen(cmd, 'r')
	for line in f:lines("*l") do
		table.insert(output, line)
	end
	f:close()
	return output
end

function utils.iterate_cmd(cmd)
	local output = {}
	local f = io.popen(cmd, 'r')
	for line in f:lines("*l") do
		table.insert(output, line)
	end
	f:close()
	return function()
		return table.remove(output, 1)
	end
end

function utils.strip_path(path)
	local stripped = string.match(path, "^.*/([^/]+)$")
	print(stripped)
	return stripped
end

function utils.dir_name(path)
	return utils.run_cmd(string.format("dirname %q", path))[1]
end

function utils.is_numeric(str)
	return string.match(str, "^-?[%d%.]+$")
end
return utils
