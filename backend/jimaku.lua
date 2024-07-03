require 'utils.sequence'
local requests = require 'requests'
local mp = require 'mp'
local mpu = require 'mp.utils'
local scheduler = require 'scheduler.scheduler'

local jimaku = {
    BASE_URL = "https://jimaku.cc/api/",
    thread_count = 3,
}

function jimaku:get_scheduler()
    if not self.scheduler then
        self.scheduler = scheduler.new("jimaku.cc", 443, self.thread_count, { ["Authorization"] = self.API_TOKEN })
    end
    return self.scheduler
end

---Extract all subtitles which are available for the given ID
---@param show_info table containing title, ep_number and anilist_data
---@return table containing all subtitles for the given show
function jimaku:query_subtitles(show_info)
    local anilist_id = show_info.anilist_data.id
    mp.osd_message(("Finding matching subtitles for AniList ID '%s'"):format(anilist_id), 3)
    local response = requests:GET {
        url = requests:build_url(self.BASE_URL, "entries/search", { anilist_id = anilist_id }),
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = self.API_TOKEN
        }
    }
    local entries, err = mpu.parse_json(response)
    assert(entries, err)
    local cached_path = self:get_cached_path(show_info)
    os.execute(string.format("mkdir -p %q", cached_path))

    local items = {}
    for _, entry in ipairs(entries) do
        for _, file in ipairs(self:get_files(entry.id)) do
            file.is_archive = self:is_supported_archive(file.name)
            file.matching_episode = self:is_matching_episode(show_info, file.name)
            file.absolute_path = cached_path .. '/' .. file.name
            table.insert(items, file)
        end
    end
    return items
end

function jimaku:get_files(entry_id)
    local response = requests:GET {
        url = requests:build_url(self.BASE_URL, ("entries/%s/files"):format(entry_id)),
        headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = self.API_TOKEN
        }
    }
    local result, err = mpu.parse_json(response)
    return assert(result, err)
end

function jimaku:download_subtitle(file_entry)
    local host, path, _ = requests:unpack_url(file_entry.url)
    local headers = {
        ["Host"] = host,
        ["Accept"] = "application/octet-stream",
        ["Connection"] = "keep-alive",
    }
    return self:get_scheduler():schedule { path = path,  headers = headers }
end

return jimaku
