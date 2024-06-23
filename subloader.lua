local loader = {}
require 'utils.sequence'
require 'utils.regex'
local mp = require 'mp'
local mpu = require 'mp.utils'
local mpi = require 'mp.input'
local menu = require 'menu'
local util = require 'utils/utils'

local function build_menu_entry(anilist_media)
    local start, end_ = anilist_media.startDate.year, anilist_media.endDate.year
    local year_string = start == end_ and start or ("%s-%s"):format(start, end_ or '...')
    return ("[%s]  %s  (%s)"):format(anilist_media.format, anilist_media.title.romaji, year_string)
end

local show_selector = menu:new { pos_x = 50, pos_y = 50, rect_width = 500 }
local sub_selector = menu:new { pos_x = 50, pos_y = 50, rect_width = 600 }

function show_selector:build_manual_episode_console(show_list)
    mpi.get {
        prompt = "Please type the correct episode number: ",
        submit = function(episode_text)
            local ep_number = tonumber(episode_text)
            if ep_number then
                mpi.terminate()
                self.show_info.ep_number = ep_number
                self:display(show_list)
            end
        end,
        edited = function(episode_text)
            if not tonumber(episode_text) then
                mpi.log("This isn't a valid number!")
            end
        end,
    }
end

function show_selector:build_manual_lookup_console()
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
            local anilist_data = matching_shows[cur_idx]
            sub_selector:query(self.show_info, anilist_data)
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
                matching_shows = self.backend:query_shows { parsed_title = user_text }
                displayed_shows = Sequence(matching_shows):map(build_menu_entry):collect()
                mpi.set_log(displayed_shows)
            end
        end
    }
end

function show_selector:init(backend, show_info)
    self.backend = backend
    self.show_info = show_info
    self.offset = 3 -- to compensate for the header, show and episode lookup entries
    self.modify_show_item = self:new_item {
        text = " >>>   Text-based lookup",
        on_chosen_cb = function() self:build_manual_lookup_console() end
    }
    self.modify_episode_item = self:new_item {
        text = (" >>>   Modify episode number"):format(show_info.ep_number or 'N/A'),
        on_chosen_cb = nil -- we set this in the display when we actually have the list of shows
    }
    self.initialized = true
end

function show_selector:display(show_list)
    self:clear_items()
    self:set_header(([[Looking for: %s, episode: %s]]):format(self.show_info.parsed_title, self.show_info.ep_number or 'N/A'))
    self.modify_episode_item.on_chosen_cb = function() self:build_manual_episode_console(show_list) end
    self:add(self.modify_show_item)
    self:add(self.modify_episode_item)

    for _,s in ipairs(show_list) do
        self:add_item {
            text = build_menu_entry(s),
            on_chosen_cb = function(item)
                local anilist_data = show_list[item.idx - self.offset]
                sub_selector:query(self.show_info, anilist_data)
            end
        }
    end
    self.selected = 2
    self:open(true)
end

function sub_selector:init(backend)
    self.backend = backend
    self.offset = 2 -- to compensate for the non-sub header menu entry and back option
    self.back_item = self:new_item {
        text = " >>>   Return to show selection",
        on_chosen_cb = function()
            self:close()
            show_selector:open(true)
        end
    }
end

function sub_selector:query(show_info, anilist_data)
    if anilist_data then
        show_info.anilist_data = anilist_data
        -- bit of a hack to not display subs for a different show if we manually changed the episode name
        show_info.parsed_title = anilist_data.title and anilist_data.title.romaji or show_info.parsed_title
    end
    local items = self.backend:query_subtitles(show_info)
    self:display(items)
end

function sub_selector:display(subtitles)
    if #subtitles == 0 then
        mp.osd_message("no matching subs", 3)
        return
    end

    local function select_sub(menu_item)
        if not menu_item._sub_initialized then
            self.backend:download_subtitle(menu_item.subtitle)
            menu_item._sub_initialized = true
        end
        if menu_item.parent.last_selected then
            mp.commandv("sub_remove", menu_item.parent.last_selected)
        end
        mp.commandv("sub_add", menu_item.subtitle.absolute_path, 'cached', 'autoloader', 'jp')
        menu_item.parent.last_selected = mp.get_property('sid')
    end

    local function choose_sub(menu_item)
        mp.osd_message(string.format("chose: %s", menu_item.subtitle.name), 2)
        -- TODO we also cp the subtitle file to a local ./subs folder, this should be optional
        local dir, fn = mpu.split_path(mp.get_property("filename/no-ext"))
        local subs_path = string.format(dir .. "/subs/")
        if not util.path_exists(subs_path) then
            os.execute(string.format("mkdir %q", subs_path))
        end
        local sub_fn = table.concat({ subs_path, fn, ".", util.get_extension(menu_item.subtitle.name) })
        os.execute(string.format("cp %q %q", menu_item.subtitle.absolute_path, sub_fn))
    end

    self:clear_items()
    self:set_header(("Found %s matching files"):format(#subtitles))
    if show_selector.initialized then
        self:add(self.back_item)
    end
    self.last_selected = nil -- store sid of active sub here
    for _, sub in ipairs(subtitles) do
        local text = sub.name
        if self.backend:is_supported_archive(sub.absolute_path) then
            text = "<ENTER to download archive> " .. text
        end
        local menu_entry = self:new_item {
            text = text,
            width = mp.get_property("osd-width") - 100,
            is_visible = sub.matching_episode,
            font_size = 17,
            on_selected_cb = select_sub,
            on_chosen_cb = choose_sub,
        }
        menu_entry.subtitle = sub
        self:add(menu_entry)
    end
    self:open(true)
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
    show_selector:init(backend, initial_show_info)
    sub_selector:init(backend)

    local show_matching_subtitles, get_show_id

    -- first check if we already have a save path for this episode
    local cached_path = backend:get_cached_path(initial_show_info)
    if util.path_exists(cached_path) then
        return sub_selector:display(cached_path)
    end

    -- look for .anilist.id file to skip the jimaku lookup
    local saved_id = util.open_file("./.anilist.id", 'r', function(f) return f:read("*l") end)
    if saved_id then
        return sub_selector:query(initial_show_info, { id = saved_id })
    end

    -- only show at most 10 entries, if there are more we probably parsed the show name wrong, plus the list wouldn't render right anyway
    local matching_shows = util.table_slice(backend:query_shows(initial_show_info), 1, 11)
    show_selector:display(matching_shows)
end

return loader
