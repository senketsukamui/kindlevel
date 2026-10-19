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
    local stats=self.owner:getStats();local data=stats:monthData(self.stats_month)
    local p,width=self:px(28),self.width-self:px(56)
    self:text(os.date("%B %Y",data.begin),p,self:px(85),width-self:px(180),self:px(50),30,{single=true,bold=true})
    self:button("Today",self.width-p-self:px(160),self:px(84),self:px(160),self:px(49),function() self.stats_month=Stats.month(stats.now);self:rebuild() end,false,"month-today")
    local top,bottom=self:px(184),self.height-self:px(215)
    local initial=Calendar.monthLayout(data,3);local cell_h=math.floor((bottom-top)/initial.weeks)
    local bar_h=self:px(20);local lanes=math.max(1,math.min(3,math.floor((cell_h-self:px(34))/(bar_h+self:px(2)))))
    local layout=Calendar.monthLayout(data,lanes);local cell_w=width/7
    for i,name in ipairs{"Mon","Tue","Wed","Thu","Fri","Sat","Sun"} do self:text(name,p+(i-1)*cell_w+self:px(8),self:px(151),cell_w,self:px(28),14,{single=true,mono=true,gray=85}) end
    local maximum=1;for _,day in pairs(data.days) do for _,s in pairs(day.hours) do maximum=math.max(maximum,s) end end
    local hidden={}
    for row=0,layout.weeks-1 do self:rect(p,top+row*cell_h,width,math.max(1,self:px(.6)),180) end
    for number=1,layout.count do
        local position=layout.offset+number-1;local column,row=position%7,math.floor(position/7)
        local x,y=p+column*cell_w,top+row*cell_h
        local stamp=Stats.day(data.begin,number-1);local key=os.date("%Y-%m-%d",stamp);local day=data.days[key] or {hours={}}
        local future=stamp>Stats.day(stats.now)
        if stamp==Stats.day(stats.now) then self:outline(x+self:px(2),y+self:px(2),cell_w-self:px(4),cell_h-self:px(4),100) end
        self:text(tostring(number),x+self:px(7),y+self:px(5),cell_w-self:px(14),self:px(26),17,{single=true,gray=future and 115 or 34})
        if not future then self:hit(x,y,cell_w,cell_h,function() self:statsOpenDay(key) end,"month-day-"..key) end
        local hw=cell_w-self:px(14)
        for hour=1,24 do local seconds=day.hours[hour] or 0
            if seconds>0 then local hx=x+self:px(7)+math.floor((hour-1)*hw/24);local next_x=x+self:px(7)+math.floor(hour*hw/24)
                local bh=math.max(1,math.floor(self:px(8)*seconds/maximum));self:rect(hx,y+cell_h-self:px(5)-bh,math.max(1,next_x-hx),bh,34)
            end
        end
    end
    for _,span in ipairs(layout.ribbons) do
        if span.lane then
            local x=p+span.first*cell_w+self:px(4);local y=top+span.week*cell_h+self:px(27)+(span.lane-1)*(bar_h+self:px(2))
            local w=(span.last-span.first+1)*cell_w-self:px(8);local gray=({34,70,100})[(span.id-1)%3+1]
            self:rect(x,y,w,bar_h,gray);self:text(span.title,x+self:px(6),y+self:px(1),w-self:px(12),bar_h,14,{single=true,mono=true,gray=255})
            self:hit(x,y,w,bar_h,function() self:statsNavigate("book");self.stats_book_id=span.id;self:rebuild() end,"month-book-"..span.id.."-"..span.week.."-"..span.first)
            table.insert(self.hits,1,table.remove(self.hits))
        else for col=span.first,span.last do local pos=span.week*7+col;hidden[pos]=(hidden[pos] or 0)+1 end end
    end
    for pos,count in pairs(hidden) do self:text("+"..count,p+(pos%7)*cell_w+cell_w-self:px(27),top+math.floor(pos/7)*cell_h+self:px(6),self:px(24),self:px(20),12,{single=true,gray=85,tiny=true}) end
    self:text("Tap a day for its reading journal.",p,self.height-self:px(190),width,self:px(30),18,{single=true,gray=85})
    local y=self.height-self:px(163);local size=self:px(48)
    self:button("«",p,y,size,size,function() self:statsMoveMonth(-12) end,false,"month-previous-year")
    self:button("‹",p+self:px(60),y,size,size,function() self:statsMoveMonth(-1) end,false,"month-previous")
    self:text(os.date("%Y-%m",data.begin),p+self:px(130),y+self:px(13),width-self:px(260),self:px(28),16,{single=true,mono=true,gray=85})
    self:button("›",self.width-p-self:px(108),y,size,size,function() self:statsMoveMonth(1) end,false,"month-next")
    self:button("»",self.width-p-size,y,size,size,function() self:statsMoveMonth(12) end,false,"month-next-year")
