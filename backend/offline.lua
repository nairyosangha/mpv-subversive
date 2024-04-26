local util = require 'utils/utils'
local mpu = require 'mp.utils'

local offline = {}

---Extract all subtitles which are available for the given ID
---@param mal_id string which is used to identify the show
---@param show_info table containing title, ep_number and show ID
---@return string|nil path to directory containing all matching subs or nil if nothing was found
function offline:query_subtitles(mal_id, show_info)
    print(("found MAL id: %d, looking for matches in %q"):format(mal_id, self.subtitle_mapping))
    assert(util.path_exists(self.subtitle_mapping), "Mapping file does not exist!")
    local mapping_dir, _ = mpu.split_path(self.subtitle_mapping)
    local path = util.open_file(self.subtitle_mapping, 'r', function(f)
        for entry in f:lines("*l") do
            local id, path = entry:match("^([%d]+);\"(.+)\"$")
            path = mapping_dir .. path
            if id == mal_id then
                assert(util.path_exists(path), ("INVALID PATH: %q"):format(path))
                return path
            end
        end
    end)
    if not path then
        mpu.osd_message("no suitable matches found")
        return nil
    end

    return self:extract_archive(path, show_info)
end

return offline
