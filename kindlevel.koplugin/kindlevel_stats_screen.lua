local Blitbuffer = require("ffi/blitbuffer")
local Stats = require("kindlevel_stats")
local UIManager = require("ui/uimanager")
local View = {}

function View:statsCards(values, top)
    local p,width=self:px(28),self.width-self:px(56)
    local cell=width/2
    for i,value in ipairs(values) do
        local x=p+((i-1)%2)*cell;local y=top+math.floor((i-1)/2)*self:px(94)
        self:text(value[1],x,y,cell-self:px(16),self:px(51),34,{single=true,mono=true})
        self:text(value[2],x,y+self:px(53),cell-self:px(16),self:px(29),16,{single=true,gray=85})
    end
end

function View:statsControls()
    local p,width=self:px(28),self.width-self:px(56)
    local labels={{"7","Week"},{"14","14 days"},{"30","30 days"},{"year","Year"},{"all","All"}}
    local cell=width/#labels
    for i,item in ipairs(labels) do
        local x=p+(i-1)*cell;local active=self.stats_period==item[1]
        if active then self:rect(x,self:px(151),cell-self:px(6),self:px(50),34) end
        self:text(item[2],x,self:px(165),cell-self:px(6),self:px(27),16,{single=true,center=true,gray=active and 255 or 85})
        self:hit(x,self:px(151),cell-self:px(6),self:px(50),function() self.stats_period=item[1];self.stats_view="overview";self.stats_history={};self:rebuild() end,"period-"..item[1])
    end
end

