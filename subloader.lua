local loader = {}
require 'utils/sequence'
require 'regex'
local mp = require 'mp'
local mpu = require 'mp.utils'
local menu = require 'menu'
local util = require 'utils/utils'
local archive = require 'archive'

-- default menu which can be used for the different selection views
local menu_selector = menu:new { pos_x = 50, pos_y = 50 }
function menu_selector:get_keybindings()
    return {
        { key = 'h', fn = function() self:close() end },
        { key = 'j', fn = function() self:down() end },
        { key = 'k', fn = function() self:up() end },
        { key = 'l', fn = function() self:act() end },
        { key = 'down', fn = function() self:down() end },
        { key = 'up', fn = function() self:up() end },
        { key = 'Enter', fn = function() self:act() end },
        { key = 'ESC', fn = function() self:close() end },
        { key = 'n', fn = function() self:close() end },
    }
end

function menu_selector:open()
    self.selected = 1
    for _, val in pairs(self:get_keybindings()) do
        mp.add_forced_key_binding(val.key, val.key, val.fn)
    end
    self:draw()
end

function menu_selector:close()
    for _, val in pairs(self:get_keybindings()) do
        mp.remove_key_binding(val.key, val.key, val.fn)
    end
    self:erase()
end

local function sanitize(text)
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

local function extract_title_and_number(text)
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

function loader.parse_current_file(filename)
    local sanitized_filename = sanitize(filename)
    print(string.format("Sanitized filename: '%s'", sanitized_filename))
    return extract_title_and_number(sanitized_filename)
end

function loader.build_show_menu(show_list, on_action)
    local titles = Sequence(show_list):map(function(x) return x.title end)
    menu_selector.items = titles:collect()
    function menu_selector:act()
        self:close()
        on_action(show_list[self.selected].id)
    end
    menu_selector:open()
end

function loader.get_cached_path(show_name, episode_number)
    local temp_sub_dir = "/tmp/subloader"
    if episode_number then
        return string.format("%s/%s/%s", temp_sub_dir, show_name, episode_number)
    end
    return string.format("%s/%s", temp_sub_dir, show_name)
end

function loader.extract_subs(file, episode_number, show_name)
    local cached_path = loader.get_cached_path(show_name, episode_number)
    local ep = (episode_number and string.format("*%s*", episode_number) or "*") .. ".%s"
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
    return cached_path end

function loader.show_matching_subs(path, episode_number)
    -- when extracting subs only ep number is checked, which can return wrong matches
    local function matching_ep(filename)
        if episode_number == nil then
            return true
        end
        local msg = "Looking for episode %d in '%s' (sanitized: '%s')"
        local sanitized = sanitize(filename)
        print(msg:format(episode_number, filename, sanitized))
        return sanitized and sanitized:find(episode_number)
    end
    local function to_full_path(subtitle)
        return string.format("%s/%s", path, subtitle)
    end
    local all_subs = util.run_cmd(string.format("ls %q", path))
    local matched_subs = Sequence(all_subs)
        :filter(matching_ep)
        :map(to_full_path)
        :collect()
    if #all_subs == 0 then
        mp.osd_message("no matching subs")
        return
    end
    if #matched_subs == 0 then
        -- if we had something initially but filter removed everything, the filter is probably wrong
        matched_subs = Sequence(all_subs):map(to_full_path):collect()
    end
    menu_selector.items = matched_subs
    menu_selector.last_selected = nil -- store sid of active sub here

    function menu_selector:update_sub()
        if self.last_selected then
            mp.commandv("sub_remove", self.last_selected)
        end

        mp.commandv("sub_add", self.items[self.selected], 'cached', 'autoloader', 'jp')
        self.last_selected = mp.get_property('sid')
    end
    function menu_selector:up()
        menu.up(menu_selector)
        self:update_sub() end
    function menu_selector:down()
        menu.down(menu_selector)
        self:update_sub()
    end
    function menu_selector:act()
        local selected_sub = self.items[self.selected]
        local _, selected_sub_file = mpu.split_path(selected_sub)
        mp.osd_message(string.format("chose: %s", selected_sub_file))
        local dir, fn = mpu.split_path(mp.get_property("filename/no-ext"))
        local subs_path = string.format(dir .. "/subs/")
        if not util.path_exists(subs_path) then
            os.execute(string.format("mkdir %q", subs_path))
        end
        local sub_fn = table.concat({ subs_path, fn, ".", util.get_extension(selected_sub) })
        os.execute(string.format("cp %q %q", selected_sub, sub_fn))
        self:close()
    end
    menu_selector:open()
    menu_selector:update_sub()
    return nil
end

function loader.search_subs(mal_id, mapping)
    print(string.format("found MAL id: %d, looking for matches in %q", mal_id, mapping))
    assert(util.path_exists(mapping), "Mapping file does not exist!")
    local f = io.open(mapping, 'r')
    for entry in f:lines("*l") do
        local id, path = string.match(entry, "^([%d]+);\"(.+)\"$")
        if id == mal_id then
            assert(util.path_exists(path), string.format("INVALID PATH: %q", path))
            f:close()
            return path
        end
    end
    f:close()
    mp.osd_message("no suitable matches found")
end

function loader.query_mal(show_name)
    local mal_cmd = string.format("python3 %q/query_mal.py '%q'", mp.get_script_directory(), show_name)
    local results = Sequence(util.run_cmd(mal_cmd))
        :map(function(res)
            local id, name = string.match(res, "^([%d]+),(.+)$")
            return { title = name, id = id } end)
    return results:collect()
end

function loader.main(subtitle_mapping_file)
    local show_name, episode = loader.parse_current_file(mp.get_property("filename"))
    print(string.format("PARSED title: '%s', ep: '%s'", show_name, episode))

    local function show_subs(mal_id)
        local subtitle_archive = loader.search_subs(mal_id, subtitle_mapping_file)
        if subtitle_archive then
            local subtitle_dir = loader.extract_subs(subtitle_archive, episode, show_name)
            loader.show_matching_subs(subtitle_dir, episode)
        end
    end

    -- check whether we already extracted subs for this show / episode
    local cached_path = loader.get_cached_path(show_name, episode)
    if util.path_exists(cached_path) then
        print("loading cached path: " .. cached_path)
        return loader.show_matching_subs(cached_path, episode)
    end

    local f = io.open("./.mal_id", 'r')
    if f then
        local mal_id = f:lines("*l")()
        print(string.format("Read id %d from ./.mal_id", mal_id))
        f:close()
        return show_subs(mal_id)
    end

    local shows = loader.query_mal(show_name)
    if shows then
        loader.build_show_menu(shows, show_subs)
    end
end

return loader
