local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Stats = require("kindlevel_stats")
local Screen = Device.screen

local Home = InputContainer:extend{
    name = "KindlevelScreen",
    covers_fullscreen = true,
    stop_events_propagation = true,
}

function Home:init()
    self.tab = self.initial_tab or "read"
    self.stats_period = "30"
    self.stats_metric = "pages"
    self.stats_year = tonumber(os.date("%Y"))
    self.stats_month = require("kindlevel_stats").month(os.time())
    self.stats_view = "overview"
    self.stats_list_page = 1
    self.stats_history = {}
    self.index = self.library:find(self.selected_file)
    self.page = math.floor((self.index - 1) / 6) + 1
    self.key_events.Back = { { "Back" }, { "Esc" } }
    self.key_events.Home = { { "Home" } }
    self.key_events.Next = { { "Right" }, { "LPgFwd" }, { "RPgFwd" } }
    self.key_events.Previous = { { "Left" }, { "LPgBack" }, { "RPgBack" } }
    self.key_events.Open = { { "Enter" }, { "Press" } }
    self:rebuild()
end

function Home:px(value)
    return math.floor(value * self.scale + 0.5)
end

function Home:addWidget(widget, x, y)
    self.resources[#self.resources + 1] = widget
    self.draw[#self.draw + 1] = { kind = "widget", widget = widget, x = x, y = y }
    return widget
end

function Home:text(text, x, y, width, height, size, options)
    options = options or {}
    -- Font:getFace already scales by screen size; compensate for our own layout scale.
    local factor = Screen:scaleBySize(1000) / 1000
    local face = Font:getFace(options.serif and "NotoSerif-Regular.ttf" or "cfont", size * self.scale / factor)
        or Font:getFace("cfont", size * self.scale / factor)
    local color = Blitbuffer.Color8(options.gray or 0)
    if options.single then
        local widget = TextWidget:new{
            text = text, face = face, fgcolor = color, bold = options.bold,
            max_width = width, padding = 0,
        }
        local widget_width = widget:getSize().w
        if options.center then x = x + math.floor((width - widget_width) / 2) end
        self:addWidget(widget, x, y)
    else
        self:addWidget(TextBoxWidget:new{
            text = text, face = face, fgcolor = color, bold = options.bold,
            width = width, height = height, alignment = options.center and "center" or "left",
            alignment_strict = true, height_overflow_show_ellipsis = true, line_height = 0.18,
        }, x, y)
    end
end

function Home:rect(x, y, w, h, gray)
    self.draw[#self.draw + 1] = { kind = "rect", x = x, y = y, w = w, h = h, gray = gray or 0 }
end

function Home:outline(x, y, w, h, gray)
    local stroke = math.max(1, self:px(1))
    self:rect(x, y, w, stroke, gray)
    self:rect(x, y + h - stroke, w, stroke, gray)
    self:rect(x, y, stroke, h, gray)
    self:rect(x + w - stroke, y, stroke, h, gray)
end

function Home:hit(x, y, w, h, callback, id)
    self.hits[#self.hits + 1] = { x = x, y = y, w = w, h = h, callback = callback, id = id }
end

function Home:button(label, x, y, w, h, callback, primary, id)
    self:rect(x, y, w, h, primary and 0 or 242)
    self:text(label, x, y + math.floor((h - self:px(24)) / 2), w, self:px(28), 18,
        { center = true, single = true, gray = primary and 255 or 0 })
    self:hit(x, y, w, h, callback, id)
end

function Home:cover(book, x, y, w, h, small)
    self:rect(x + self:px(4), y + self:px(5), w, h, 228)
    self:rect(x, y, w, h, 249)
    local cover = self.library:cover(book)
    if cover then
        local widget = ImageWidget:new{
            file = cover.file, image = cover.image,
            width = w, height = h, scale_factor = 0,
            image_disposable = true, alpha = true,
        }
        -- Decode now so a malformed cover can fall back before the paint pass.
        local ok, err = pcall(widget.getSize, widget)
        if ok then
            self:addWidget(widget, x, y)
            self:outline(x, y, w, h, 198)
            return
        end
        pcall(widget.free, widget)
        logger.warn("Kindlevel: cannot render cover", book.file, err)
    end
    self:outline(x, y, w, h, 175)
    self:rect(x + self:px(8), y, math.max(1, self:px(1)), h, 212)
    self:text(book.format, x + self:px(18), y + self:px(20), w - self:px(30), self:px(22), small and 10 or 12,
        { single = true, gray = 100 })
    self:text(book.title, x + self:px(18), y + math.floor(h * 0.3), w - self:px(35), math.floor(h * 0.5),
        small and 14 or 25, { serif = true })
    self:rect(x + self:px(18), y + h - self:px(27), w - self:px(36), math.max(1, self:px(1)), 185)
end

function Home:header()
    local p, w = self:px(28), self.width
    self:text("KINDLEVEL", p, self:px(22), w - 2 * p, self:px(25), 12,
        { single = true, gray = 70 })
    if self.owner.previewAchievement then
        self:addWidget(ImageWidget:new{
            file = self.owner.plugin_dir .. "/assets/achievement.svg", width = self:px(24), height = self:px(24), alpha = true,
        }, w - self:px(170), self:px(22))
        self:hit(w - self:px(189), 0, self:px(60), self:px(55), function()
            self.tab = "achievements"; self:rebuild()
        end, "tab-achievements")
    end
    self:addWidget(ImageWidget:new{
        file = self.owner.plugin_dir .. "/assets/settings.svg", width = self:px(22), height = self:px(22), alpha = true,
    }, w - self:px(110), self:px(23))
    self:hit(w - self:px(128), 0, self:px(58), self:px(55), function()
        self.settings_return_tab = self.tab
        self.tab = "settings"; self:rebuild()
    end, "tab-settings")
    self:text("×", w - self:px(66), self:px(10), self:px(48), self:px(42), 29,
        { center = true, single = true })
    self:hit(w - self:px(75), 0, self:px(75), self:px(55), function() self:onClose() end, "close")
    self:readingSummary()
end

function Home:summaryTrack(x, width, ratio)
    self:rect(x, self:px(120), width, self:px(2), 226)
    self:rect(x, self:px(120), math.floor(width * math.max(0, math.min(1, ratio))), self:px(2), 35)
end

function Home:summaryNavigate(view)
    if self.tab ~= "stats" then
        self.stats_view, self.stats_history, self.stats_list_page = "overview", {}, 1
    end
    self.tab = "stats"
    self:statsNavigate(view)
end

function Home:readingSummary()
    local p, width = self:px(28), self.width - self:px(56)
    local stats = self.owner:getStats():load()
    local today_key = os.date("%Y-%m-%d", stats.now)
    local seconds = (stats.days[today_key] or {}).seconds or 0
    local goal = self.owner.settings:readSetting("daily_minutes", 20)
    local left_width = math.floor(width * 2 / 3) - self:px(32)
    local right = p + math.floor(width * 2 / 3)
    local right_width = p + width - right
    local detail = p + math.floor(left_width * 0.47)
    local detail_width = left_width - (detail - p)
    self:text("TODAY", p, self:px(65), left_width, self:px(18), 10, { single = true, gray = 85 })
    local streak = stats:streak()
    if streak > 0 then
        self:text(string.format("Streak · %d %s", streak, streak == 1 and "day" or "days"), detail,
            self:px(65), detail_width, self:px(18), 10, { single = true, gray = 85 })
    end
    self:text(stats.error and "—" or Stats.duration(seconds), p, self:px(84), detail - p - self:px(8), self:px(31), 25,
        { single = true, serif = true })
    local caption = stats.error == "missing" and "No reading history"
        or stats.error and "History unavailable"
        or goal > 0 and string.format(seconds >= goal * 60 and "Goal reached · %d min" or "%d min goal", goal)
        or "Reading time today"
    self:text(caption, detail, self:px(95), detail_width, self:px(20), 10, { single = true, gray = 85 })
    if goal > 0 and not stats.error then self:summaryTrack(p, left_width, seconds / (goal * 60)) end
    self:hit(p, self:px(60), left_width, self:px(65), function()
        self:summaryNavigate("day"); self.stats_date, self.stats_list_page = today_key, 1; self:rebuild()
    end, "today-reading")

    local year = tonumber(os.date("%Y", stats.now))
    if self.tab == "stats" then
        year = self.stats_view == "goal" and (self.stats_goal_year or self.stats_year)
            or self.stats_view == "month" and tonumber(os.date("%Y", self.stats_month))
            or self.stats_period == "year" and self.stats_year or year
    end
    self:text(tostring(year) .. " · BOOKS", right, self:px(65), right_width, self:px(18), 10, { single = true, gray = 85 })
    if self.owner.getGoals then
        local goals = self.owner:getGoals()
        local target, completed = goals:target(year), #goals:list(year)
        self:text(target > 0 and string.format("%d / %d", completed, target) or tostring(completed), right,
            self:px(84), right_width, self:px(31), 25, { single = true, serif = true })
        if target > 0 then self:summaryTrack(right, right_width, completed / target) end
        self:hit(right, self:px(60), right_width, self:px(65), function()
            self:summaryNavigate("goal"); self.stats_goal_year, self.stats_list_page = year, 1; self:rebuild()
        end, "year-goal")
    else
        self:text("—", right, self:px(84), right_width, self:px(31), 25, { single = true, serif = true })
    end
end

function Home:reading()
    local w, h, p = self.width, self.height, self:px(28)
    local book = self.library.books[self.index]
    if not book then
        self:text("A place for your books", p, math.floor(h * 0.29), w - 2 * p, self:px(100), 32,
            { center = true, serif = true })
        self:text("Choose a folder on your Kindle,\nor open the sample library to try it out.", p,
            math.floor(h * 0.45), w - 2 * p, self:px(70), 18, { center = true, gray = 90 })
        self:button("Choose books folder", p, math.floor(h * 0.62), w - 2 * p, self:px(50),
            function() self.owner:chooseFolder() end, true, "choose-folder")
        self:button("Try sample books", p, math.floor(h * 0.71), w - 2 * p, self:px(50),
            function() self.owner:useSamples() end, false, "samples")
        return
    end
    self.library:inspect(book)
    self:text(book.title, p, math.floor(h * 0.165), w - 2 * p, self:px(60), 27,
        { center = true, serif = true })
    self:text(book.author, p, math.floor(h * 0.243), w - 2 * p, self:px(24), 13,
        { center = true, single = true, gray = 85 })

    local cw = math.floor(w * 0.37)
    local ch = math.floor(h * 0.365)
    local cx, cy = math.floor((w - cw) / 2), math.floor(h * 0.302)
    local sw, sh = math.floor(cw * 0.46), math.floor(ch * 0.56)
    local sy = cy + ch - sh - self:px(22)
    local previous, following = self.library.books[self.index - 1], self.library.books[self.index + 1]
    if previous then
        self.library:inspect(previous)
        self:cover(previous, p, sy, sw, sh, true)
        self:hit(0, cy, cx - self:px(8), ch, function() self:onPrevious() end, "previous")
    end
    if following then
        self.library:inspect(following)
        self:cover(following, w - p - sw, sy, sw, sh, true)
        self:hit(cx + cw + self:px(8), cy, w - cx - cw - self:px(8), ch, function() self:onNext() end, "next")
    end
    self:cover(book, cx, cy, cw, ch, false)
    self:hit(cx, cy, cw, ch, function() self.owner:openBook(book) end, "open-cover")
    self:text(string.format("%d / %d", self.index, #self.library.books), p, math.floor(h * 0.694), w - 2 * p,
        self:px(20), 11, { center = true, single = true, gray = 105 })
    local progress_y = math.floor(h * 0.743)
    local track_w = math.floor(w * 0.54)
    local track_x = math.floor((w - track_w) / 2)
    self:rect(track_x, progress_y, track_w, self:px(2), 214)
    if book.percent then
        self:rect(track_x, progress_y, math.floor(track_w * book.percent), self:px(2), 0)
    end
    local progress = book.percent and string.format("%d%% read", math.floor(book.percent * 100 + 0.5)) or "Not started"
    if book.started and not book.percent then progress = "Ready to continue" end
    self:text(progress, p, progress_y + self:px(11), w - 2 * p, self:px(23), 13,
        { center = true, single = true, gray = 80 })
    local bw = math.floor(w * 0.54)
    self:button(book.started and "Continue reading" or "Start reading", math.floor((w - bw) / 2),
        math.floor(h * 0.803), bw, self:px(48), function() self.owner:openBook(book) end, true, "start-reading")
    if self.owner.getStats then
        local y = math.floor(h * 0.871)
        self:text("Book statistics →", p, y, w - 2 * p, self:px(25), 13, { center = true, single = true, gray = 75 })
        self:hit(p, y - self:px(3), w - 2 * p, self:px(29), function()
            local match = self.owner:getStats():findBook(book)
            self.stats_book_id = match and match.id
            self.stats_book_title = book.title
            self.stats_library_book = book
            self.stats_view, self.tab = "book", "stats"
            self:rebuild()
        end, "book-statistics")
    end
end

function Home:libraryGrid()
    local w, h, p = self.width, self.height, self:px(28)
    local first = (self.page - 1) * 6 + 1
    local pages = math.max(1, math.ceil(#self.library.books / 6))
    self:text("Your library", p, self:px(139), w - 2 * p, self:px(43), 29, { serif = true, single = true })
    self:text(self.library:folderLabel(), p, self:px(184), w - 2 * p, self:px(22), 12,
        { single = true, gray = 95 })
    if #self.library.books == 0 then
        self:text("No readable books in this folder.", p, math.floor(h * 0.37), w - 2 * p,
            self:px(75), 23, { center = true, serif = true })
        self:button("Choose books folder", p, math.floor(h * 0.57), w - 2 * p, self:px(50),
            function() self.owner:chooseFolder() end, true, "choose-folder")
        return
    end
    local grid_top = self:px(225)
    local grid_bottom = math.floor(h * 0.81)
    local row_h = math.floor((grid_bottom - grid_top) / 3)
    local cell_w = math.floor((w - 2 * p - self:px(22)) / 2)
    for slot = 0, 5 do
        local book_index = first + slot
        local book = self.library.books[book_index]
        if book then
            self.library:inspect(book)
            local x = p + (slot % 2) * (cell_w + self:px(22))
            local y = grid_top + math.floor(slot / 2) * row_h
            local cover_h = math.max(self:px(55), row_h - self:px(26))
            local cover_w = math.floor(cover_h * 0.65)
            self:cover(book, x, y, cover_w, cover_h, true)
            local tx = x + cover_w + self:px(12)
            local tw = cell_w - cover_w - self:px(12)
            self:text(book.title, tx, y + self:px(4), tw, math.floor(cover_h * 0.57), 17, { serif = true })
            self:text(book.format, tx, y + cover_h - self:px(27), tw, self:px(22), 10, { single = true, gray = 90 })
            self:hit(x, y, cell_w, row_h - self:px(8), function()
                self.index = book_index
                self.tab = "read"
                self:rememberSelection()
                self:rebuild()
            end, "book-" .. tostring(book_index))
        end
    end
    local y = math.floor(h * 0.835)
    self:button("‹", p, y, self:px(64), self:px(43), function() self:onPrevious() end, false, "previous-page")
    self:text(string.format("%d / %d", self.page, pages), p + self:px(80), y + self:px(10), w - 2 * p - self:px(160),
        self:px(25), 14, { center = true, single = true })
    self:button("›", w - p - self:px(64), y, self:px(64), self:px(43), function() self:onNext() end, false, "next-page")
end

function Home:settingsPanel()
    local p, w = self:px(28), self.width
    self:text("Make yourself at home", p, self:px(145), w - 2 * p, self:px(77), 29, { serif = true })
    self:text("BOOKS FOLDER", p, self:px(217), w - 2 * p, self:px(24), 11, { single = true, gray = 90 })
    self:text(self.library.root, p, self:px(244), w - 2 * p, self:px(48), 13, { gray = 65 })
    local actions = {
        { "Choose books folder", function() self.owner:chooseFolder() end, "choose-folder" },
        { "Refresh library", function() self:rescan() end, "refresh" },
        { "Open sample library", function() self.owner:useSamples() end, "samples" },
        { self.owner.settings:isTrue("auto_home") and "[✓] Show home on file browser entry" or "[ ] Show home on file browser entry",
            function() self.owner:toggleAutoHome() end, "auto-home" },
        { "Daily reading goal", function() self.owner:setDailyGoal() end, "daily-goal" },
        { "Yearly book goal", function() self.owner:setYearGoal() end, "yearly-goal" },
        { "Reading statistics tools", function() self.owner:statisticsTools() end, "statistics-tools" },
        { "Refresh statistics", function() self.owner:refreshStats() end, "refresh-stats" },
    }
    for i, action in ipairs(actions) do
        self:button(action[1], p, self:px(300 + (i - 1) * 45), w - 2 * p, self:px(39), action[2], false, action[3])
    end
    local note = "Kindlevel 0.3.0 · Your reading, at a glance."
    if next(self.library.warnings) then note = note .. "\nSome folders were skipped; choose a smaller books folder." end
    self:text(note, p, self:px(670), w - 2 * p, self:px(45), 12, { center = true, gray = 95 })
end

function Home:navigation()
    local y, h = math.floor(self.height * 0.914), self:px(56)
    local cell = math.floor(self.width / 3)
    self:rect(self:px(28), y - self:px(12), self.width - self:px(56), math.max(1, self:px(1)), 220)
    for i, item in ipairs{ { "stats", "Statistics", "statistics" }, { "read", "Reading", "reading" }, { "library", "Library", "library" } } do
        local x = (i - 1) * cell
        local size = self:px(26)
        self:addWidget(ImageWidget:new{
            file = self.owner.plugin_dir .. "/assets/" .. item[3] .. ".svg",
            width = size, height = size, alpha = true,
        }, x + math.floor((cell - size) / 2), y)
        self:text(item[2], x, y + self:px(32), cell, self:px(20), 11,
            { center = true, single = true, gray = self.tab == item[1] and 0 or 100 })
        if self.tab == item[1] then
            self:rect(x + math.floor(cell * 0.37), y + self:px(57), math.floor(cell * 0.26), self:px(2), 0)
        end
        self:hit(x, y - self:px(10), cell, h + self:px(12), function()
            self.tab = item[1]
            if self.tab == "stats" then self.stats_view = "overview"; self.stats_history = {} end
            self.page = math.floor((self.index - 1) / 6) + 1
            self:rebuild()
        end, "tab-" .. item[1])
    end
end

function Home:freeResources()
    for _, widget in ipairs(self.resources or {}) do widget:free() end
    self.resources = {}
end

function Home:rebuild()
    if self.closed then return end
    self:freeResources()
    self.width, self.height = Screen:getWidth(), Screen:getHeight()
    self.scale = math.min(self.width / 600, self.height / 800)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.draw, self.hits = {}, {}
    self.ges_events.TapKindlevel = { GestureRange:new{ ges = "tap", range = self.dimen } }
    self.ges_events.SwipeKindlevel = { GestureRange:new{ ges = "swipe", range = self.dimen } }
    self:header()
    if self.tab == "stats" then self:statsPanel()
    elseif self.tab == "library" then self:libraryGrid()
    elseif self.tab == "settings" then self:settingsPanel()
    elseif self.tab == "achievements" then self:achievementPanel()
    else self:reading() end
    self:navigation()
    UIManager:setDirty(self, "full")
end

function Home:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    for _, command in ipairs(self.draw) do
        if command.kind == "rect" then
            bb:paintRect(x + command.x, y + command.y, command.w, command.h, Blitbuffer.Color8(command.gray))
        elseif command.kind == "custom" then command.paint(bb, x, y)
        else command.widget:paintTo(bb, x + command.x, y + command.y) end
    end
end

function Home:onTapKindlevel(_, gesture)
    for _, hit in ipairs(self.hits) do
        local pos = gesture.pos
        if pos.x >= hit.x and pos.x < hit.x + hit.w and pos.y >= hit.y and pos.y < hit.y + hit.h then
            hit.callback()
            return true
        end
    end
    return true
end

function Home:onSwipeKindlevel(_, gesture)
    if gesture.direction == "west" or gesture.direction == "north" then self:onNext()
    elseif gesture.direction == "east" or gesture.direction == "south" then self:onPrevious() end
    return true
end

function Home:rememberSelection()
    local book = self.library.books[self.index]
    if book then
        self.owner.settings:saveSetting("selected_file", book.file)
        self.owner.settings:flush()
    end
end

function Home:onNext()
    if self.tab == "achievements" then return self:achievementNext(1)
    elseif self.tab == "stats" then return self:statsNext(1)
    elseif self.tab == "library" then
        self.page = math.min(math.max(1, math.ceil(#self.library.books / 6)), self.page + 1)
    elseif self.tab == "read" then
        self.index = math.min(math.max(1, #self.library.books), self.index + 1)
        self:rememberSelection()
    else return true end
    self:rebuild()
    return true
end

function Home:onPrevious()
    if self.tab == "achievements" then return self:achievementNext(-1)
    elseif self.tab == "stats" then return self:statsNext(-1)
    elseif self.tab == "library" then self.page = math.max(1, self.page - 1)
    elseif self.tab == "read" then
        self.index = math.max(1, self.index - 1)
        self:rememberSelection()
    else return true end
    self:rebuild()
    return true
end

function Home:onOpen()
    if self.tab == "read" then self.owner:openBook(self.library.books[self.index]) end
    return true
end

function Home:rescan()
    local selected = self.library.books[self.index]
    self.library:scan()
    self.index = self.library:find(selected and selected.file)
    self.page = math.floor((self.index - 1) / 6) + 1
    self:rebuild()
end

function Home:onBack()
    if self.tab == "stats" and self.stats_view ~= "overview" then
        local previous = table.remove(self.stats_history)
        if previous then
            self.stats_view, self.stats_date, self.stats_book_id, self.stats_list_page =
                previous.view, previous.date, previous.book_id, previous.page
        else self.stats_view = "overview" end
        self:rebuild()
    elseif self.tab == "settings" then self.tab = self.settings_return_tab or "read"; self:rebuild()
    elseif self.tab ~= "read" then self.tab = "read"; self:rebuild()
    else self:onClose() end
    return true
end

function Home:onHome()
    return self:onBack()
end

function Home:onSetDimensions()
    self:rebuild()
end

function Home:onResume()
    if not self.closed then UIManager:setDirty(self, "full") end
end

function Home:onClose()
    if not self.closed then UIManager:close(self, "full") end
    return true
end

function Home:onCloseWidget()
    self.closed = true
    self:freeResources()
    if self.owner.home == self then self.owner.home = nil end
end

for name, method in pairs(require("kindlevel_stats_screen")) do Home[name] = method end
for name, method in pairs(require("kindlevel_achievements_screen")) do Home[name] = method end
return Home
