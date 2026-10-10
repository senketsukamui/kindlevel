local Blitbuffer = require("ffi/blitbuffer")
local Stats = require("kindlevel_stats")
local Journey = require("kindlevel_journey")
local View = {}

local function date(key)
    return os.date("%d %b %Y", Stats.date(key))
end

function View:journeyThreshold()
    return Journey.threshold(self.owner.settings:readSetting("return_break_days"))
end

function View:journeyControls(y)
    local p, width, threshold = self:px(28), self.width - self:px(56), self:journeyThreshold()
    self:text("Break length", p, self:px(y + 8), width / 2, self:px(23), 12, { single = true, gray = 90 })
    for i, days in ipairs{ 3, 7, 14 } do
        local x = p + width / 2 + (i - 1) * width / 6
        self:text(days .. " days", x, self:px(y + 8), width / 6, self:px(23), 12, { center = true, single = true })
        if threshold == days then self:rect(x + self:px(8), self:px(y + 34), width / 6 - self:px(16), self:px(2), 0) end
        self:hit(x, self:px(y), width / 6, self:px(43), function()
            self.owner.settings:saveSetting("return_break_days", days); self.owner.settings:flush()
            self.stats_list_page = 1; self:rebuild()
        end, "break-" .. days)
    end
end

function View:journeyPages(count, y)
    local pages, p = math.max(1, math.ceil(count / 3)), self:px(28)
    self.stats_list_page = math.max(1, math.min(self.stats_list_page, pages))
    if pages <= 1 then return end
    self:button("‹", p, self:px(y), self:px(49), self:px(30), function() self:statsNext(-1) end, false, "journey-previous")
    self:text(string.format("%d / %d", self.stats_list_page, pages), p + self:px(55), self:px(y + 5),
        self.width - self:px(166), self:px(23), 12, { center = true, single = true })
    self:button("›", self.width - p - self:px(49), self:px(y), self:px(49), self:px(30),
        function() self:statsNext(1) end, false, "journey-next")
end

function View:journeyGraph(summary, y, height)
    local x, width = self:px(50), self.width - self:px(83)
    local top, h = self:px(y), self:px(height)
    self:rect(x, top + h, width, self:px(1), 180)
    if not summary.first then return end
    local begin = Journey.ordinal(summary.first)
    local span = math.max(1, summary.elapsed_days - 1)
    local function position(key) return x + math.floor((Journey.ordinal(key) - begin) * width / span) end
    for _, item in ipairs(summary.returns) do
        local left, right = position(item.previous), position(item.date)
        self:rect(left, top, math.max(1, right - left), h, 242)
    end
    for _, mark in ipairs{ 0, 50, 100 } do
        self:text(tostring(mark) .. "%", self:px(4), top + h * (1 - mark / 100) - self:px(7), self:px(43), self:px(18), 9,
            { center = true, single = true, gray = 100 })
    end
    local previous
    for _, day in ipairs(summary.days) do
        if day.position then
            local point = { x = position(day.date), y = top + math.floor(h * (1 - day.position)), date = day.date }
            if previous and Journey.ordinal(day.date) - Journey.ordinal(previous.date) - 1 < self:journeyThreshold() then
                local a = previous
                self.draw[#self.draw + 1] = { kind = "custom", paint = function(bb, ox, oy)
                    local steps = math.max(math.abs(point.x - a.x), math.abs(point.y - a.y), 1)
                    for step = 0, steps do
                        local dx = math.floor(a.x + (point.x - a.x) * step / steps)
                        local dy = math.floor(a.y + (point.y - a.y) * step / steps)
                        bb:paintRect(ox + dx, oy + dy, self:px(1), self:px(1), Blitbuffer.Color8(55))
                    end
                end }
            end
            self:rect(point.x - self:px(2), point.y - self:px(2), self:px(4), self:px(4), 0)
            previous = point
        end
    end
    self:text(date(summary.first), x, top + h + self:px(8), width / 2, self:px(19), 9, { single = true, gray = 90 })
    self:text(date(summary.last), x + width / 2, top + h + self:px(8), width / 2, self:px(19), 9,
        { single = true, center = true, gray = 90 })
end

