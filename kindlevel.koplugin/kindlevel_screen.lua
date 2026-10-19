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
local Theme = require("kindlevel_theme")
local Screen = Device.screen

local Home = InputContainer:extend{
    name = "KindlevelScreen",
    covers_fullscreen = true,
    stop_events_propagation = true,
}

function Home:init()
    self.tab = self.initial_tab or "read"
    self.stats_period = "7"
    self.stats_metric = "seconds"
    self.stats_year = tonumber(os.date("%Y"))
    self.stats_month = require("kindlevel_stats").month(os.time())
    self.stats_view = "overview"
    self.stats_list_page = 1
    self.stats_history = {}
    self.index = self.library:find(self.selected_file)
    self.page = math.floor((self.index - 1) / 4) + 1
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
    size = math.max(size, options.tiny and 10 or 14)
    local face = Theme.face(self.owner.plugin_dir, size * self.scale / factor, options)
    local color = Blitbuffer.Color8(options.gray or 0)
    if options.single then
        local widget = TextWidget:new{
            text = text, face = face, fgcolor = color, bold = false,
            max_width = width, padding = 0,
        }
        local widget_width = widget:getSize().w
        if options.center then x = x + math.floor((width - widget_width) / 2) end
        return self:addWidget(widget, x, y)
    else
        return self:addWidget(TextBoxWidget:new{
            text = text, face = face, fgcolor = color, bold = false,
            width = width, height = height, alignment = options.center and "center" or "left",
            alignment_strict = true, height_overflow_show_ellipsis = true, height_adjust = options.fit_height, line_height = 0.18,
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
    h=math.max(h,self:px(48))
    self:rect(x, y, w, h, primary and 34 or 255)
    if primary then
        local cut=self:px(4)
        for _,point in ipairs{{x,y},{x+w-cut,y},{x,y+h-cut},{x+w-cut,y+h-cut}} do self:rect(point[1],point[2],cut,cut,255) end
    else self:outline(x,y,w,h,180) end
    self:text(label, x+self:px(8), y + math.floor((h - self:px(27)) / 2), w-self:px(16), self:px(30), 18,
        { center = true, single = true, gray = primary and 255 or 34 })
    self:hit(x, y, w, h, callback, id)
end

function Home:cover(book, x, y, w, h, small)
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

function Home:icon(name, x, y, size)
    self:addWidget(ImageWidget:new{file=self.owner.plugin_dir .. "/assets/ui/" .. name .. ".svg",
        width=size, height=size, alpha=true}, x, y)
end

function Home:divider(y)
    self:rect(self:px(28), y, self.width-self:px(56), math.max(1,self:px(0.6)), 180)
end

function Home:progress(x, y, width, ratio, height)
    height=height or self:px(6)
    self:rect(x,y,width,height,238)
    self:rect(x,y,math.floor(width*math.max(0,math.min(1,ratio or 0))),height,34)
end

function Home:pageTitle(title, subtitle, y)
    local p, width=self:px(28),self.width-self:px(56)
    y=y or 85
    self:text(title,p,self:px(y),width,self:px(56),30,{single=true,bold=true})
    if subtitle then self:text(subtitle,p,self:px(y+45),width,self:px(32),18,{gray=85,single=true}) end
end

function Home:row(label, caption, y, callback, id, value)
    local p,width=self:px(28),self.width-self:px(56)
    local reserve=value and self:px(140) or self:px(32)
    self:text(label,p,self:px(y),width-reserve,self:px(29),18,{single=true})
    if caption then self:text(caption,p,self:px(y+32),width-reserve,self:px(25),14,{single=true,gray=85,mono=true}) end
    if value then self:text(value,self.width-p-reserve,self:px(y+10),reserve,self:px(30),18,{single=true,center=true})
    elseif callback then self:icon("arrow-right",self.width-p-self:px(18),self:px(y+14),self:px(18)) end
    if callback then self:hit(p,self:px(y-5),width,self:px(68),callback,id) end
    self:divider(self:px(y+73))
end

function Home:header()
    local p,w=self:px(28),self.width
    local label=({read="Home",stats="Activity",library="Library",achievements="Achievements",settings="Settings"})[self.tab] or "Home"
    self:text("kindlevel",p,self:px(20),self:px(140),self:px(35),23,{single=true,bold=true})
    self:text("· "..label,p+self:px(146),self:px(25),w-self:px(320),self:px(28),16,{single=true,gray=85})
    self:icon("settings",w-p-self:px(72),self:px(26),self:px(24))
    self:hit(w-p-self:px(84),self:px(14),self:px(48),self:px(48),function()
        if self.tab ~= "settings" then self.settings_return_tab=self.tab end
        self.tab,self.settings_group="settings",nil;self:rebuild()
    end,"tab-settings")
    self:icon("close",w-p-self:px(22),self:px(28),self:px(20))
    self:hit(w-p-self:px(34),self:px(14),self:px(48),self:px(48),function() self:onClose() end,"close")
    self:divider(self:px(63))
    self:rect(self:px(16),self:px(75),self:px(12),self:px(2),34)
    self:rect(self:px(16),self:px(75),self:px(2),self:px(12),34)
end

function Home:summaryNavigate(view)
    if self.tab~="stats" then self.stats_view,self.stats_history,self.stats_list_page="overview",{},1 end
    self.tab="stats";self:statsNavigate(view)
end

function Home:readingSummary()
    local p,width=self:px(28),self.width-self:px(56)
    local stats=self.owner:getStats():load()
    local key=os.date("%Y-%m-%d",stats.now)
    local seconds=(stats.days[key] or {}).seconds or 0
    local goal=self.owner.settings:readSetting("daily_minutes",20)
    self:text(os.date("%A, %d %B",stats.now):upper(),p,self:px(88),width,self:px(25),14,{single=true,mono=true,gray=85})
    local half=width/2
    self:icon("clock",p,self:px(145),self:px(26))
    self:text(stats.error and "—" or (goal>0 and string.format("%d / %d",Stats.minutes(seconds),goal) or tostring(Stats.minutes(seconds))),p+self:px(42),self:px(124),half-self:px(45),self:px(60),36,{single=true,mono=true})
    self:text("minutes today",p+self:px(42),self:px(175),half-self:px(45),self:px(27),18,{single=true,gray=85})
    self:icon("sun",p+half+self:px(8),self:px(145),self:px(26))
    self:text(tostring(stats:streak()),p+half+self:px(54),self:px(124),half-self:px(54),self:px(60),36,{single=true,mono=true})
    self:text("day streak",p+half+self:px(54),self:px(175),half-self:px(54),self:px(27),18,{single=true,gray=85})
    self:progress(p,self:px(200),width,goal>0 and seconds/(goal*60) or 0,self:px(7))
    self:hit(p,self:px(120),half,self:px(90),function()
        self:summaryNavigate("day");self.stats_date,self.stats_list_page=key,1;self:rebuild()
    end,"today-reading")
    local year=tonumber(os.date("%Y",stats.now))
    local goals=self.owner.getGoals and self.owner:getGoals()
    local caption=goals and (goals:target(year)>0 and string.format("%d / %d books this year",#goals:list(year),goals:target(year)) or tostring(#goals:list(year)).." books this year") or "Your books this year"
    self:icon("book-open",p,self:px(228),self:px(24))
    self:text(caption,p+self:px(39),self:px(223),width-self:px(39),self:px(34),18,{single=true})
    if goals then self:hit(p,self:px(216),width,self:px(44),function()
        self:summaryNavigate("goal");self.stats_goal_year,self.stats_list_page=year,1;self:rebuild()
    end,"year-goal") end
    self:divider(self:px(263))
end

function Home:reading()
    local w,p=self.width,self:px(28)
    local book=self.library.books[self.index]
    if not book then
        self:pageTitle("A shelf waiting for stories.",nil,180)
        self:text("Choose the folder where you keep your books,\nor explore the sample library.",p,self:px(275),w-2*p,self:px(90),20,{gray=85})
        self:button("Choose books folder",p,self:px(395),w-2*p,self:px(50),function() self.owner:chooseFolder() end,true,"choose-folder")
        self:button("Try sample books",p,self:px(466),w-2*p,self:px(50),function() self.owner:useSamples() end,false,"samples")
        return
    end
    self:readingSummary()
    self.library:inspect(book)
    local tx=p+self:px(112);local tw=w-p-tx
    self:cover(book,p,self:px(290),self:px(85),self:px(110),true)
    self:text(book.title,tx,self:px(278),tw,self:px(50),23,{bold=true})
    self:text(book.author.." · "..(book.percent and string.format("%d%% read",math.floor(book.percent*100+.5)) or book.started and "Reading" or "Not started"),tx,self:px(322),tw,self:px(28),18,{single=true,gray=85})
    self:progress(tx,self:px(345),tw,book.percent or 0,self:px(6))
    self:button(book.started and "Continue reading" or "Start reading",tx,self:px(365),tw,self:px(50),function() self.owner:openBook(book) end,true,"start-reading")
    self:divider(self:px(424))
    local stats=self.owner:getStats():load()
    local first=Stats.day(stats.now,-((tonumber(os.date("%w",stats.now))+6)%7))
    local series={}
    for i=0,6 do
        local timestamp=Stats.day(first,i);local key=os.date("%Y-%m-%d",timestamp);local day=stats.days[key] or {}
        series[#series+1]={date=key,timestamp=timestamp,seconds=day.seconds or 0,pages=day.pages or 0,future=timestamp>Stats.day(stats.now)}
    end
    self:text("THIS WEEK · "..os.date("%d %b",first).."–"..os.date("%d %b",Stats.day(first,6)),p,self:px(440),w-2*p,self:px(25),14,{single=true,mono=true,gray=85})
    self:statsChart(series,self:px(80),self:px(495),w-self:px(108),self:px(128),"seconds")
    local y=self.height-self:px(137)
    self:button("‹",p,y,self:px(50),self:px(48),function() self:onPrevious() end,false,"previous-book")
    self:button("Book statistics",p+self:px(65),y,w-2*p-self:px(130),self:px(48),function()
        local match=stats:findBook(book);self.stats_book_id=match and match.id
        self.stats_book_title,self.stats_library_book=book.title,book
        self.stats_view,self.tab="book","stats";self.stats_history={};self:rebuild()
    end,false,"book-statistics")
    self:button("›",w-p-self:px(50),y,self:px(50),self:px(48),function() self:onNext() end,false,"next-book")
end

function Home:libraryItems()
    local result={};local query=require("ffi/utf8proc").lowercase(self.library_query or "")
    for index,book in ipairs(self.library.books) do
        local source=require("ffi/utf8proc").lowercase((book.title or "").." "..(book.filename or ""))
        if (query=="" or source:find(query,1,true)) and (not self.library_format or book.format==self.library_format) then
            result[#result+1]={index=index,book=book}
        end
    end
    return result
end

function Home:searchLibrary()
    local dialog
    dialog=require("ui/widget/inputdialog"):new{title="Search title or filename",input=self.library_query or "",buttons={{
        {text="Cancel",callback=function() UIManager:close(dialog) end},
        {text="Search",callback=function() self.library_query=dialog:getInputText();self.page=1;UIManager:close(dialog);self:rebuild() end},
    }}}
    UIManager:show(dialog);dialog:onShowKeyboard()
end

function Home:filterLibrary()
    local dialog;local formats={};local rows={}
    rows[1]={{text="All formats",callback=function() self.library_format=nil;self.page=1;UIManager:close(dialog);self:rebuild() end}}
    for _,book in ipairs(self.library.books) do formats[book.format]=true end
    local ordered={};for format in pairs(formats) do ordered[#ordered+1]=format end;table.sort(ordered)
    for _,format in ipairs(ordered) do local value=format;rows[#rows+1]={{text=value,callback=function() self.library_format=value;self.page=1;UIManager:close(dialog);self:rebuild() end}} end
    dialog=require("ui/widget/buttondialog"):new{title="Book format",buttons=rows};UIManager:show(dialog)
end

function Home:libraryGrid()
    local p,w=self:px(28),self.width
    self:pageTitle("Your library",self.library:folderLabel())
    local half=(w-2*p-self:px(20))/2
    self:button(self.library_query and self.library_query~="" and "Search: "..self.library_query or "Search books",p,self:px(170),half,self:px(50),function() self:searchLibrary() end,false,"search-library")
    self:button(self.library_format or "All formats",p+half+self:px(20),self:px(170),half,self:px(50),function() self:filterLibrary() end,false,"filter-library")
    local items=self:libraryItems();local pages=math.max(1,math.ceil(#items/4));self.page=math.min(self.page,pages)
    for slot=0,3 do
        local item=items[(self.page-1)*4+slot+1]
        if item then
            local book=item.book;self.library:inspect(book)
            local y=self:px(245+slot*101);local tx=p+self:px(86);local tw=w-p-tx
            self:cover(book,p,y,self:px(58),self:px(84),true)
            self:text(book.title,tx,y+self:px(4),tw,self:px(50),20,{bold=true})
            self:text(book.author.." · "..book.format,tx,y+self:px(50),tw,self:px(24),15,{single=true,gray=85})
            self:text(book.percent and string.format("%d%% read",math.floor(book.percent*100+.5)) or book.started and "Reading" or "Not started",tx,y+self:px(75),tw,self:px(23),14,{single=true,mono=true,gray=85})
            self:hit(p,y,w-2*p,self:px(98),function() self.index=item.index;self.tab="read";self:rememberSelection();self:rebuild() end,"book-"..item.index)
            self:divider(y+self:px(100))
        end
    end
    if #items==0 then self:text(#self.library.books==0 and "No books in this folder.\nChoose a books folder in Settings." or "No matching titles.\nTry another search or format.",p,self:px(350),w-2*p,self:px(120),22,{gray=85}) end
    local y=self.height-self:px(137)
    self:button("‹",p,y,self:px(50),self:px(48),function() self:onPrevious() end,false,"previous-page")
    self:text(string.format("%d / %d · %d books",self.page,pages,#items),p+self:px(70),y+self:px(13),w-2*p-self:px(140),self:px(28),15,{single=true,mono=true,gray=85})
    self:button("›",w-p-self:px(50),y,self:px(50),self:px(48),function() self:onNext() end,false,"next-page")
end

function Home:settingsPanel()
    local p,width=self:px(28),self.width-self:px(56)
    local group=self.settings_group
    if not group then
        self:pageTitle("The practical things")
        local groups={{"library","Library","Books folder, refresh and samples"},{"reading","Reading preferences","Startup and reading goals"},{"statistics","Reading statistics","Tools and refresh"},{"connection","Web dashboard","Connection and automatic sync"},{"updates","Updates & recovery","Check version, reinstall or restore"}}
        for i,item in ipairs(groups) do local value=item[1];self:row(item[2],item[3],166+(i-1)*94,function() self.settings_group=value;self:rebuild() end,"settings-"..value) end
        self:text("KINDLEVEL · "..require("kindlevel_version"),p,self:px(670),width,self:px(28),14,{mono=true,single=true,gray=85})
        return
    end
    local titles={library="Your books, your shelf",reading="Make yourself at home",statistics="Reading statistics tools",connection="Your reading, connected",updates="Updates & recovery"}
    self:pageTitle(titles[group] or "Settings")
    local actions={}
    if group=="library" then
        self:text(self.library.root,p,self:px(145),width,self:px(52),15,{gray=85})
        actions={{"Choose books folder",function() self.owner:chooseFolder() end,"choose-folder"},{"Refresh library",function() self:rescan() end,"refresh"},{"Open sample library",function() self.owner:useSamples() end,"samples"}}
    elseif group=="reading" then
        actions={{self.owner.settings:isTrue("auto_home") and "Startup home: on" or "Startup home: off",function() self.owner:toggleAutoHome() end,"auto-home"},{"Daily reading goal",function() self.owner:setDailyGoal() end,"daily-goal"},{"Yearly book goal",function() self.owner:setYearGoal() end,"yearly-goal"}}
        self:text("Show Kindlevel when KOReader's file browser opens.\nLevels and outfits are planned for a future chapter.",p,self:px(510),width,self:px(80),18,{gray=85})
    elseif group=="statistics" then
        actions={{"Open Reading Statistics",function() self.owner:statisticsTools() end,"statistics-tools"},{"Refresh Kindlevel statistics",function() self.owner:refreshStats() end,"refresh-stats"}}
        self:text("Kindlevel uses the data collected by KOReader's Reading Statistics plugin. Keep it enabled while you read.",p,self:px(460),width,self:px(100),18,{gray=85})
    elseif group=="connection" then
        local ok,state=pcall(function() return self.owner:getSync():state() end)
        state=ok and state or {}
        self:text(state.server or "Not connected yet",p,self:px(158),width,self:px(55),18,{gray=85})
        self:text(state.token and (state.last_error and "Last sync failed · retry pending" or state.last_sync and "Last synced: "..os.date("%d %b, %H:%M",state.last_sync) or "Waiting for the first sync") or "Pair with your self-hosted Kindlevel server.",p,self:px(218),width,self:px(55),16,{gray=85})
        actions={{state.token and "Sync now" or "Connect to server",function() if state.token then self.owner:syncDashboard() else self.owner:pairDashboard() end end,"sync-dashboard"},{"Connection settings",function() self.owner:dashboardConnection() end,"web-dashboard"}}
        self:text("Reading works offline. Statistics sync when KOReader is awake and Wi-Fi is already available.",p,self:px(510),width,self:px(90),18,{gray=85})
    elseif group=="updates" then
        actions={{"Check for updates",function() self.owner:checkForUpdates() end,"check-updates"}}
        self:text("Installed: "..require("kindlevel_version").."\n\nIf the main plugin cannot open, use Tools → Kindlevel recovery to reinstall or restore a local backup.",p,self:px(340),width,self:px(160),18,{gray=85})
    end
    local top=group=="connection" and 310 or 235
    for i,a in ipairs(actions) do self:button(a[1],p,self:px(top+(i-1)*74),width,self:px(50),a[2],i==1,a[3]) end
    self:button("Back to settings",p,self.height-self:px(137),width,self:px(48),function() self.settings_group=nil;self:rebuild() end,false,"settings-back")
end

function Home:navigation()
    local y=self.height-self:px(74);local cell=self.width/4
    self:rect(0,y,self.width,math.max(1,self:px(.6)),180)
    for i,item in ipairs{{"read","Read","book-open"},{"stats","Stats","chart"},{"library","Library","book-open"},{"achievements","Badges","trophy"}} do
        local x=(i-1)*cell;local active=self.tab==item[1]
        self:icon(item[3],x+(cell-self:px(24))/2,y+self:px(14),self:px(24))
        self:text(item[2],x,y+self:px(43),cell,self:px(27),16,{center=true,single=true,gray=active and 34 or 85,bold=active})
        self:hit(x,y,cell,self:px(74),function() self.tab=item[1];if self.tab=="stats" then self.stats_view="overview";self.stats_history={} end;self:rebuild() end,"tab-"..item[1])
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
    self.scale = math.min(self.width / 400, self.height / 800)
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.draw, self.hits = {}, {}
    self.ges_events.TapKindlevel = { GestureRange:new{ ges = "tap", range = self.dimen } }
    self.ges_events.SwipeKindlevel = { GestureRange:new{ ges = "swipe", range = self.dimen } }
    self:header()
    local draw_start, hit_start = #self.draw, #self.hits
    if self.tab == "stats" then self:statsPanel()
    elseif self.tab == "library" then self:libraryGrid()
    elseif self.tab == "settings" then self:settingsPanel()
    elseif self.tab == "achievements" then self:achievementPanel()
    else self:reading() end
    if self.tab=="stats" and self.stats_view~="overview" and self.stats_view~="month" and self.stats_view~="goal" then
        local shift=self:px(56)
        for i=draw_start+1,#self.draw do
            local command=self.draw[i]
            if command.kind=="custom" then local paint=command.paint;command.paint=function(bb,x,y) paint(bb,x,y-shift) end
            else command.y=command.y-shift end
        end
        for i=hit_start+1,#self.hits do self.hits[i].y=self.hits[i].y-shift end
    end
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
        self.page = math.min(math.max(1, math.ceil(#self:libraryItems() / 4)), self.page + 1)
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
    self.page = math.floor((self.index - 1) / 4) + 1
    self:rebuild()
end

function Home:onBack()
    if self.tab=="achievements" and self.achievement_detail then self.achievement_detail=nil;self:rebuild();return true end
    if self.tab == "stats" and self.stats_view ~= "overview" then
        local previous = table.remove(self.stats_history)
        if previous then
            self.stats_view, self.stats_date, self.stats_book_id, self.stats_list_page =
                previous.view, previous.date, previous.book_id, previous.page
        else self.stats_view = "overview" end
        self:rebuild()
    elseif self.tab == "settings" then
        if self.settings_group then self.settings_group=nil else self.tab=self.settings_return_tab or "read" end
        self:rebuild()
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
