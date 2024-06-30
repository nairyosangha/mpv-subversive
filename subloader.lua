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

function show_selector:display()
    -- only show at most 10 entries, if there are more we probably parsed the show name wrong, plus the list wouldn't render right anyway
    local show_list = util.table_slice(self.backend:query_shows(self.show_info), 1, 11)
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
    self.offset = 3 -- to compensate for the non-sub header menu entry and back option
    self.showing_all_items = false -- this is toggled when the user toggles the show all files button
    self.back_item = self:new_item {
        text = " >>>   Return to show selection",
        on_chosen_cb = function()
            self:close()
            show_selector:display()
        end
    }
    self.toggle_ep_filter = self:new_item {
        text = " >>>   Toggle showing all files",
        on_chosen_cb = function()
            self.showing_all_items = not self.showing_all_items
            self:display()
        end
    }
    self.download_timer = function()
        local finished_results = self.backend:get_scheduler():poll()
        if #finished_results > 0 then
            self:draw()
        end
    end
end

function sub_selector:query(show_info, anilist_data)
    if anilist_data then
        show_info.anilist_data = anilist_data
        -- bit of a hack to not display subs for a different show if we manually changed the episode name
        show_info.parsed_title = anilist_data.title and anilist_data.title.romaji or show_info.parsed_title
    end
    self.subtitles = self.backend:query_subtitles(show_info)
    self:display()
end

function sub_selector:select_item(menu_item)
    if not menu_item.subtitle._initialized then
        return
    end
    if menu_item.parent.last_selected then
        mp.commandv("sub_remove", menu_item.parent.last_selected)
    end
    mp.commandv("sub_add", menu_item.subtitle.absolute_path, 'cached', 'autoloader', 'jp')
    menu_item.parent.last_selected = mp.get_property('sid')
end

function sub_selector:choose_item(menu_item)
    if not menu_item.subtitle._initialized then
        return
    end
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

function sub_selector:display()
    if #self.subtitles == 0 then
        mp.osd_message("no matching subs", 3)
        return
    end

    self:clear_items()
    self:add({}) -- placeholder for header we fill in later
    self:add(self.back_item)
    self:add(self.toggle_ep_filter)

    local start_dl = false

    self.last_selected = nil -- store sid of active sub here
    local visible_subs_count = 0
    for _, sub in ipairs(self.subtitles) do
        local text = sub.name
        if self.backend:is_supported_archive(sub.absolute_path) then
            text = "<ENTER to download archive> " .. text
        end
        local menu_entry = self:new_item {
            text = text,
            width = mp.get_property("osd-width") - 100,
            is_visible = self.showing_all_items and true or sub.matching_episode,
            font_size = 17,
            on_selected_cb = function(item) self:select_item(item) end,
            on_chosen_cb = function(item) self:choose_item(item) end
        }
        menu_entry.subtitle = sub
        if menu_entry.is_visible then
            visible_subs_count = visible_subs_count + 1
            if not sub._initialized then
                start_dl = true
                menu_entry.display_text = '[not downloaded]:  ' .. text
                self:download(menu_entry)
            else
            end
        end
        self:add(menu_entry)
    end
    self:set_header(("Found %s/%s matching files"):format(visible_subs_count, #self.subtitles))
    self:open(true)

    if start_dl then
        self.timer = mp.add_periodic_timer(0.2, self.download_timer)
        self:on_close(function() self.timer:kill() end)
    end
end

function sub_selector:download(menu_item)
    if menu_item.subtitle._initialized then
        menu_item.display_text = menu_item.subtitle.name
        return
    end
    local sub = menu_item.subtitle
    self.backend:download_subtitle(sub):on_complete(function(response)
        if response.status_code ~= 200 then
            return false
        end
        local f = assert(io.open(sub.absolute_path, 'wb'))
        f:write(response.data)
        f:close()
        menu_item.subtitle._initialized = true
        menu_item.display_text = sub.name
        return true
    end):on_incomplete(function(response)
        local content_length = response.headers and response.headers['content-length']
        if not content_length then return end
        local data_downloaded = response.data and #response.data or 0
        menu_item.display_text = ('[%d%% downloaded]:\t   '):format(100 * data_downloaded / content_length) .. sub.name
        self:draw() -- download update is always redrawn
    end)
end

function loader:run(backend)
    mp.osd_message("Parsing file name..")
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
        local cached_subs = {}
        for _,file in ipairs(util.run_cmd(("ls %q"):format(cached_path))) do
            table.insert(cached_subs, {
                name = file,
                absolute_path = cached_path .. '/' .. file,
                _initialized = true,
            })
        end
        sub_selector.subtitles = cached_subs
        return sub_selector:display()
    end

    -- look for .anilist.id file to skip the jimaku lookup
    local saved_id = util.open_file("./.anilist.id", 'r', function(f) return f:read("*l") end)
    if saved_id then
        return sub_selector:query(initial_show_info, { id = saved_id })
    end

    show_selector:display()
end

return loader
