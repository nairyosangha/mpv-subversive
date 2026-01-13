require 'utils.sequence'
local HTTPClient = require("http.client")
local mp = require 'mp'
local mpu = require 'mp.utils'

local jimaku = {
    BASE_URL = "https://jimaku.cc/api/",
}

function jimaku:get_scheduler()
    return HTTPClient:get_scheduler("jimaku.cc", 443)
end

---Extract all subtitles which are available for the given ID
---@param show_info table containing title, ep_number and anilist_data
---@return table containing all subtitles for the given show, with optional error field if something went wrong
function jimaku:query_subtitles(show_info)
    if not self.API_TOKEN or self.API_TOKEN == "" then
        return { error = "no API_TOKEN available! Cannot do lookup." }
    end
    local anilist_id = show_info.anilist_data.id
    mp.osd_message(("Finding matching subtitles for AniList ID '%s'"):format(anilist_id), 3)
    -- we don't need this here, but this takes a sec to load, and it feels better to do it here
    self:get_scheduler()
    local response = HTTPClient:sync_GET {
        url = self.BASE_URL .. "entries/search",
        params = { anilist_id = anilist_id },
        headers = { ["Authorization"] = self.API_TOKEN }
    }
    if response.status_code ~= 200 then
        return { error = ("Unexpected return code: %d: %s"):format(response.status_code, response.data) }
    end
    local entries, err = mpu.parse_json(response.data)
    assert(entries, err)
    local cached_path = self:get_cached_path(show_info)
    os.execute(string.format("mkdir -p %q", cached_path))

    local items = {}
    for _, entry in ipairs(entries) do
        for _, file in ipairs(self:get_files(entry.id)) do
            file.is_archive = self:is_supported_archive(file.name)
            file.matching_episode = self:is_matching_episode(show_info, file.name)
            file.absolute_path = cached_path .. '/' .. file.name
            local _, _, year, month, day, hour, minute, second = string.find(file.last_modified,
                "(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+).?%d*Z")
            assert(year, ("Could not parse last_modified time '%s'"):format(file.last_modified))
            file.last_modified = os.time({
                year = year,
                month = month,
                day = day,
                hour = hour,
                minute = minute,
                second = second
            })
            table.insert(items, file)
        end
    end
    return items
end

function jimaku:get_files(entry_id)
    local response = HTTPClient:sync_GET {
        url = self.BASE_URL .. ("entries/%s/files"):format(entry_id),
        headers = { ["Authorization"] = self.API_TOKEN }
    }
    local result, err = mpu.parse_json(response.data)
    return assert(result, err)
end

---@return Routine
function jimaku:download_subtitle(file_entry)
    return HTTPClient:async_GET {
        url = file_entry.url,
        headers = { ["Accept"] = "application/octet-stream" }
    }
end

return jimaku
