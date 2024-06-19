------------------------------------------------------------
-- Menu visuals

local mp = require('mp')
local assdraw = require('mp.assdraw')
local Menu = {}
local MenuItem = assdraw.ass_new()

local EMPTY_OR_UNSELECTABLE_MENU_ERROR = [[Could not move up or down, did you create an empty menu, or a menu with non selectable items only?]]


MenuItem.DEFAULT_ACTIVE_COLOR = "FFFFFF"
MenuItem.DEFAULT_INACTIVE_COLOR = "AAAAAA"
MenuItem.DEFAULT_BORDER_COLOR = "000000"
MenuItem.DEFAULT_TEXT_COLOR = "FFFFFFFF"
MenuItem.DEFAULT_FONT_SIZE = 25
MenuItem.DEFAULT_WIDTH = 500
MenuItem.DEFAULT_HEIGHT = 40

function MenuItem:new(opts)
    local new = {}
    -- text field is used internally by assdraw so we use display_text
    new.display_text = opts.text
    new.selectable = opts.selectable
    new.on_chosen_cb = opts.on_chosen_cb
    new.on_selected_cb = opts.on_selected_cb or function() end
    new.active_color = opts.active_color or self.DEFAULT_ACTIVE_COLOR
    new.inactive_color = opts.inactive_color or self.DEFAULT_INACTIVE_COLOR
    new.border_color = opts.border_color or self.DEFAULT_BORDER_COLOR
    new.text_color = opts.text_color or self.DEFAULT_TEXT_COLOR
    new.font_size = opts.font_size or self.DEFAULT_FONT_SIZE
    new.width = opts.width or self.DEFAULT_WIDTH
    new.height = opts.height or self.DEFAULT_HEIGHT
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

function MenuItem:draw()
    self.text = ''
    -- our idx starts at 1 but we want to start at 0 here
    local x0, y0 = self.parent.pos_x, self.parent.pos_y + ((self.idx-1) * self.height)
    self:new_event()
    self:apply_rect_color()
    self:draw_start()
    self:pos(x0, y0)
    self:rect_cw(0, 0, self.width, self.height)
    self:draw_stop()
    self:draw_text()
    return self.text
end

function MenuItem:draw_text()
    self:new_event()
    self:pos(self.parent.pos_x + self.parent.padding, self.parent.pos_y + (self.height * (self.idx - 1)) + self.parent.padding)
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
    if self.idx == self.parent.selected then
        self:set_text_color(self.active_color)
    else
        self:set_text_color(self.inactive_color)
    end
end

function Menu:new(o)
    self.__index = self
    o = o or {}
    o.items = o.items or {}
    o.selected = o.selected or 1
    o.canvas_width = o.canvas_width or 1280
    o.canvas_height = o.canvas_height or 720
    o.pos_x = o.pos_x or 0
    o.pos_y = o.pos_y or 0
    o.padding = o.padding or 5
    return setmetatable(o, self)
end

function Menu:set_header(header_text)
    self.items[1] = MenuItem:new {
        selectable = false,
        text = header_text,
        text_color = '95bdc7',
        font_size = 27
    }
    self.items[1].idx = 1
    self.items[1].parent = self
end

function Menu:add_item(item_opts)
    table.insert(self.items, MenuItem:new(item_opts))
    self.items[#self.items].selectable = true
    self.items[#self.items].idx = #self.items
    self.items[#self.items].parent = self
end

function Menu:clear_items(with_redraw)
    for _=1, #self.items do
        table.remove(self.items, 1)
    end
    self.selected = 1
    if with_redraw then
        self:draw()
    end
end

function Menu:draw()
    self.text_table = {}
    for _,i in ipairs(self.items) do
        table.insert(self.text_table, i:draw())
    end
    self.items[self.selected]:on_selected_cb()
    mp.set_osd_ass(self.canvas_width, self.canvas_height, table.concat(self.text_table, "\n"))
end

function Menu:erase()
    mp.set_osd_ass(self.canvas_width, self.canvas_height, '')
end

function Menu:up()
    for _=0, #self.items do
        self.selected = self.selected - 1
        if self.selected == 0 then
            self.selected = #self.items
        end
        if self.items[self.selected].selectable == true then
            self:draw()
            return self.items[self.selected]:on_selected_cb()
        end
    end
    assert(false, EMPTY_OR_UNSELECTABLE_MENU_ERROR)
end

function Menu:down()
    for _=0, #self.items do
        self.selected = self.selected + 1
        if self.selected > #self.items then
            self.selected = 1
        end
        if self.items[self.selected].selectable then
            self:draw()
            return self.items[self.selected]:on_selected_cb()
        end
    end
    assert(false, EMPTY_OR_UNSELECTABLE_MENU_ERROR)
end

function Menu:act()
    self:close()
    local item = self.items[self.selected]
    self:clear_items() -- make sure this is done before the callback, so it doesn't interfere with whatever the cb does with the menu items
    item:on_chosen_cb()
end

return Menu
