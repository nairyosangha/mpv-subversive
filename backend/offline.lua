local util = require 'utils/utils'
local mpu = require 'mp.utils'

local offline = {}

---Extract all subtitles which are available for the given ID
---@param show_info table containing title, ep_number and anilist_data
-- the anilist_data in question only contains an id here
---@return string|nil path to directory containing all matching subs or nil if nothing was found
function offline:query_subtitles(show_info)
    print(("found ID: %s, looking for matches in %q"):format(show_info.anilist_data.id, self.subtitle_mapping))
    assert(util.path_exists(self.subtitle_mapping), ("Could not find mapping file '%q'"):format(self.subtitle_mapping))
    local mapping_dir, _ = mpu.split_path(self.subtitle_mapping)
    util.open_file(self.subtitle_mapping, 'r', function(f)
        for entry in f:lines("*l") do
            local id, path = entry:match("^([%d]+),\"(.+)\"$")
            if id == show_info.anilist_data.id then
                if path[1] ~= '/' then
                    path = mapping_dir .. path
                end
                assert(util.path_exists(path), ("Path in mapping was invalid: '%q'"):format(path))
                if self:is_supported_archive(path) then
                    return self:extract_archive(path, show_info)
                end

                path = path .. '/' -- makes sure we error out if this isn't a directory
                for _,file in ipairs(util.run_cmd(("ls %q"):format(path))) do
                    if self:is_supported_archive(file) then
                        self:extract_archive(path, show_info)
                    elseif self:is_matching_episode(show_info, file) then
                        os.execute(("cp %q %q"):format(path .. file, self:get_cached_path(show_info)))
                    end
                end
            end
        end
    end)
end

return offline
