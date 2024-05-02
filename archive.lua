local utils = require 'utils/utils'

local archive = {}
local archive_mt = { __index = archive }
local ZIP = setmetatable({}, archive_mt)
local RAR = setmetatable({}, archive_mt)
local mapper = { ZIP = ZIP, RAR = RAR }

-- execute command and return exit code
local function execute(cmd)
    if _VERSION == "Lua 5.1" then
        return os.execute(cmd)
    elseif _VERSION == "Lua 5.2" then
        local success, exit, code = os.execute(cmd)
        return exit == "exit" and code or 1
    end
    assert(true, ("Unsupported lua version: %s!"):format(_VERSION))
end

function archive:new(file_path)
    assert(utils.path_exists(file_path), string.format("INVALID PATH '%s'!", file_path))
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

function ZIP:check_valid()
    return execute(string.format("unzip -t %q", self.path)) == 0
end

function RAR:check_valid()
    return execute(string.format("rar t %q", self.path)) == 0
end

-- [] are expanded as pattern in unzip command, to 'escape' them '[' is replaced with '[[]'
function ZIP:replace_left_brackets(filter)
    if filter == nil then return nil end
    local replaced = {}
    for _,v in ipairs(filter) do
        local v_replaced, count = string.gsub(v, "%[", "[[]")
        replaced[#replaced+1] = v_replaced
    end
    return replaced
end

function ZIP:extract(args)
    local cmd_str = 'unzip -jo %q %s -d %q'
    local cmd = cmd_str:format(self.path, self:build_filter(self:replace_left_brackets(args.filter)), args.target_path or ".")
    return utils.iterate_cmd(cmd)
end

function RAR:extract(args)
    local cmd_str = 'unrar e -o+ %q %s %q'
    local cmd = cmd_str:format(self.path, self:build_filter(args.filter), args.target_path or ".")
    return utils.iterate_cmd(cmd)
end
return archive
