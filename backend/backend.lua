require 'utils/sequence'
require 'regex'
local mpu = require 'mp.utils'
local util = require 'utils/utils'
local archive = require 'archive'
local requests = require 'requests'

local backend = {
    archive_extensions = { ["RAR"] = 1, ["ZIP"] = 1 },
}

function backend:new(options)
    local backend_impl = require("backend." .. string.lower(options.subtitle_backend))
    return setmetatable(options, {
        __index = function(t, k)
            return backend_impl[k] or self[k] or rawget(t, k)
        end
    })
end

---Use AniList's search API to query the show name (parsed from the filename)
---@param show_info table containing title, ep_number and show ID
---@return table containing all shows which match the title
function backend:query_shows(show_info)
    local graphql_query = [[
        query ($id: Int, $page: Int=1, $search: String) {
            Page (page: $page) {
                media (id: $id, search: $search, type: ANIME) {
                    id
                    episodes
                    title {
                        english
                        romaji
                        native
                    }
                }
            }
        }
    ]]
    local body_json = mpu.format_json({
        query = graphql_query,
        variables = {
            search = show_info.title
        }
    })
    local response = requests:POST {
        url = "https://graphql.anilist.co",
        headers = {
            ["Content-Type"] = "application/json"
        },
        body = body_json
    }
    return mpu.parse_json(response).data.Page.media
end

---Extract all subtitles which are available for the given ID
---@param id string which is used to identify the show
---@param show_info table containing title, ep_number and show ID
---@return string path to directory containing all matching subs
function backend:query_subtitles(id, show_info)
    assert(false, "This should be implemented in a specific backend!")
end

--- Extract all subtitle files in the given archive and store them in predefined cache directory
---@param file string: filename which is a archive containing subtitles
---@param show_info table containing title, ep_number and show ID
---@return string path where the extracted subtitles are stored
function backend:extract_archive(file, show_info)
    -- TODO we could be smarter here, we can check how many episodes is and add leading zeros to ep number (so we don't match ep 12 when looking for ep 2)
    local cached_path = self:get_cached_path(show_info)
    local ep = (show_info.ep_number and ("*%s*"):format(show_info.ep_number) or "*") .. ".%s"
    local extensions = Sequence { "srt", "ass", "ssa", "pgs", "sup", "sub", "idx" }:map(function(ext) return ep:format(ext) end):collect()

    local function extract_inner_archive(path_to_archive)
        print(string.format("Looking for archive files in: %q", path_to_archive))
        local parser = archive:new(path_to_archive)
        if not parser:check_valid() then
            print(string.format("Archive was invalid! skipping..\n"))
            return
        end
        local archive_filter = { "*.zip", "*.rar" }
        for arch in parser:list_files { filter = archive_filter } do
            archive
                :new(path_to_archive)
                :extract { filter = { arch }, target_path = cached_path }
            -- lookup in archive can have full path, so strip it
            local a_path = string.format("%s/%s", cached_path, util.strip_path(arch))
            extract_inner_archive(a_path)
        end
    end
    -- extract all zips to the cache folder, then loop over each zip and look for matching subtitle files within
    os.execute(string.format("mkdir -p %q", cached_path))
    extract_inner_archive(file)

    os.execute(string.format("cp %q %q", file, cached_path))
    print(string.format("Extracting matches to: %q", cached_path))
    Sequence(util.run_cmd(string.format("ls %q", cached_path)))
        :map(function(zip)
            return string.format("%s/%s", cached_path, zip) end)
        :foreach(function(full_path)
            archive
                :new(full_path)
                :extract { filter = extensions, target_path = cached_path }
            os.remove(full_path)
        end)
    return cached_path
end

function backend:get_cached_path(show_info)
    if show_info.ep_num then
        return string.format("%s/%s/%s", self.cache_directory, show_info.title, show_info.ep_num)
    end
    return string.format("%s/%s", self.cache_directory, show_info.title)
end

function backend.sanitize(text)
    local sub_patterns = {
        "%.[%a]+$", -- extension
        "_", "%.",
        "%[[^%]]+%]", -- [] bracket
        "%([^%)]+%)", -- () bracket
        "720[pP]", "480[pP]", "1080[pP]", "[xX]26[45]", "[bB]lu[-]?[rR]ay", "^[%s]*", "[%s]*$",
        "1920x1080", "1920X1080", "Hi10P", "FLAC", "AAC"
    }
    local result = text
    for _,sub_pattern in ipairs(sub_patterns) do
        local new = result:gsub(sub_pattern, "")
        if #new > 0 then result = new end
    end
    return result
end

---@return string,number|nil: show's title and episode number
function backend.extract_title_and_number(text)
    local matchers = Sequence {
        Regex("^([%a%s%p%d]+)[Ss][%d]+[Ee]?([%d]+)", "\1\2"),
        Regex("^([%a%s%p%d]+)%-[%s]-([%d]+)[%s%p]*[^%a]*", "\1\2"),
        Regex("^([%a%s%p%d]+)[Ee]?[Pp]?[%s]+(%d+)$", "\1\2"),
        Regex("^([%a%s%p%d]+)[%s](%d+).*$", "\1\2"),
        Regex("^([%d]+)[%s]*(.+)$", "\2\1") }
    local _, re = matchers:find_first(function(re) return re:match(text) end)
    if re then
        local title, ep_number = re:groups()
        return title, tonumber(ep_number)
    end
    return text
end

function backend:parse_current_file(filename)
    local sanitized_filename = self.sanitize(filename)
    print(string.format("Sanitized filename: '%s'", sanitized_filename))
    return self.extract_title_and_number(sanitized_filename)
end

return backend