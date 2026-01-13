local util = require 'utils/utils'
local mpu = require 'mp.utils'

---@class Offline : Backend
---@field subtitle_mapping string
local offline = {}

function offline:query_subtitles(show_info)
    print(("found ID: %s, looking for matches in %q"):format(show_info.anilist_data.id, self.subtitle_mapping))
    if not util.path_exists(self.subtitle_mapping) then
        return { error = ("Could not find mapping file '%q'"):format(self.subtitle_mapping) }
    end
    local mapping_dir, _ = mpu.split_path(self.subtitle_mapping)
    local subtitles = {}
    util.open_file(self.subtitle_mapping, 'r', function(f)
        for entry in f:lines("*l") do
            local id, path = entry:match("^([%d]+),\"(.+)\"$")
            if tonumber(id) == show_info.anilist_data.id then
                if path[1] ~= '/' then
                    path = mapping_dir .. path
                end
                assert(util.path_exists(path), ("Path in mapping was invalid: '%q'"):format(path))
                path = path .. '/' -- makes sure we error out if this isn't a directory
                for _, file in ipairs(util.run_cmd(("ls %q"):format(path))) do
                    if self:is_supported_archive(file) then
                        local _, files_in_archive = self:extract_archive(path .. file, show_info)
                        for _, ff in ipairs(files_in_archive) do
                            ff.last_modified = 1
                            table.insert(subtitles, ff)
                        end
                    else
                        table.insert(subtitles, {
                            name = file,
                            matching_episode = self:is_matching_episode(show_info, file),
                            absolute_path = path .. file,
                            is_downloaded = true,
                            last_modified = 1
                        })
                    end
                end
            end
        end
    end)
    return subtitles
end

return offline