function View:statsChart(series,x,y,width,height,forced_metric)
    local metric=forced_metric or self.stats_metric
    local buckets=series
    if #series>60 then
        buckets={};local size=math.ceil(#series/30)
        for i=1,#series,size do
            local v={date=series[i].date,timestamp=series[i].timestamp,pages=0,seconds=0,future=series[i].future}
            for j=i,math.min(i+size-1,#series) do if not series[j].future then v.pages=v.pages+series[j].pages;v.seconds=v.seconds+series[j].seconds end end
            buckets[#buckets+1]=v
        end
    end
    local maximum=metric=="seconds" and 60 or 30
    for _,item in ipairs(buckets) do if not item.future then maximum=math.max(maximum,metric=="pages" and item.pages or item.seconds/60) end end
    local unit=metric=="seconds" and 60 or 30;maximum=math.ceil(maximum/unit)*unit
    for i=0,3 do
        local ly=y+height-math.floor(height*i/3)
        self:rect(x,ly,width,math.max(1,self:px(.6)),195)
        self:text(tostring(math.floor(maximum*i/3))..(metric=="seconds" and "m" or ""),self:px(28),ly-self:px(10),x-self:px(36),self:px(24),14,{single=true,mono=true,gray=85})
    end
    local step=width/math.max(1,#buckets)
    for i,item in ipairs(buckets) do
        local value=item.future and 0 or metric=="pages" and item.pages or item.seconds/60
        local left=x+(i-1)*step;local bw=math.max(1,math.floor(step*.54));local bx=left+math.floor(step*.1)
        local bh=math.floor(height*value/maximum)
        local current=item.date==os.date("%Y-%m-%d",self.owner:getStats().now)
        if bh>0 then self:rect(bx,y+height-bh,bw,bh,current and 34 or 222) end
        if #buckets<=7 then
            if not item.future then self:text(tostring(math.floor(value+.5)),bx,y+height-bh-self:px(29),step,self:px(24),14,{single=true,mono=true,gray=current and 34 or 85}) end
            self:text(os.date("%a",item.timestamp):sub(1,1)..os.date("%d",item.timestamp),bx,y+height+self:px(14),step,self:px(27),14,{single=true,mono=true,gray=current and 34 or 85})
        end
        if #series<=30 and not item.future then self:hit(left,y,step,height+self:px(44),function() self:statsOpenDay(item.date) end,"chart-day-"..item.date) end
    end
    if #buckets>7 then
        self:text(os.date("%d %b",buckets[1].timestamp),x,y+height+self:px(12),width/2,self:px(25),14,{single=true,mono=true,gray=85})
        self:text(os.date("%d %b",buckets[#buckets].timestamp),x+width/2,y+height+self:px(12),width/2,self:px(25),14,{single=true,mono=true,gray=85})
    end
end

function View:statsOverview()
    local stats,p=self.owner:getStats():load(),self:px(28)
    local width=self.width-2*p
    self:pageTitle("Your reading, at a glance.")
    self:statsControls()
    local series,totals=stats:series(self.stats_period,self.stats_year)
    self:statsCards({{Stats.duration(totals.seconds),"reading time"},{Stats.number(totals.pages),"pages read"}},self:px(225))
    self:text(string.format("Avg %.1f pages/day · Best %d · %dd streak",totals.average,totals.record,stats:streak()),p,self:px(314),width,self:px(25),14,{single=true,mono=true,gray=85})
    if self.stats_period=="year" then self:statsCalendar(series);return end
    self:divider(self:px(347))
    if stats.error or totals.seconds==0 then
        self:text(stats.error and "Reading history is unavailable." or "Every story starts somewhere.",p,self:px(360),width,self:px(70),25,{bold=true})
        self:text(stats.error=="missing" and "Enable KOReader's Reading Statistics plugin to collect reading time."
            or stats.error and "Refresh statistics to try again. Your reading history stays in KOReader."
            or "No reading was recorded in this period. Try another period or read a few pages.",p,self:px(445),width,self:px(100),18,{gray=85})
        if self.owner.statisticsTools then self:button("Reading Statistics tools",p,self:px(578),width,self:px(50),function() self.owner:statisticsTools() end,false,"statistics-tools") end
        self:statsMonthLink();return
    end
    self:row("Reading history",string.format("%d active days · %d books",totals.active_days,#stats.books),365,function() self:statsNavigate("books");self.stats_list_page=1;self:rebuild() end,"stats-books")
    self:statsMetricToggle(self:px(455))
    self:statsChart(series,self:px(80),self:px(530),self.width-self:px(108),self:px(90))
    self:statsMonthLink()
end

function View:statsCalendar(series)
    local p,width=self:px(28),self.width-self:px(56)
    self:button("‹",p,self:px(341),self:px(50),self:px(48),function() self:statsNext(-1) end,false,"previous-year")
    self:text(tostring(self.stats_year),p+self:px(70),self:px(352),width-self:px(140),self:px(30),20,{single=true,mono=true,center=true})
    self:button("›",self.width-p-self:px(50),self:px(341),self:px(50),self:px(48),function() self:statsNext(1) end,false,"next-year")
    local january=series[1] and series[1].timestamp
    local offset=january and (tonumber(os.date("%w",january))+6)%7 or 0
    local step=width/53;local size=math.max(1,math.floor(step-self:px(2)))
    for index,day in ipairs(series) do
        local position=index-1+offset;local column,row=math.floor(position/7),position%7
        local x,y=p+column*step,self:px(432)+row*step
        if day.date:sub(-2)=="01" then self:text(os.date("%b",day.timestamp),x,self:px(403),self:px(37),self:px(24),12,{single=true,mono=true,gray=85}) end
        self:rect(x,y,size,size,day.future and 249 or day.seconds==0 and 238 or day.seconds<1800 and 190 or 34)
        if not day.future then self:hit(x,y,size,size,function() self:statsOpenDay(day.date) end,"calendar-"..day.date) end
    end
    self:text("Less  ▫ ▪ ■  More · Future days are blank",p,self:px(525),width,self:px(28),14,{single=true,mono=true,gray=85})
    local goals=self.owner.getGoals and self.owner:getGoals()
    if goals then
        local count,target=#goals:list(self.stats_year),goals:target(self.stats_year)
        self:text(string.format("%d / %d books finished",count,target),p,self:px(574),width,self:px(35),22,{single=true})
        self:progress(p,self:px(618),width,target>0 and count/target or 0)
        self:hit(p,self:px(565),width,self:px(70),function() self:statsNavigate("goal");self.stats_goal_year=self.stats_year;self.stats_list_page=1;self:rebuild() end,"year-goal")
    end
    self:statsMonthLink()
end

function View:statsMonthLink()
    local p,width=self:px(28),self.width-self:px(56)
    local y=self.height-self:px(131);local half=(width-self:px(16))/2
    self:button("Book calendar",p,y,half,self:px(48),function() self:statsNavigate("month");self:rebuild() end,false,"book-calendar")
    self:button("Returns",p+half+self:px(16),y,half,self:px(48),function() self:statsNavigate("recovery");self.stats_list_page=1;self:rebuild() end,false,"return-statistics")
end

function View:statsMetricToggle(y)
    local p,width=self:px(28),self.width
    self:text("Reading activity",p,y+self:px(10),width/2,self:px(30),18,{single=true})
    for i,item in ipairs{{"pages","Pages"},{"seconds","Time"}} do
        local x=width-self:px(205)+(i-1)*self:px(90);local active=self.stats_metric==item[1]
        if active then self:rect(x,y,self:px(82),self:px(46),34) end
        self:text(item[2],x,y+self:px(12),self:px(82),self:px(27),16,{single=true,center=true,gray=active and 255 or 85})
        self:hit(x,y,self:px(82),self:px(46),function() self.stats_metric=item[1];self:rebuild() end,"metric-"..item[1])
    end
end

function View:statsOpenDay(key)
    if self.tab ~= "stats" then
        self.tab, self.stats_view, self.stats_history = "stats", "overview", {}
    end
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
    self:statsCards({ { Stats.number(book.pages), "Distinct pages read" }, { Stats.duration(book.seconds), "Reading time" } }, self:px(217))
    self:text(string.format("%d highlights · %d notes",book.highlights,book.notes),p,self:px(318),self.width-2*p,self:px(28),16,{single=true,gray=85})
    self:text(string.format("%d reading days · %s per page", book.active_days,
        string.format("%.0f sec", book.average_seconds)), p, self:px(361),
        self.width - 2 * p, self:px(25), 12, { center = true, single = true, gray = 90 })
    self:statsMetricToggle(self:px(400))
    local series = stats:series("30", nil, book.id)
    self:statsChart(series, self:px(80), self:px(470), self.width - self:px(108), self:px(157))
    local period = book.first and os.date("%d %b %Y", book.first) .. " → " .. os.date("%d %b %Y", book.last) or ""
    self:text(period, p, self:px(664), self.width - 2 * p, self:px(22), 11, { center = true, single = true, gray = 100 })
    local half = (self.width - 2 * p) / 2
    self:button("Book journey",p,self:px(694),half-self:px(8),self:px(48),function()
        self:statsNavigate("journey");self.stats_list_page=1;self:rebuild()
    end,false,"book-journey")
    if self.owner.recordFinish then
        self:button("Record finish",p+half+self:px(8),self:px(694),half-self:px(8),self:px(48),function() self.owner:recordFinish(book) end,false,"record-finish")
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
