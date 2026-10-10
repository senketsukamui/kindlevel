local Stats = require("kindlevel_stats")
local Calendar = {}

-- Pack actual consecutive reading days into ribbons, splitting at week boundaries.
-- Titles keep their lane across neighboring weeks when an overlap allows it.
function Calendar.monthLayout(data, lanes)
    local offset = (tonumber(os.date("%w", data.begin)) + 6) % 7
    local count = tonumber(os.date("%d", Stats.day(data.finish, -1)))
    local weeks = math.ceil((offset + count) / 7)
    local per_book, ribbons, preferred = {}, {}, {}
    for date, day in pairs(data.days) do
        local position = offset + tonumber(date:sub(-2)) - 1
        for _, book in ipairs(day.books) do
            per_book[book.id] = per_book[book.id] or { title = book.title, dates = {} }
            per_book[book.id].dates[position] = true
        end
    end
    for week = 0, weeks - 1 do
        local spans = {}
        for id, book in pairs(per_book) do
            local column = 0
            while column < 7 do
                if book.dates[week * 7 + column] then
                    local first = column
                    while column + 1 < 7 and book.dates[week * 7 + column + 1] do column = column + 1 end
                    spans[#spans + 1] = { id = id, title = book.title, first = first, last = column, week = week }
                end
                column = column + 1
            end
        end
        table.sort(spans, function(a, b)
            if a.first ~= b.first then return a.first < b.first end
            if a.last ~= b.last then return a.last > b.last end
            return a.id < b.id
        end)
        local occupied = {}
        for _, span in ipairs(spans) do
            local lane = preferred[span.id]
            if not lane or (occupied[lane] or -1) >= span.first then
                lane = nil
                for candidate = 1, lanes do
                    if (occupied[candidate] or -1) < span.first then lane = candidate; break end
                end
            end
            span.lane = lane
            if lane then occupied[lane] = span.last; preferred[span.id] = lane end
            ribbons[#ribbons + 1] = span
        end
    end
    return { offset = offset, count = count, weeks = weeks, ribbons = ribbons }
end

function Calendar:statsMoveMonth(amount)
    local current = self.owner:getStats().now
    local target = Stats.month(self.stats_month, amount)
    if target <= Stats.month(current) then self.stats_month = target end
    self:rebuild()
end

function Calendar:statsMonth()
    local stats = self.owner:getStats()
    local data = stats:monthData(self.stats_month)
    local p, width = self:px(18), self.width
    self:text(os.date("%B %Y", data.begin), p, self:px(139), width - 2 * p, self:px(45), 28,
        { single = true, serif = true })
    local top, bottom = self:px(216), self:px(662)
    local initial = Calendar.monthLayout(data, 3)
    local cell_h = math.floor((bottom - top) / initial.weeks)
    local bar_h = self:px(14)
    local lanes = math.max(1, math.min(3, math.floor((cell_h - self:px(49)) / (bar_h + self:px(2)))))
    local layout = Calendar.monthLayout(data, lanes)
    local cell_w = math.floor((width - 2 * p) / 7)
    for column, name in ipairs{ "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" } do
        self:text(name, p + (column - 1) * cell_w, self:px(190), cell_w, self:px(25), 12,
            { center = true, single = true, bold = true, gray = 70 })
    end
    local maximum = 1
    for _, day in pairs(data.days) do
        for _, seconds in pairs(day.hours) do maximum = math.max(maximum, seconds) end
    end
    local hidden = {}
    for number = 1, layout.count do
        local position = layout.offset + number - 1
        local column, row = position % 7, math.floor(position / 7)
        local x, y = p + column * cell_w, top + row * cell_h
        local timestamp = Stats.day(data.begin, number - 1)
        local key = os.date("%Y-%m-%d", timestamp)
        local day = data.days[key]
        local future = timestamp > Stats.day(stats.now)
        self:outline(x, y, cell_w - self:px(2), cell_h - self:px(2), future and 226 or 180)
        if timestamp == Stats.day(stats.now) then
            self:outline(x + self:px(2), y + self:px(2), cell_w - self:px(6), cell_h - self:px(6), 40)
        end
        self:text(tostring(number), x + self:px(5), y + self:px(4), cell_w - self:px(10), self:px(23), 13,
            { single = true, bold = true, gray = future and 165 or 25 })
        if not future then self:hit(x, y, cell_w - self:px(2), cell_h - self:px(2), function()
            self:statsOpenDay(key)
        end, "month-day-" .. key) end
        local histogram_width = cell_w - self:px(9)
        for hour = 1, 24 do
            local seconds = day.hours[hour] or 0
            if seconds > 0 then
                local hx = x + self:px(4) + math.floor((hour - 1) * histogram_width / 24)
                local next_x = x + self:px(4) + math.floor(hour * histogram_width / 24)
                local height = math.max(self:px(1), math.floor(self:px(14) * seconds / maximum))
                self:rect(hx, y + cell_h - self:px(5) - height, math.max(1, next_x - hx), height, 55)
            end
        end
    end
    for _, span in ipairs(layout.ribbons) do
        if span.lane then
            local x = p + span.first * cell_w + self:px(3)
            local y = top + span.week * cell_h + self:px(29) + (span.lane - 1) * (bar_h + self:px(2))
            local w = (span.last - span.first + 1) * cell_w - self:px(8)
            local gray = ({ 45, 80, 115 })[(span.id - 1) % 3 + 1]
            self:rect(x, y, w, bar_h, gray)
            self:text(span.title, x + self:px(3), y + self:px(2), w - self:px(6), bar_h - self:px(2), 9,
                { center = true, single = true, gray = 255 })
            self:hit(x, y, w, bar_h, function()
                self:statsNavigate("book"); self.stats_book_id = span.id; self:rebuild()
            end, "month-book-" .. tostring(span.id) .. "-" .. tostring(span.week) .. "-" .. tostring(span.first))
            -- Book ribbons receive taps before the day cell underneath them.
            table.insert(self.hits, 1, table.remove(self.hits))
        else
            for column = span.first, span.last do
                local position = span.week * 7 + column
                hidden[position] = (hidden[position] or 0) + 1
            end
        end
    end
    for position, count in pairs(hidden) do
        local x = p + (position % 7) * cell_w
        local y = top + math.floor(position / 7) * cell_h
        self:text("+" .. tostring(count), x + cell_w - self:px(23), y + self:px(6), self:px(19), self:px(16), 9,
            { single = true, gray = 95 })
    end
    local y, size = self:px(678), self:px(39)
    self:button("«", p, y, size, size, function() self:statsMoveMonth(-12) end, false, "month-previous-year")
    self:button("‹", p + self:px(48), y, size, size, function() self:statsMoveMonth(-1) end, false, "month-previous")
    self:text(os.date("%Y-%m", data.begin), p + self:px(97), y + self:px(10), width - 2 * p - self:px(194), self:px(27), 14,
        { center = true, single = true })
    self:button("›", width - p - self:px(87), y, size, size, function() self:statsMoveMonth(1) end, false, "month-next")
    self:button("»", width - p - size, y, size, size, function() self:statsMoveMonth(12) end, false, "month-next-year")
end

function Calendar:statsGoal()
    local goals, p = self.owner:getGoals(), self:px(28)
    local year = self.stats_goal_year or self.stats_year
    self.stats_goal_year = year
    local records, target = goals:list(year), goals:target(year)
    local width = self.width - 2 * p
    self:button("‹", p, self:px(138), self:px(50), self:px(35), function() self:statsNext(-1) end, false, "goal-previous-year")
    self:text(tostring(year) .. " reading goal", p + self:px(58), self:px(141), width - self:px(116), self:px(39), 25,
        { center = true, single = true, serif = true })
    self:button("›", self.width - p - self:px(50), self:px(138), self:px(50), self:px(35), function() self:statsNext(1) end, false, "goal-next-year")
    self:text(target > 0 and string.format("%d / %d", #records, target) or tostring(#records), p, self:px(198), width, self:px(80), 58,
        { center = true, single = true })
    self:text("Books finished", p, self:px(280), width, self:px(30), 15, { center = true, single = true, gray = 95 })
    self:rect(p, self:px(330), width, self:px(5), 227)
    if target > 0 then self:rect(p, self:px(330), math.floor(width * math.min(1, #records / target)), self:px(5), 35) end
    self:text(target > 0 and string.format("%d%% of your goal", math.floor(#records * 100 / target)) or "Goal is off", p,
        self:px(351), width, self:px(24), 13, { center = true, single = true, gray = 90 })
    self:button("Set yearly goal", p, self:px(395), width, self:px(42), function() self.owner:setYearGoal(year) end, false, "set-year-goal")
    local first = (self.stats_list_page - 1) * 4 + 1
    for slot = 0, 3 do
        local record = records[first + slot]
        if record then
            local y = self:px(460 + slot * 50)
            self:text(record.title, p, y, width - self:px(80), self:px(28), 16, { single = true, serif = true })
            self:text(os.date("%d %b", Stats.date(record.date)), self.width - p - self:px(77), y + self:px(4), self:px(73), self:px(25), 12,
                { single = true, gray = 95 })
            if record.book_id then self:hit(p, y, width - self:px(46), self:px(40), function()
                self:statsNavigate("book"); self.stats_book_id = record.book_id; self:rebuild()
            end, "goal-book-" .. tostring(record.book_id)) end
            self:text("×", self.width - p - self:px(31), y + self:px(22), self:px(30), self:px(28), 18,
                { center = true, single = true, gray = 115 })
            self:hit(self.width - p - self:px(39), y + self:px(22), self:px(39), self:px(28), function()
                self.owner:removeFinish(record.key, year)
            end, "remove-finish-" .. record.key)
        end
    end
    if #records == 0 then self:text("Mark books as Finished in KOReader, or use\nRecord finish in a book's statistics.", p,
        self:px(485), width, self:px(80), 17, { center = true, gray = 95 }) end
    if #records > 4 then
        self:button("‹", p, self:px(687), self:px(49), self:px(30), function()
            self.stats_list_page = math.max(1, self.stats_list_page - 1); self:rebuild()
        end, false, "goal-page-previous")
        self:text(string.format("%d / %d", self.stats_list_page, math.ceil(#records / 4)), p, self:px(693), width, self:px(23), 12,
            { center = true, single = true })
        self:button("›", self.width - p - self:px(49), self:px(687), self:px(49), self:px(30), function()
            self.stats_list_page = math.min(math.ceil(#records / 4), self.stats_list_page + 1); self:rebuild()
        end, false, "goal-page-next")
    end
end

return Calendar
