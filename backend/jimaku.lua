require 'utils.sequence'
local requests = require 'requests'
local mp = require 'mp'
local mpu = require 'mp.utils'

local jimaku = {
    BASE_URL = "https://jimaku.cc/api/"
}

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
    local file_filter = function(file_entry)
        return file_entry.is_archive or self:is_matching_episode(show_info, file_entry.name)
    end
    local cached_path = self:get_cached_path(show_info)
    os.execute(string.format("mkdir -p %q", cached_path))

    local items = {}
    for _, entry in ipairs(entries) do
        for _, file in ipairs(self:get_files(entry.id)) do
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
    requests:save(file_entry.url, file_entry.absolute_path)
end

return jimaku