end

function Calendar:statsGoal()
    local goals,p=self.owner:getGoals(),self:px(28)
    local year=self.stats_goal_year or self.stats_year;self.stats_goal_year=year
    local records,target=goals:list(year),goals:target(year);local width=self.width-2*p
    self:pageTitle("Stories you finished")
    self:button("‹",p,self:px(150),self:px(50),self:px(48),function() self:statsNext(-1) end,false,"goal-previous-year")
    self:text(tostring(year),p+self:px(70),self:px(163),width-self:px(140),self:px(29),18,{single=true,mono=true,center=true})
    self:button("›",self.width-p-self:px(50),self:px(150),self:px(50),self:px(48),function() self:statsNext(1) end,false,"goal-next-year")
    self:text(target>0 and string.format("%d / %d",#records,target) or tostring(#records),p,self:px(226),width,self:px(65),42,{single=true,mono=true})
    self:text("books finished",p,self:px(296),width,self:px(28),18,{single=true,gray=85})
    self:progress(p,self:px(341),width,target>0 and #records/target or 0,self:px(8))
    self:button("Set yearly goal",p,self:px(373),width,self:px(48),function() self.owner:setYearGoal(year) end,false,"set-year-goal")
    for slot=0,3 do local record=records[(self.stats_list_page-1)*4+slot+1]
        if record then local y=self:px(446+slot*53)
            self:text(record.title,p,y,width-self:px(155),self:px(29),19,{single=true,bold=true})
            self:text(os.date("%d %b",Stats.date(record.date)),self.width-p-self:px(145),y+self:px(4),self:px(90),self:px(27),14,{single=true,mono=true,gray=85})
            if record.book_id then self:hit(p,y-self:px(4),width-self:px(52),self:px(48),function() self:statsNavigate("book");self.stats_book_id=record.book_id;self:rebuild() end,"goal-book-"..record.book_id) end
            self:icon("close",self.width-p-self:px(26),y+self:px(6),self:px(20))
            self:hit(self.width-p-self:px(44),y-self:px(4),self:px(44),self:px(48),function() self.owner:removeFinish(record.key,year) end,"remove-finish-"..record.key)
            self:divider(y+self:px(47))
        end
    end
    if #records==0 then self:text("Mark books as Finished in KOReader, or use Record finish in a book's statistics.",p,self:px(476),width,self:px(110),20,{gray=85}) end
    if #records>4 then local y=self.height-self:px(137)
        self:button("‹",p,y,self:px(50),self:px(48),function() self.stats_list_page=math.max(1,self.stats_list_page-1);self:rebuild() end,false,"goal-page-previous")
        self:text(string.format("%d / %d",self.stats_list_page,math.ceil(#records/4)),p+self:px(70),y+self:px(12),width-self:px(140),self:px(29),16,{single=true,center=true,mono=true})
        self:button("›",self.width-p-self:px(50),y,self:px(50),self:px(48),function() self.stats_list_page=math.min(math.ceil(#records/4),self.stats_list_page+1);self:rebuild() end,false,"goal-page-next")
    end
end

return Calendar
