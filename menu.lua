------------------------------------------------------------
-- Menu visuals

local mp = require('mp')
local assdraw = require('mp.assdraw')
local Menu = {}
local MenuItem = assdraw.ass_new()

MenuItem.DEFAULT_ACTIVE_COLOR = "FFFFFF"
MenuItem.DEFAULT_INACTIVE_COLOR = "AAAAAA"
MenuItem.DEFAULT_BORDER_COLOR = "000000"
MenuItem.DEFAULT_TEXT_COLOR = "FFFFFFFF"
MenuItem.DEFAULT_FONT_SIZE = 25
MenuItem.DEFAULT_WIDTH = 500
MenuItem.DEFAULT_HEIGHT = 40

function MenuItem:new(opts)
    local new = {}
    new.display_text = opts.display_text
    new.is_enabled = opts.is_enabled == nil and true or opts.is_enabled
    new.is_visible = opts.is_visible == nil and true or opts.is_visible
    new.on_chosen_cb = opts.on_chosen_cb
    new.on_selected_cb = opts.on_selected_cb or function() end
    new.active_color = opts.active_color or self.DEFAULT_ACTIVE_COLOR
    new.inactive_color = opts.inactive_color or self.DEFAULT_INACTIVE_COLOR
    new.border_color = opts.border_color or self.DEFAULT_BORDER_COLOR
    new.text_color = opts.text_color or self.DEFAULT_TEXT_COLOR
    new.font_size = opts.font_size or self.DEFAULT_FONT_SIZE
    new.width = opts.width or self.DEFAULT_WIDTH
    new.height = opts.height or self.DEFAULT_HEIGHT
    new.is_selected = false
    return setmetatable(new, {
        __index = function(t, k) return rawget(t, k) or self[k] end,
        __tostring = function(x)
            local string_rep = {}
            for k,v in pairs(x) do
                table.insert(string_rep, ("%s=%s"):format(k,v))
            end
            return ("MenuItem { %s }"):format(table.concat(string_rep, ", "))
        end
    })
end

function MenuItem:is_selectable()
    return self.is_enabled == true and self.is_visible == true
end

---@param display_idx number the index at which this item is displayed on screen, this isn't necessarily its own internal idx
function MenuItem:draw(display_idx)
    self.text = ''
    -- our idx starts at 1 but we want to start at 0 here
    local x0, y0 = self.parent.pos_x, self.parent.pos_y + ((display_idx-1) * self.height)
    self:new_event()
    self:apply_rect_color(display_idx)
    self:draw_start()
    self:pos(x0, y0)
    self:rect_cw(0, 0, self.width, self.height)
    self:draw_stop()
    self:draw_text(display_idx)
    return self.text
end

function MenuItem:draw_text(display_idx)
    self:new_event()
    self:pos(self.parent.pos_x + self.parent.padding, self.parent.pos_y + (self.height * (display_idx - 1)) + self.parent.padding)
    self:set_font_size()
    self:apply_text_color()
    self:append(self.display_text)
end

function MenuItem:set_font_size(size)
    self:append(string.format([[{\fs%s}]], size or self.font_size))
end

function MenuItem:set_text_color(hex_code)
    self:append(string.format("{\\1c&H%s%s%s&\\1a&H05&}", hex_code:sub(5, 6), hex_code:sub(3, 4), hex_code:sub(1, 2)))
end

function MenuItem:set_border_color(hex_code)
    self:append(string.format("{\\3c&H%s%s%s&}", hex_code:sub(5, 6), hex_code:sub(3, 4), hex_code:sub(1, 2)))
end

function MenuItem:apply_text_color()
    self:set_border_color(self.border_color)
    self:set_text_color(self.text_color)
end

function MenuItem:apply_rect_color()
    self:set_border_color(self.border_color)
    self:set_text_color(self.is_selected and self.active_color or self.inactive_color)
end

