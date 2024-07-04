local loader = {}
require 'utils.sequence'
require 'utils.regex'
local mp = require 'mp'
local mpu = require 'mp.utils'
local mpi = require 'mp.input'
local menu = require 'menu'
local util = require 'utils.utils'

local function build_menu_entry(anilist_media)
    local start, end_ = anilist_media.startDate.year, anilist_media.endDate.year
    local year_string = start == end_ and start or ("%s-%s"):format(start, end_ or '...')
    return ("[%s]  %s  (%s)"):format(anilist_media.format, anilist_media.title.romaji, year_string)
end

local show_selector = menu:new { pos_x = 50, pos_y = 50 }
local sub_selector = menu:new { pos_x = 50, pos_y = 50 }

function show_selector:build_manual_episode_console()
    mpi.get {
        prompt = "Please type the correct episode number: ",
        submit = function(episode_text)
            local ep_number = tonumber(episode_text)
            if ep_number then
                mpi.terminate()
                self.show_info.ep_number = ep_number
                self:display()
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
            self.show_list = { anilist_data }
            self.show_info.anilist_data = anilist_data
            self.show_info.parsed_title = anilist_data.title and anilist_data.title.romaji or self.show_info.parsed_title
            sub_selector:query(self.show_info)
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
    self.modify_show_item = self.modify_show_item or self:add_option {
        display_text = " >>>   Text-based lookup",
        on_chosen_cb = function() self:build_manual_lookup_console() end
    }
    self.modify_episode_item = self.modify_episode_item or self:add_option {
        display_text = (" >>>   Modify episode number"):format(show_info.ep_number or 'N/A'),
        on_chosen_cb = nil -- we set this in the display when we actually have the list of shows
    }
    self.initialized = true
end

function show_selector:display(show_list)
    -- only show at most 10 entries, if there are more we probably parsed the show name wrong, plus the list wouldn't render right anyway
    self.show_list = show_list and show_list or util.table_slice(self.backend:query_shows(self.show_info), 1, 11)
    self:clear_choices()
    self:set_header(([[Looking for: %s, episode: %s]]):format(self.show_info.parsed_title, self.show_info.ep_number or 'N/A'))
    self.modify_episode_item.on_chosen_cb = function() self:build_manual_episode_console() end

    for _,s in ipairs(self.show_list) do
        self:add_item {
            display_text = build_menu_entry(s),
            on_chosen_cb = function(item)
                self.show_info.anilist_data = item.anilist_data
                sub_selector:query(self.show_info)
            end
        }
        self.choices[#self.choices].anilist_data = s
    end
    self:open()
end

function sub_selector:init(backend)
    self.backend = backend
    self.showing_all_choices = false -- this is toggled when the user toggles the show all files button
    self.go_back_option = self.go_back_option or self:add_option {
        display_text = " >>>   Return to show selection",
        on_chosen_cb = function()
            self:close()
            self.showing_all_choices = false
            show_selector:display(show_selector.show_list)
        end
    }
    self.show_all_toggle = self.show_all_toggle or self:add_option {
        display_text = " >>>   Toggle showing all files",
        on_chosen_cb = function()
            self.showing_all_choices = not self.showing_all_choices
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

function sub_selector:query(show_info)
    self.subtitles = {}
    self.show_info = show_info
    local function extract_archive(path_to_archive)
        local _,files_in_archive = self.backend:extract_archive(path_to_archive, show_info)
        for _,f in ipairs(files_in_archive) do
            table.insert(self.subtitles, f)
        end
        return files_in_archive
    end
    local archive_cnt, completed_archive_cnt = 0, 0
    for _,sub in ipairs(self.backend:query_subtitles(show_info)) do
        if self:is_cached(sub) then sub._initialized = true end
        if sub.is_archive then
            local archive_name = self.backend:get_cached_path(show_info) .. sub.name
            if sub._initialized then
                for _,s in ipairs(util.copy_table(self:get_cache().archives[sub.name])) do
                    s.matching_episode = self.backend:is_matching_episode(show_info, s.name)
                    table.insert(self.subtitles, s)
                end
            else
                archive_cnt = archive_cnt + 1
                self.backend:download_subtitle(sub):on_complete(function(result)
                    completed_archive_cnt = completed_archive_cnt + 1
                    mp.osd_message(("Finished archive %d of %d: %s"):format(completed_archive_cnt, archive_cnt, sub.name))
                    util.open_file(archive_name, 'wb', function(f) f:write(result.data) end)
                    self:cache_archive(sub, extract_archive(archive_name))
                    return true
                end)
            end
        else
            table.insert(self.subtitles, sub)
        end
    end
    if archive_cnt > 0 then
        mp.osd_message(("Extracting %d archive files, this may take a while.."):format(archive_cnt))
        self.backend:get_scheduler():wait()
    end
    table.sort(self.subtitles, function(a,b) return a.name < b.name end)
    self:display()
end

function sub_selector:get_cache()
    if not self.backend.cache then
        self.backend.cache = {}
    end
    local show_id = self.show_info.anilist_data.id
    if not self.backend.cache[show_id] then
        local cache_path = self.backend:get_cached_path(self.show_info) .. 'cache.json'
        print(("Checking cache for id %s in path %q"):format(show_id, cache_path))
        self.backend.cache[show_id] = util.open_file(cache_path, 'r', function(f)
            local c, err = mpu.parse_json(f:read("*a"))
            if not c then
                print(("Could not parse stored JSON %q: %s"):format(cache_path, err))
            end
            return c
        end) or { subs = {}, archives = {} }
    end
    return self.backend.cache[show_id]
end

function sub_selector:is_cached(sub)
    local last_modified = self:get_cache().subs[sub.name]
    return last_modified and last_modified >= sub.last_modified
end

function sub_selector:cache_subtitle(sub)
    self:get_cache().subs[sub.name] = sub.last_modified
end

function sub_selector:cache_archive(archive, files_in_archive)
    files_in_archive = util.copy_table(files_in_archive)
    self:cache_subtitle(archive)
    for _,f in ipairs(files_in_archive) do
        f.matching_episode = nil
    end
    self:get_cache().archives[archive.name] = files_in_archive
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
    if self.backend.chosen_sub_dir and #self.backend.chosen_sub_dir > 0 then
        local dir, fn = mpu.split_path(mp.get_property("path"))
        local sub_path = self.backend.chosen_sub_dir
        if sub_path:sub(1, 1) == '.' then -- relative path
            sub_path = dir .. '/' .. sub_path .. '/'
        end
        os.execute(("mkdir -p %q"):format(sub_path))
        local sub_fn = table.concat({ sub_path, fn:gsub("[^.]+$", ""), util.get_extension(menu_item.subtitle.name) })
        os.execute(("cp %q %q"):format(menu_item.subtitle.absolute_path, sub_fn))
    end
end

function sub_selector:display()
    if #self.subtitles == 0 then
        mp.osd_message("no matching subs", 3)
        return
    end

    self:clear_choices()
    local start_dl = false

    self.last_selected = nil -- store sid of active sub here
    local visible_subs_count = 0
    for _, sub in ipairs(self.subtitles) do
        local text = sub.name
        local menu_entry = self:new_item {
            display_text = text,
            is_visible = self.showing_all_choices and true or sub.matching_episode,
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
    self:open()

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
        util.open_file(sub.absolute_path, 'wb', function(f) f:write(response.data) end)
        self:cache_subtitle(sub)
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

    -- look for .anilist.id file to skip the jimaku lookup
    local saved_id = util.open_file("./.anilist.id", 'r', function(f) return f:read("*l") end)
    if saved_id then
        initial_show_info.anilist_data = { id = saved_id }
        return sub_selector:query(initial_show_info)
    end

    show_selector:display()
end

return loader
