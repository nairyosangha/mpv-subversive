require 'utils.sequence'
local requests = require 'requests'
local mp = require 'mp'
local mpu = require 'mp.utils'

local jimaku = {
    BASE_URL = "https://jimaku.cc/api/"
}

---Extract all subtitles which are available for the given ID
---@param show_info table containing title, ep_number and anilist_data
---@return string|nil path to directory containing all matching subs or nil if nothing was found
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
    for _, entry in ipairs(entries) do
        print(("Found matching entry '%s', id: %d"):format(entry.name, entry.id))
        Sequence(self:get_files(entry.id))
            :map(function(x)
                x.is_archive = self:is_supported_archive(x.name)
                return x
            end)
            :filter(file_filter)
            :foreach(function(file_entry)
                local fn = self:download_subtitle(file_entry, cached_path)
                if file_entry.is_archive then
                    self:extract_archive(fn, show_info)
                end
            end)
    end
    return cached_path
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

function jimaku:download_subtitle(file_entry, path)
    local filename = path .. '/' .. file_entry.name
    requests:save(file_entry.url, filename)
    return filename
end

return jimaku