function Menu:new(o)
    self.__index = self
    o = o or {}
    o.header = o.header
    o.options = o.options or {}
    o.choices = o.choices or {}
    o.canvas_width = o.canvas_width or 1280
    o.canvas_height = o.canvas_height or 720
    o.on_close_callbacks = {}
    o.pos_x = o.pos_x or 0
    o.pos_y = o.pos_y or 0
    o.padding = o.padding or 5
    o.visible_item_count = o.visible_item_count or 5
    return setmetatable(o, self)
end

function Menu:set_header(header_text)
    self.header = MenuItem:new {
        is_enabled = false,
        is_visible = true,
        display_text = header_text,
        text_color = '95bdc7',
        font_size = 27
    }
    self.header.parent  = self
end

function Menu:new_item(item_opts)
    local new = MenuItem:new(item_opts)
    new.parent = self
    return new
end

function Menu:add(choice)
    table.insert(self.choices, choice)
end

function Menu:add_item(item_opts)
    self:add(self:new_item(item_opts))
end

function Menu:add_option(item_opts)
    local opt = self:new_item(item_opts)
    table.insert(self.options, opt)
    return opt
end

function Menu:clear_choices(with_redraw)
    for _=1, #self.choices do
        table.remove(self.choices, 1)
    end
    if with_redraw then
        self:draw()
    end
end

function Menu:on_close(callback)
    table.insert(self.on_close_callbacks, callback)
end

function Menu:get_visible_items()
    local function is_within_window(item_idx)
        return math.abs(item_idx + #self.options - self.selected - 1) <= self.visible_item_count
    end

    local current_selection = self:get_selected_item()
    local visible_items = {}
    table.insert(visible_items, self.header)
    for _,option in ipairs(self.options) do
        table.insert(visible_items, option)
        option.is_selected = option == current_selection
    end
    local non_item_size = #visible_items
    for i,item in ipairs(self.choices) do
        -- when we're selecting an option item the `is_within_window` call does not work
        if item.is_visible and (self.selected <= #self.options or is_within_window(i)) then
            table.insert(visible_items, item)
        end
        item.is_selected = self.selected == i + #self.options
        if #visible_items == self.visible_item_count + non_item_size then
            break
        end
    end
    return visible_items
end

function Menu:draw()
    self.text_table = {}
    for i,item in ipairs(self:get_visible_items()) do
        table.insert(self.text_table, item:draw(i))
    end
    mp.set_osd_ass(self.canvas_width, self.canvas_height, table.concat(self.text_table, "\n"))
end

function Menu:erase()
    mp.set_osd_ass(self.canvas_width, self.canvas_height, '')
end

function Menu:up()
    local before = self.selected
    while self.selected > 1 do
        self.selected = self.selected - 1
        local item = self:get_selected_item()
        if item:is_selectable() then
            item:on_selected_cb()
            return self:draw()
        end
    end
    self.selected = before
end

function Menu:down()
    local count = #self.options + #self.items
    local before = self.selected
    while self.selected < count do
        self.selected = self.selected + 1
        local item = self:get_selected_item()
        if item:is_selectable() then
            item:on_selected_cb()
            return self:draw()
        end
    end
    self.selected = before
end

function Menu:get_selected_item()
    return self.options[self.selected] or self.choices[self.selected - #self.options]
end

function Menu:act()
    self:close()
    self:get_selected_item():on_chosen_cb()
end

function Menu:get_keybindings()
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

function Menu:open()
    self.selected = self.selected or 1
    for _, val in pairs(self:get_keybindings()) do
        mp.add_forced_key_binding(val.key, val.key, val.fn)
    end
    self:draw()
end

function Menu:close()
    for _, val in pairs(self:get_keybindings()) do
        mp.remove_key_binding(val.key, val.key, val.fn)
    end
    for _, callback in ipairs(self.on_close_callbacks) do
        callback(self)
    end
    self:erase()
end

return Menu
