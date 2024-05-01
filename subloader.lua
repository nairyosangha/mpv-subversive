local loader = {}
require 'utils/sequence'
require 'regex'
local mp = require 'mp'
local mpu = require 'mp.utils'
local menu = require 'menu'
local util = require 'utils/utils'

-- default menu which can be used for the different selection views
local menu_selector = menu:new { pos_x = 50, pos_y = 50, rect_width = 500 }
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

function loader.build_show_menu(show_list, show_info, on_action)
    menu_selector.header = "Select the correct show"
    menu_selector.items = Sequence(show_list):map(function(x)
        local start, end_ = x.startDate.year, x.endDate.year
        local year_string = start == end_ and start or ("%s-%s"):format(start, end_)
        return ("[%s]  %s  (%s)"):format(x.format, x.title.romaji, year_string)
    end):collect()
    function menu_selector:act()
        self:close()
        show_info.anilist_data = show_list[self.selected]
        on_action(show_info)
    end
    menu_selector:open()
end

--- Displays menu with all the subtitles that match the current show
--- @param path string: path where extracted subtitle files are stored
--- @return nil
function loader.show_matching_subs(path)
    local function to_full_path(subtitle)
        return string.format("%s/%s", path, subtitle)
    end
    local all_subs = util.run_cmd(string.format("ls %q", path))
    local with_full_path = Sequence(all_subs)
        :map(to_full_path)
        :collect()
    if #all_subs == 0 then
        mp.osd_message("no matching subs", 3)
        return
    end
    menu_selector.header = "Matching subtitles"
    menu_selector.rect_width = mp.get_property("osd-width") - 100
    menu_selector.font_size = 20
    menu_selector.items = all_subs
    menu_selector.last_selected = nil -- store sid of active sub here

    function menu_selector:update_sub()
        if self.last_selected then
            mp.commandv("sub_remove", self.last_selected)
        end

        mp.commandv("sub_add", with_full_path[self.selected], 'cached', 'autoloader', 'jp')
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
        local selected_sub = with_full_path[self.selected]
        local _, selected_sub_file = mpu.split_path(selected_sub)
        mp.osd_message(string.format("chose: %s", selected_sub_file), 2)
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

function loader:run(backend)
    local show_name, episode = backend:parse_current_file(mp.get_property("filename"))
    local initial_show_info = {
        parsed_title = show_name,
        ep_number = episode and tonumber(episode),
        -- the following field gets filled in later after we query AniList
        anilist_data = nil
    }
    print(("show title: '%s', episode number: '%d'"):format(show_name, episode or -1))

    local show_matching_subtitles, get_show_id

    -- check whether we already extracted subs for this show / episode
    local cached_path = backend:get_cached_path(initial_show_info)
    if util.path_exists(cached_path) then
        print("loading cached path: " .. cached_path)
        return loader.show_matching_subs(cached_path)
    end

    -- TODO we never save this anywhere
    util.open_file("./.anilist.id", 'r', function(f)
        local id = f:read("*a")
        print("Found existing ./.anilist.id, skipping show lookup")
        return show_matching_subtitles(id)
    end)

    -- show titles which match the parsed show title
    function get_show_id()
        local matching_shows = backend:query_shows(initial_show_info)
        if #matching_shows == 0 then
            return mp.osd_message("Failed to query shows", 3)
        end
        self.build_show_menu(matching_shows, initial_show_info, show_matching_subtitles)
    end

    ---callback used after we've identified the correct show
    ---@param show_info table containing parsed_title, ep_number and anilist_data
    function show_matching_subtitles(show_info)
        local extracted_subs_path = backend:query_subtitles(show_info)
        self.show_matching_subs(extracted_subs_path)
    end

    get_show_id()
end

return loader
