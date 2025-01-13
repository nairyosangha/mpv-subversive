local Client = require 'http.client'
local json = require 'json'
local u = require 'utils.utils'

local ARCHIVE_DIR = './mapping'
local LAST_TIME_RUN_FILE = '.last_time'
local headers = { ["Authorization"] = '' }
local last_run = u.open_file(ARCHIVE_DIR..'/'..LAST_TIME_RUN_FILE, 'r', function(f) return json.decode(f:read("*a")) end) or {}

local function to_epoch(timestamp)
    local _,_, year, month, day, hour, minute, second = timestamp:find("(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+).?%d*[Z0-9.:]+")
    return os.time({ year=year, month=month, day=day, hour=hour, minute=minute, second=second })
end

local function GET(opts)
    local result = Client:sync_GET(opts)
    local reset_after_seconds = result.headers['x-ratelimit-reset-after']
    if reset_after_seconds then
        os.execute(("sleep %f"):format(tonumber(reset_after_seconds) + 1))
    end
    if result.status_code == 429 then
        print(("[STATUS %d] Too many requests, reset after: %.2f"):format(result.status_code, reset_after_seconds))
        result = GET(opts)
    end
    return result
end

local function get_modified(GET_opts, get_id_fn, in_place)
    local items = assert(json.decode(GET(GET_opts).data), "Could not decode JSON")
    table.sort(items, function(a,b) return a.name > b.name end)
    return function()
        while true do
            local item = table.remove(items)
            if not item then return end
            item.was_modified = (last_run[get_id_fn(item)] or 1) <= to_epoch(item.last_modified)
            if item.was_modified or in_place then
                print("Handling item", item.name)
                return item
            end
        end
    end
end


local new_mapping = {}
local function save_last_run()
    u.open_file(ARCHIVE_DIR..'/'..LAST_TIME_RUN_FILE, 'w', function(f) f:write(json.encode(last_run)) end)
    u.open_file('./mapping.csv', 'w', function(f) f:write(table.concat(new_mapping, '\n')) end)
    os.exit(0)
end
local sig = require('posix.signal')
if sig then
    sig.signal(sig.SIGINT, save_last_run)
    sig.signal(sig.SIGQUIT, save_last_run)
end

local function entry_id(e) return tostring(e.id) end
for entry in get_modified({ url = "https://jimaku.cc/api/entries/search", headers = headers }, entry_id, true) do
    local directory = ARCHIVE_DIR..'/'..(entry.name or entry.english_name or entry.japanese_name)
    if entry.was_modified then
        os.execute(("mkdir -p %q"):format(directory))
        local function file_id(f) return entry_id(entry)..':'..f.name end
        for file in get_modified({ id = entry.name, url = ("https://jimaku.cc/api/entries/%s/files"):format(entry.id), headers = headers }, file_id) do
            if not u.path_exists(directory..'/'..file.name) then
                local file_response = GET { id = entry.english_name, url = file.url, headers = headers }
                u.open_file(directory..'/'..file.name, 'w', function(f) f:write(file_response.data) end)
            else
                print(("already downloaded: %s"):format(file.name))
            end
            last_run[file_id(file)] = os.time()
        end
        last_run[entry_id(entry)] = os.time()
    end
    new_mapping[#new_mapping+1] = ("%s,%q"):format(entry.anilist_id, directory)
    -- uncomment this if you don't have luaposix installed, otherwise killing the process will mean everything gets downloaded again
    -- if #new_mapping % 10 == 0 then save_last_run() end
end
save_last_run()
