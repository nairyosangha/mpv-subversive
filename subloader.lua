local loader = {}
require 'utils.sequence'
require 'utils.regex'
local mp = require 'mp'
local mpu = require 'mp.utils'
local mpi = require 'mp.input'
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

local function build_menu_entry(anilist_media)
    local start, end_ = anilist_media.startDate.year, anilist_media.endDate.year
    local year_string = start == end_ and start or ("%s-%s"):format(start, end_ or '...')
    return ("[%s]  %s  (%s)"):format(anilist_media.format, anilist_media.title.romaji, year_string)
end

---the backend needs to be inserted in the loader table before calling this function
---@param show_info table containing parsed_title, ep_number (anilist_data is filled in on success)
---@param on_action function which is called when the user confirms their selection
function loader:build_manual_lookup_console(show_info, on_action)
    local function log_help()
        mpi.log("Manual lookup requested, Please start typing the name of the show.")
        mpi.log("When the correct entry pops up on screen, select it with TAB, and press ENTER.")
    end
    local matching_shows = {}           -- contains data as received from AniList
    local displayed_shows = {}          -- contains only text rendered on screen
    local cur_idx, last_idx = 0, nil    -- used to highlight the currenctly selected entry
    local last_lookup_time = os.time()  -- used to debounce requests so we don't spam the AniList API
    mpi.get {
        prompt = "Please type the name of the show: ",
        opened = log_help,
        submit = function(_)
            if cur_idx == 0 then
                mpi.log_error("No show was selected!")
                return log_help()
            end
            mpi.terminate()
            show_info.anilist_data = matching_shows[cur_idx]
            on_action(show_info)
        end,
        -- we are kinda abusing the complete function here, we never actually complete the text
        -- we just update the displayed log messages so the user can pick a show there
        complete = function(user_text)
            cur_idx = cur_idx + 1
            if cur_idx > #matching_shows then
                cur_idx = 1
            end
            local current_show = displayed_shows[cur_idx]
            displayed_shows[cur_idx] = {
                text = current_show,
                style = "{\\c&H7a77f2&}",
                terminal_style = "\027[31m",
            }
            if last_idx then
                displayed_shows[last_idx] = displayed_shows[last_idx].text
            end
            last_idx = cur_idx
            mpi.set_log(displayed_shows)
            return { user_text }, 1
        end,
        edited = function(user_text)
            local current_time = os.time()
            if #user_text > 3 and os.difftime(current_time, last_lookup_time) > 1 then
                last_lookup_time = current_time
                matching_shows = Sequence(self.backend:query_shows { parsed_title = user_text }):collect()
                displayed_shows = Sequence(matching_shows):map(build_menu_entry):collect()
                mpi.set_log(displayed_shows)
            end
        end
    }
end

---Unlike the build_manual_lookup_console function, this first displays a GUI menu asking the user if they want to try a manual lookup.
---@param show_info table containing parsed_title, ep_number (anilist_data is not filled in at this point)
---@param on_action function which is called when the user confirms their selection
function loader:build_manual_lookup_menu(show_info, on_action)
    menu_selector.header = "No matching shows, try manual lookup?"
    menu_selector.items = { "Yes", "No" }
    menu_selector.act = function(self_menu)
        self_menu:close()
        if self_menu.selected == 2 then -- No
            return mp.osd_message("No matching shows.", 3)
        end
        self:build_manual_lookup_console(show_info, on_action)
    end
    menu_selector:open()
end

---@param show_list table with all shows that match the automatically parsed filename
---@param show_info table containing parsed_title, ep_number (anilist_data is not filled in at this point)
---@param on_action function which is called when the user confirms their selection
function loader:build_show_menu(show_list, show_info, on_action)
    menu_selector.header = "Select the correct show"
    menu_selector.items = Sequence(show_list):map(build_menu_entry):collect()
    table.insert(menu_selector.items, 1, " >>>   Text-based lookup")
    function menu_selector:act()
        self:close()
        if self.selected == 1 then
            return loader:build_manual_lookup_console(show_info, on_action)
        end
        show_info.anilist_data = show_list[self.selected-1]
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
    self.backend = backend
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

    -- show titles which match the parsed show title
    function get_show_id()
        local saved_id = util.open_file("./.anilist.id", 'r', function(f) return f:read("*l") end)
        if saved_id then
            print("Found existing ./.anilist.id, skipping show lookup")
            return show_matching_subtitles {
                parsed_title = initial_show_info.parsed_title,
                ep_number = initial_show_info.ep_number,
                anilist_data = { id = saved_id }
            }
        end
        -- only show at most 10 entries, if there are more we probably parsed the show name wrong, plus the list wouldn't render right anyway
        local matching_shows = util.table_slice(backend:query_shows(initial_show_info), 1, 11)
        if #matching_shows == 0 then
            return self:build_manual_lookup_menu(initial_show_info, show_matching_subtitles)
        end
        self:build_show_menu(matching_shows, initial_show_info, show_matching_subtitles)
    end

    ---callback used after we've identified the correct show
    ---@param show_info table containing parsed_title, ep_number and anilist_data
    function show_matching_subtitles(show_info)
        -- TODO now that we know which show we're dealing with, we could persist the id to disk
        -- this way we prevent another AniList query for the following episode
        local extracted_subs_path = backend:query_subtitles(show_info)
        self.show_matching_subs(extracted_subs_path)
    end

    get_show_id()
end

return loader