function View:statsJourney()
    local stats, p = self.owner:getStats():load(), self:px(28)
    local width, book = self.width - 2 * p, stats:book(self.stats_book_id)
    self:text("Book journey", p, self:px(140), width, self:px(39), 27, { serif = true, single = true })
    self:text(book and book.title or "Book unavailable", p, self:px(186), width, self:px(28), 16, { serif = true, single = true })
    self:journeyControls(224)
    local summary = Journey:new(stats):book(self.stats_book_id, self:journeyThreshold(), self.owner.getGoals and self.owner:getGoals())
    self:statsCards({ { tostring(summary.active_days), "Reading days" }, { tostring(summary.elapsed_days or 0), "Days · first to latest entry" } }, self:px(282))
    if not summary.first then
        self:text(summary.error and "Reading history is unavailable. Try Refresh statistics."
            or "No recorded reading for this book yet.", p, self:px(424), width, self:px(60), 18, { center = true, gray = 90 })
        return
    end
    self:text(string.format("%d returns · longest gap %dd · last read %dd ago", #summary.returns, summary.longest_break,
        summary.idle_days), p, self:px(366), width, self:px(22), 11,
        { center = true, single = true, gray = 85 })
    local has_positions = false
    for _, day in ipairs(summary.days) do if day.position then has_positions = true; break end end
    self:journeyGraph(summary, 410, 105)
    self:text(has_positions and "Furthest recorded position each day · shaded gaps are breaks"
        or "Position history is unavailable in this older database", p, self:px(545), width, self:px(20), 9,
        { center = true, single = true, gray = 90 })
    local count = #summary.episodes
    self:journeyPages(count, 696)
    for slot = 0, 2 do
        local index = count - (self.stats_list_page - 1) * 3 - slot
        local episode = summary.episodes[index]
        if episode then
            local y = self:px(577 + slot * 36)
            local label = index == 1 and "First recorded" or "Returned after " .. summary.returns[index - 1].gap .. " days"
            self:text(label, p, y, width * 0.47, self:px(21), 12, { single = true })
            self:text(string.format("%s – %s · %dd", date(episode.first),
                date(episode.last), episode.active_days), p + width * 0.47, y, width * 0.53,
                self:px(21), 11, { single = true, gray = 90 })
            self:hit(p, y - self:px(2), width, self:px(32), function() self:statsOpenDay(episode.first) end, "journey-episode-" .. index)
        end
    end
    self:text(#summary.finishes > 0 and "Confirmed finish: " .. summary.finishes[#summary.finishes]
        .. (#summary.finishes > 1 and string.format(" · +%d earlier", #summary.finishes - 1) or "")
        or "No confirmed finish recorded", p, self:px(679), width, self:px(18), 10, { single = true, gray = 90 })
end

function View:statsRecovery()
    local stats, p = self.owner:getStats():load(), self:px(28)
    local width = self.width - 2 * p
    self:text("Every return counts", p, self:px(140), width, self:px(42), 27, { serif = true, single = true })
    self:journeyControls(196)
    local mode = self.stats_recovery_mode or "reading"
    for i, item in ipairs{ { "reading", "Returning to reading" }, { "books", "Returning to books" } } do
        local x = p + (i - 1) * width / 2
        self:text(item[2], x, self:px(252), width / 2, self:px(23), 13, { center = true, single = true })
        if mode == item[1] then self:rect(x + self:px(16), self:px(280), width / 2 - self:px(32), self:px(2), 0) end
        self:hit(x, self:px(244), width / 2, self:px(42), function()
            self.stats_recovery_mode, self.stats_list_page = item[1], 1; self:rebuild()
        end, "recovery-" .. item[1])
    end
    local summary = Journey:new(stats):recovery(self:journeyThreshold(), mode)
    self:statsCards({ { tostring(#summary.returns), "Returns · all recorded history" },
        { tostring(summary.recent_returns), "Returns · last 30 days" },
        { summary.typical_break and string.format("%g days", summary.typical_break) or "—", "Typical completed break · median" },
        { summary.idle_days and tostring(summary.idle_days) .. (summary.idle_days == 1 and " day" or " days") or "—",
            "Since last reading · any book" } }, self:px(300))
    self:text(mode == "books" and "A book return follows a gap in that book, even if you read others."
        or "A reading return follows a gap with no reading in any book.", p, self:px(478), width, self:px(33), 11,
        { center = true, gray = 90 })
    self:journeyPages(#summary.returns, 687)
    for slot = 0, 2 do
        local index = (self.stats_list_page - 1) * 3 + slot + 1
        local item = summary.returns[index]
        if item then
            local y = self:px(535 + slot * 46)
            self:text(item.title or "Back to reading", p, y, width * 0.64, self:px(23), 15, { serif = true, single = true })
            self:text(item.gap .. " days away", p + width * 0.64, y + self:px(2), width * 0.36, self:px(21), 12,
                { single = true, center = true })
            self:text(date(item.date), p, y + self:px(23), width, self:px(19), 10, { single = true, gray = 90 })
            self:hit(p, y, width, self:px(43), function()
                if item.book_id then self:statsNavigate("journey"); self.stats_book_id = item.book_id; self.stats_list_page = 1; self:rebuild()
                else self:statsOpenDay(item.date) end
            end, "recovery-return-" .. index)
        end
    end
    if #summary.returns == 0 then
        self:text(summary.error and "Reading history is unavailable. Try Refresh statistics."
            or "No returns after this length of break recorded yet.\nAn ongoing break counts once you return.", p,
            self:px(548), width, self:px(80), 16, { center = true, gray = 90 })
    end
    self:text("Breaks count full local days without recorded activity.", p, self:px(674), width, self:px(19), 9,
        { center = true, single = true, gray = 95 })
end

return View
