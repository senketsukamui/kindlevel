local Blitbuffer = require("ffi/blitbuffer")
local Stats = require("kindlevel_stats")
local UIManager = require("ui/uimanager")
local View = {}

function View:statsCards(values, top)
    local p, width = self:px(28), self.width
    local cell = math.floor((width - 2 * p) / 2)
    for i, value in ipairs(values) do
        local x = p + ((i - 1) % 2) * cell
        local y = top + math.floor((i - 1) / 2) * self:px(83)
        self:text(value[1], x, y, cell, self:px(47), 37, { center = true, single = true })
        self:text(value[2], x, y + self:px(49), cell, self:px(22), 12,
            { center = true, single = true, gray = 85 })
    end
end

function View:statsControls()
    local p, width = self:px(28), self.width
    local labels = { { "7", "7 days" }, { "14", "14 days" }, { "30", "30 days" }, { "year", "Year" }, { "all", "All" } }
    local cell = math.floor((width - 2 * p) / #labels)
    for i, label in ipairs(labels) do
        local x, y = p + (i - 1) * cell, self:px(132)
        self:text(label[2], x, y + self:px(7), cell, self:px(23), 13, { center = true, single = true })
        if self.stats_period == label[1] then self:rect(x + self:px(12), y + self:px(35), cell - self:px(24), self:px(2), 0) end
        self:hit(x, y, cell, self:px(43), function()
            self.stats_period = label[1]; self.stats_view = "overview"; self.stats_history = {}; self:rebuild()
        end, "period-" .. label[1])
    end
end

local function line(bb, x1, y1, x2, y2, width, gray)
    local steps = math.max(math.abs(x2 - x1), math.abs(y2 - y1), 1)
    for step = 0, steps do
        local x = math.floor(x1 + (x2 - x1) * step / steps)
        local y = math.floor(y1 + (y2 - y1) * step / steps)
        bb:paintRect(x, y, width, width, Blitbuffer.Color8(gray))
    end
end

function View:statsChart(series, x, y, width, height)
    local metric = self.stats_metric
    local buckets = series
    if #series > 60 then
        buckets = {}
        local size = math.ceil(#series / 30)
        for i = 1, #series, size do
            local value = { date = series[i].date, timestamp = series[i].timestamp, pages = 0, seconds = 0 }
            for j = i, math.min(i + size - 1, #series) do
                value.pages = value.pages + series[j].pages
                value.seconds = value.seconds + series[j].seconds
            end
            buckets[#buckets + 1] = value
        end
    end
    local maximum = 1
    for _, item in ipairs(buckets) do maximum = math.max(maximum, metric == "pages" and item.pages or item.seconds / 60) end
    maximum = math.max(1, math.ceil(maximum / 5) * 5)
    for i = 0, 3 do
        local ly = y + math.floor(height * i / 3)
        self:rect(x, ly, width, math.max(1, self:px(0.5)), 229)
        self:text(tostring(math.floor(maximum * (3 - i) / 3)), self:px(4), ly - self:px(8), x - self:px(12), self:px(20), 10,
            { center = true, single = true, gray = 105 })
    end
    local points = {}
    for i, item in ipairs(buckets) do
        local value = metric == "pages" and item.pages or item.seconds / 60
        points[i] = { x = x + math.floor((i - 1) * width / math.max(1, #buckets - 1)),
            y = y + height - math.floor(height * value / maximum) }
        if #series <= 30 then
            local step = width / math.max(1, #buckets - 1)
            local left = math.max(x, points[i].x - step / 2)
            local right = math.min(x + width, points[i].x + step / 2)
            if #buckets == 1 then left, right = x, x + width end
            self:hit(left, y, right - left, height, function() self:statsOpenDay(item.date) end, "chart-day-" .. item.date)
        end
    end
    local stroke = math.max(1, self:px(1))
    self.draw[#self.draw + 1] = { kind = "custom", paint = function(bb, ox, oy)
        for i = 2, #points do
            local a, b = points[i - 1], points[i]
            for px = a.x, b.x do
                local py = math.floor(a.y + (b.y - a.y) * (px - a.x) / math.max(1, b.x - a.x))
                bb:paintRect(ox + px, oy + py, 1, y + height - py, Blitbuffer.Color8(231))
            end
            line(bb, ox + a.x, oy + a.y, ox + b.x, oy + b.y, stroke, 50)
        end
    end }
    if #buckets > 0 then
        self:text(os.date("%d %b", buckets[1].timestamp), x, y + height + self:px(10), width / 2, self:px(22), 10,
            { single = true, gray = 95 })
        self:text(os.date("%d %b", buckets[#buckets].timestamp), x + width / 2, y + height + self:px(10), width / 2, self:px(22), 10,
            { center = true, single = true, gray = 95 })
    end
end

function View:statsMetricToggle(y)
    local p, width = self:px(28), self.width
    self:text("Reading activity", p, y + self:px(5), width / 2, self:px(27), 16, { single = true })
    for i, metric in ipairs{ { "pages", "Pages" }, { "seconds", "Time" } } do
        local x = math.floor(width * 0.66) + (i - 1) * self:px(78)
        self:text(metric[2], x, y + self:px(7), self:px(70), self:px(22), 12, { center = true, single = true })
        if self.stats_metric == metric[1] then self:rect(x + self:px(8), y + self:px(33), self:px(54), self:px(1), 0) end
        self:hit(x, y, self:px(74), self:px(39), function() self.stats_metric = metric[1]; self:rebuild() end, "metric-" .. metric[1])
    end
end

function View:statsOverview()
    local stats, p = self.owner:getStats():load(), self:px(28)
    self:statsControls()
    local series, totals = stats:series(self.stats_period, self.stats_year)
    self:statsCards({
        { Stats.number(totals.pages), "Pages read" }, { Stats.duration(totals.seconds), "Reading time" },
        { string.format("%.1f", totals.average), "Average pages / day" }, { Stats.number(totals.record), "Best day · pages" },
    }, self:px(189))
    self:text(string.format("%d active days · %d books in your history", totals.active_days, #stats.books), p,
        self:px(359), self.width - 2 * p, self:px(23), 12, { center = true, single = true, gray = 95 })
    if self.stats_period == "year" then self:statsCalendar(series)
    else
        self:statsMetricToggle(self:px(397))
        self:statsChart(series, self:px(51), self:px(450), self.width - self:px(84), self:px(182))
        local note = stats.error == "missing" and "Enable Reading statistics in KOReader to begin."
            or stats.error and "Reading history is temporarily unavailable. Try Refresh statistics."
            or totals.seconds == 0 and "Your reading history will appear here as you read."
            or #series > 60 and "Activity is grouped across this period. Tap the book count for details."
            or "Tap a day in the chart to see its reading sessions."
        self:text(note, p, self:px(670), self.width - 2 * p, self:px(24), 10, { center = true, gray = 95 })
        self:statsMonthLink()
    end
    if self.stats_period ~= "year" then
        self:hit(p, self:px(350), self.width - 2 * p, self:px(39), function()
            self:statsNavigate("books"); self.stats_list_page = 1; self:rebuild()
        end, "stats-books")
    end
end

function View:statsCalendar(series)
    local p = self:px(28)
    self:button("‹", p, self:px(391), self:px(54), self:px(33), function() self:statsNext(-1) end, false, "previous-year")
    self:text(tostring(self.stats_year), p + self:px(60), self:px(394), self.width - 2 * p - self:px(120), self:px(30), 18,
        { center = true, single = true })
    self:button("›", self.width - p - self:px(54), self:px(391), self:px(54), self:px(33), function() self:statsNext(1) end, false, "next-year")
    local step = math.floor((self.width - 2 * p) / 27)
    local size = math.min(step - self:px(3), self:px(14))
    local january = series[1] and series[1].timestamp
    local offset = january and (tonumber(os.date("%w", january)) + 6) % 7 or 0
    local maximum = 1
    for _, day in ipairs(series) do maximum = math.max(maximum, day.pages) end
    for index, day in ipairs(series) do
        local position = index - 1 + offset
        local week, weekday = math.floor(position / 7), position % 7
        local panel, column = math.floor(week / 27), week % 27
        local x = p + column * step
        local top = self:px(452 + panel * 137)
        local y = top + weekday * self:px(16)
        if day.date:sub(-2) == "01" then
            self:text(os.date("%b", day.timestamp), x, top - self:px(25), self:px(49), self:px(20), 10,
                { single = true, gray = 100 })
        end
        local gray = day.pages == 0 and 247 or 215 - math.floor(180 * math.sqrt(day.pages / maximum))
        if day.future then gray = 255 end
        self:rect(x, y, size, size, gray)
        if day.pages == 0 then self:outline(x, y, size, size, day.future and 234 or 216) end
        if not day.future then self:hit(x, y, size, size, function() self:statsOpenDay(day.date) end, "calendar-" .. day.date) end
    end
    self:statsMonthLink()
end

function View:statsMonthLink()
    local p = self:px(28)
    local half = (self.width - 2 * p) / 2
    self:text("Book calendar →", p, self:px(707), half, self:px(22), 12,
        { center = true, single = true, gray = 60 })
    self:hit(p, self:px(702), half, self:px(27), function()
        self:statsNavigate("month"); self:rebuild()
    end, "book-calendar")
    self:text("Return statistics →", p + half, self:px(707), half, self:px(22), 12,
        { center = true, single = true, gray = 60 })
    self:hit(p + half, self:px(702), half, self:px(27), function()
        self:statsNavigate("recovery"); self.stats_list_page = 1; self:rebuild()
    end, "return-statistics")
end

function View:statsOpenDay(key)
    self:statsNavigate("day")
    self.stats_date, self.stats_list_page = key, 1
    self:rebuild()
end

function View:statsNavigate(view)
    self.stats_history[#self.stats_history + 1] = { view = self.stats_view,
        date = self.stats_date, book_id = self.stats_book_id, page = self.stats_list_page }
    self.stats_view = view
    if view == "book" then self.stats_library_book = nil end
end

function View:statsDay()
    local stats, p = self.owner:getStats():load(), self:px(28)
    local key = self.stats_date or os.date("%Y-%m-%d")
    local timestamp = Stats.date(key)
    local details = stats:dayDetails(key)
    local day = stats.days[key] or { pages = 0, seconds = 0 }
    self:button("‹", p, self:px(137), self:px(54), self:px(37), function() self:statsNext(-1) end, false, "previous-day")
    self:text(os.date("%a, %d %B", timestamp), p + self:px(60), self:px(144), self.width - 2 * p - self:px(120), self:px(40), 22,
        { center = true, single = true, serif = true })
    self:button("›", self.width - p - self:px(54), self:px(137), self:px(54), self:px(37), function() self:statsNext(1) end, false, "next-day")
    self:statsCards({ { Stats.number(day.pages), "Pages read" }, { Stats.duration(day.seconds), "Reading time" } }, self:px(200))
    self:text(string.format("%d %s · %d %s", #details.sessions, #details.sessions == 1 and "session" or "sessions",
        #details.books, #details.books == 1 and "book" or "books"), p, self:px(284), self.width - 2 * p,
        self:px(28), 13, { center = true, single = true, gray = 90 })
    self:text("Your day", p, self:px(333), self.width - 2 * p, self:px(30), 18, { single = true })
    local tx, tw, ty = p, self.width - 2 * p, self:px(379)
    self:rect(tx, ty, tw, self:px(22), 240)
    local day_end = Stats.day(timestamp, 1)
    for _, session in ipairs(details.sessions) do
        local start = math.max(0, math.min(1, (session.start - timestamp) / (day_end - timestamp)))
        local finish = math.max(start, math.min(1, (session.finish - timestamp) / (day_end - timestamp)))
        self:rect(tx + math.floor(tw * start), ty, math.max(self:px(2), math.floor(tw * (finish - start))), self:px(22), 60)
    end
    for hour = 0, 24, 6 do
        local width = self:px(42)
        local x = math.max(tx, math.min(tx + tw - width, tx + tw * hour / 24 - width / 2))
        self:text(string.format("%02d:00", hour), x, ty + self:px(31), width, self:px(24), 10,
            { single = true, gray = 95 })
    end
    self:text("Reading journal", p, self:px(447), tw, self:px(28), 18, { single = true })
    local first = (self.stats_list_page - 1) * 4 + 1
    for slot = 0, 3 do
        local session = details.sessions[first + slot]
        if session then
            local y = self:px(488 + slot * 47)
            self:text(session.title, p, y, tw - self:px(125), self:px(25), 14, { single = true })
            self:text(os.date("%H:%M", session.start) .. "–" .. os.date("%H:%M", session.finish), p, y + self:px(25),
                tw - self:px(125), self:px(17), 10, { single = true, gray = 105 })
            self:text(Stats.duration(session.seconds), self.width - p - self:px(120), y + self:px(9), self:px(120), self:px(25), 12,
                { center = true, single = true })
            self:hit(p, y, tw, self:px(46), function()
                self:statsNavigate("book"); self.stats_book_id = session.book_id; self:rebuild()
            end, "session-" .. tostring(first + slot))
        end
    end
    if #details.sessions == 0 then self:text("No reading recorded on this day.", p, self:px(520), tw, self:px(40), 17,
        { center = true, gray = 100 }) end
    if #details.sessions > 4 then
        local pages = math.ceil(#details.sessions / 4)
        self:button("‹", p, self:px(691), self:px(54), self:px(29), function()
            self.stats_list_page = math.max(1, self.stats_list_page - 1); self:rebuild()
        end, false, "sessions-previous")
        self:text(string.format("%d / %d", self.stats_list_page, pages), p + self:px(60), self:px(697), tw - self:px(120), self:px(23), 11,
            { center = true, single = true })
        self:button("›", self.width - p - self:px(54), self:px(691), self:px(54), self:px(29), function()
            self.stats_list_page = math.min(pages, self.stats_list_page + 1); self:rebuild()
        end, false, "sessions-next")
    end
end

function View:statsBook()
    local stats, p = self.owner:getStats():load(), self:px(28)
    local book = stats:book(self.stats_book_id)
    self:text(book and book.title or self.stats_book_title or "Book statistics", p, self:px(141), self.width - 2 * p, self:px(65), 25,
        { center = true, serif = true })
    if not book then
        self:text("No recorded history for this book yet.\nKeep Reading statistics enabled while you read.", p, self:px(300),
            self.width - 2 * p, self:px(100), 20, { center = true, gray = 85 })
        if self.stats_library_book and self.owner.recordFinish then
            self:button("Record finish", p, self:px(485), self.width - 2 * p, self:px(46), function()
                self.owner:recordFinish(self.stats_library_book)
            end, false, "record-finish")
        end
        return
    end
    self:statsCards({ { Stats.number(book.pages), "Distinct pages read" }, { Stats.duration(book.seconds), "Reading time" },
        { tostring(book.highlights), "Highlights" }, { tostring(book.notes), "Notes" } }, self:px(217))
    self:text(string.format("%d reading days · %s per page", book.active_days,
        string.format("%.0f sec", book.average_seconds)), p, self:px(383),
        self.width - 2 * p, self:px(25), 12, { center = true, single = true, gray = 90 })
    self:statsMetricToggle(self:px(423))
    local series = stats:series("30", nil, book.id)
    self:statsChart(series, self:px(51), self:px(477), self.width - self:px(84), self:px(157))
    local period = book.first and os.date("%d %b %Y", book.first) .. " → " .. os.date("%d %b %Y", book.last) or ""
    self:text(period, p, self:px(664), self.width - 2 * p, self:px(22), 11, { center = true, single = true, gray = 100 })
    local half = (self.width - 2 * p) / 2
    self:text("Book journey →", p, self:px(700), half, self:px(24), 13, { center = true, single = true })
    self:hit(p, self:px(694), half, self:px(30), function()
        self:statsNavigate("journey"); self.stats_list_page = 1; self:rebuild()
    end, "book-journey")
    if self.owner.recordFinish then
        self:text("Record finish →", p + half, self:px(700), half, self:px(24), 13,
            { center = true, single = true })
        self:hit(p + half, self:px(694), half, self:px(30), function()
            self.owner:recordFinish(book)
        end, "record-finish")
    end
end

function View:statsBooks()
    local stats, p = self.owner:getStats():load(), self:px(28)
    self:text("Your reading history", p, self:px(145), self.width - 2 * p, self:px(53), 28, { serif = true, single = true })
    local first = (self.stats_list_page - 1) * 6 + 1
    for slot = 0, 5 do
        local book = stats.books[first + slot]
        if book then
            local y = self:px(223 + slot * 70)
            self:text(book.title, p, y, self.width - 2 * p, self:px(30), 18, { serif = true, single = true })
            self:text(string.format("%s · %s pages · %d reading days", Stats.duration(book.seconds), Stats.number(book.pages), book.active_days),
                p, y + self:px(32), self.width - 2 * p, self:px(25), 12, { single = true, gray = 95 })
            self:rect(p, y + self:px(63), self.width - 2 * p, self:px(1), 231)
            self:hit(p, y, self.width - 2 * p, self:px(65), function()
                self:statsNavigate("book"); self.stats_book_id = book.id; self:rebuild()
            end, "history-book-" .. tostring(book.id))
        end
    end
    self:text("Swipe to browse · Back returns to overview", p, self:px(683), self.width - 2 * p, self:px(24), 12,
        { center = true, single = true, gray = 100 })
end

function View:statsPanel()
    if self.stats_view == "journey" then self:statsJourney()
    elseif self.stats_view == "recovery" then self:statsRecovery()
    elseif self.stats_view == "month" then self:statsMonth()
    elseif self.stats_view == "goal" then self:statsGoal()
    elseif self.stats_view == "day" then self:statsDay()
    elseif self.stats_view == "book" then self:statsBook()
    elseif self.stats_view == "books" then self:statsBooks()
    else self:statsOverview() end
end

function View:statsNext(direction)
    local stats = self.owner:getStats()
    if self.stats_view == "journey" or self.stats_view == "recovery" then
        local Journey = require("kindlevel_journey")
        local history = Journey:new(stats)
        local count = self.stats_view == "journey" and #history:book(self.stats_book_id, self:journeyThreshold()).episodes
            or #history:recovery(self:journeyThreshold(), self.stats_recovery_mode).returns
        self.stats_list_page = math.max(1, math.min(math.max(1, math.ceil(count / 3)), self.stats_list_page + direction))
    elseif self.stats_view == "day" then
        local next_day = Stats.day(Stats.date(self.stats_date), direction)
        if next_day <= Stats.day(stats.now) then self.stats_date = os.date("%Y-%m-%d", next_day) end
        self.stats_list_page = 1
    elseif self.stats_view == "month" then
        self:statsMoveMonth(direction)
        return true
    elseif self.stats_view == "goal" then
        self.stats_goal_year = math.max(1970, math.min(tonumber(os.date("%Y", stats.now)), self.stats_goal_year + direction))
        self.stats_list_page = 1
    elseif self.stats_view == "books" then
        self.stats_list_page = math.max(1, math.min(math.max(1, math.ceil(#stats.books / 6)), self.stats_list_page + direction))
    elseif self.stats_period == "year" then
        self.stats_year = math.max(1970, math.min(tonumber(os.date("%Y", stats.now)), self.stats_year + direction))
    else return true end
    self:rebuild()
    return true
end

for name, method in pairs(require("kindlevel_calendar")) do View[name] = method end
for name, method in pairs(require("kindlevel_journey_screen")) do View[name] = method end

return View
