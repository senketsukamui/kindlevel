local Stats = require("kindlevel_stats")
local Journey = require("kindlevel_journey")
local Sessions = require("kindlevel_sessions")
local Utf8Proc = require("ffi/utf8proc")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local Achievements = { catalog = {}, by_id = {} }
local units = { minutes = "min", pages = "pages", finished = "books", best_streak = "days",
    active_days = "days", highlights = "highlights", notes = "notes", authors = "authors", books_read = "books" }

local function positive(value) return type(value) == "number" and value > 0 and value < math.huge end
local function validate(trigger, depth)
    if type(trigger) == "function" then return true end
    if type(trigger) ~= "table" or (depth or 0) > 8 then return false end
    if trigger.type == "metric" then return units[trigger.metric] ~= nil and positive(trigger.target) end
    if trigger.type == "daily" then
        if not ({minutes=true,pages=true,books=true})[trigger.metric] or not positive(trigger.target) then return false end
        for _, day in ipairs(trigger.weekdays or {}) do if type(day) ~= "number" or day < 0 or day > 6 or day % 1 ~= 0 then return false end end
        return true
    end
    if trigger.type == "window" then
        return type(trigger.start_hour) == "number" and trigger.start_hour % 1 == 0 and trigger.start_hour >= 0 and trigger.start_hour < 24
            and type(trigger.end_hour) == "number" and trigger.end_hour % 1 == 0 and trigger.end_hour >= 0 and trigger.end_hour <= 24
            and trigger.end_hour ~= trigger.start_hour and positive(trigger.target)
    end
    if trigger.type == "return" then
        return (trigger.scope == "reading" or trigger.scope == "books") and positive(trigger.min_gap)
            and trigger.min_gap % 1 == 0 and positive(trigger.target)
    end
    if trigger.type == "session" then
        local gap=trigger.max_gap or 60
        return positive(trigger.target) and type(gap)=="number" and gap>=0 and gap<math.huge and gap%1==0
    end
    if trigger.type == "book" then
        if (trigger.action ~= "read" and trigger.action ~= "finish" and trigger.action ~= "open") or type(trigger.titles) ~= "table" or #trigger.titles == 0 then return false end
        for _, title in ipairs(trigger.titles) do if type(title) ~= "string" or Achievements.normalize(title) == "" then return false end end
        if trigger.authors then
            if type(trigger.authors) ~= "table" or #trigger.authors == 0 then return false end
            for _, author in ipairs(trigger.authors) do if type(author) ~= "string" or author == "" then return false end end
        end
        return (trigger.match == nil or trigger.match == "exact" or trigger.match == "contains")
            and (trigger.action ~= "read" or positive(trigger.target))
    end
    if trigger.type == "all" or trigger.type == "any" then
        if type(trigger.conditions) ~= "table" or #trigger.conditions == 0 then return false end
        for _, condition in ipairs(trigger.conditions) do if not validate(condition, (depth or 0) + 1) then return false end end
        return true
    end
    return false
end

function Achievements.register(item)
    local ok, valid = pcall(function()
        return type(item) == "table" and type(item.id) == "string" and item.id:match("^[a-z][a-z0-9_]*$")
            and not Achievements.by_id[item.id] and type(item.text or item.title) == "string" and (item.text or item.title) ~= ""
            and type(item.description) == "string" and item.description ~= "" and type(item.icon) == "string"
            and type(item.xp) == "number" and item.xp >= 0 and item.xp < math.huge and item.xp % 1 == 0 and validate(item.trigger)
    end)
    if not ok or not valid then logger.warn("Kindlevel: skipped invalid or duplicate achievement", type(item) == "table" and item.id or "unknown"); return false end
    item.title, item.text = item.text or item.title, item.text or item.title
    item.notification = item.notification or item.description
    Achievements.by_id[item.id] = item
    Achievements.catalog[#Achievements.catalog + 1] = item
    return true
end

function Achievements.find(id) return Achievements.by_id[id] end

function Achievements.iconPath(item, plugin_dir)
    local icon = item.icon or "achievement.svg"
    if icon:match("^[%w_/-]+%.svg$") and not icon:find("..", 1, true) and icon:sub(1,1) ~= "/" then
        local path = plugin_dir .. "/assets/" .. icon
        if lfs.attributes(path, "mode") == "file" then return path end
    end
    return plugin_dir .. "/assets/achievement.svg"
end

function Achievements.iconWidget(item, plugin_dir, size)
    local ImageWidget = require("ui/widget/imagewidget")
    local widget = ImageWidget:new{file=Achievements.iconPath(item,plugin_dir),width=size,height=size,alpha=true}
    local ok = pcall(widget.getSize, widget)
    if ok then return widget end
    pcall(widget.free, widget)
    return ImageWidget:new{file=plugin_dir .. "/assets/achievement.svg",width=size,height=size,alpha=true}
end

function Achievements.normalize(value)
    return Utf8Proc.lowercase(tostring(value or "")):gsub("’", "'"):gsub("‘", "'"):gsub("—", "-"):gsub("–", "-")
        :gsub("[%p%s]+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function matches(book, trigger)
    local title, author = Achievements.normalize(book.title), Achievements.normalize(book.author)
    local matched = false
    for _, alias in ipairs(trigger.titles) do
        local normalized = Achievements.normalize(alias)
        if normalized ~= "" and (trigger.match == "exact" and title == normalized
            or trigger.match ~= "exact" and title:find(normalized,1,true)) then matched = true; break end
    end
    if not matched then return false end
    if not trigger.authors then return true end
    for _, name in ipairs(trigger.authors) do if author == Achievements.normalize(name) then return true end end
    return false
end

local function rows(conn, sql, now)
    local stmt, result = conn:prepare(sql), {}
    stmt:bind(now)
    for row in stmt:rows() do result[#result+1] = row end
    stmt:close()
    return result
end

function Achievements.recordOpen(owner, book, timestamp)
    if not book or not book.title or book.title == "" then return end
    local opened=owner.settings:readSetting("achievement_opened_books",{})
    local title,author=Achievements.normalize(book.title),Achievements.normalize(book.author)
    local key=tostring(#title) .. ":" .. title .. tostring(#author) .. ":" .. author
    if not opened[key] then
        opened[key]={title=book.title,author=book.author,opened_at=timestamp or os.time()}
        owner.settings:saveSetting("achievement_opened_books",opened); owner.settings:flush()
    end
    owner.achievement_open_event=book
end

function Achievements.recordSessionBreak(owner, timestamp)
    local breaks=owner.settings:readSetting("achievement_session_breaks",{})
    timestamp=timestamp or os.time()
    if breaks[#breaks] ~= timestamp then
        breaks[#breaks+1]=timestamp
        owner.settings:saveSetting("achievement_session_breaks",breaks); owner.settings:flush()
    end
end

local function sessionGaps()
    local gaps,seen={60},{[60]=true}
    local function visit(trigger)
        if type(trigger) ~= "table" then return end
        if trigger.type == "session" then
            local gap=trigger.max_gap or 60
            if not seen[gap] then gaps[#gaps+1]=gap;seen[gap]=true end
        end
        for _,condition in ipairs(trigger.conditions or {}) do visit(condition) end
    end
    for _,item in ipairs(Achievements.catalog) do visit(item.trigger) end
    return gaps
end

function Achievements.context(owner)
    local stats = owner:getStats():load()
    local goals = owner.getGoals and owner:getGoals()
    local context = { now=stats.now, metrics={}, daily={}, hours={}, books={}, finished={}, activity_days={}, return_counts={}, opened={}, sessions={},
        open_event=owner.achievement_open_event }
    for _,book in pairs(owner.settings:readSetting("achievement_opened_books",{})) do
        if book.opened_at <= stats.now then context.opened[#context.opened+1]=book end
    end
    local result, err = stats:query(function(conn)
        local raw = conn:rowexec("SELECT name FROM sqlite_master WHERE type='table' AND name='page_stat_data';")
        local sessions=Sessions:new(sessionGaps(),owner.settings:readSetting("achievement_session_breaks",{}),stats.now)
        local stmt=conn:prepare(string.format([[
            SELECT id_book,start_time,duration FROM %s
            WHERE duration > 0 AND start_time <= ? ORDER BY start_time,id_book;
        ]],raw and "page_stat_data" or "page_stat"))
        stmt:bind(stats.now)
        for row in stmt:rows() do sessions:add(tonumber(row[1]),tonumber(row[2]),tonumber(row[3])) end
        stmt:close()
        return {
            sessions=sessions.best,
            daily = rows(conn, [[
                SELECT day, count(*), sum(seconds) FROM (
                    SELECT strftime('%Y-%m-%d',start_time,'unixepoch','localtime') AS day,
                           id_book,page,sum(duration) AS seconds FROM page_stat
                    WHERE duration > 0 AND start_time <= ? GROUP BY day,id_book,page
                ) GROUP BY day ORDER BY day;
            ]], stats.now),
            hours = rows(conn, string.format([[
                SELECT id_book,strftime('%%Y-%%m-%%d',start_time,'unixepoch','localtime'),
                       strftime('%%H',start_time,'unixepoch','localtime'),sum(duration)
                FROM %s WHERE duration > 0 AND start_time <= ? GROUP BY id_book,2,3 ORDER BY 2,3;
            ]], raw and "page_stat_data" or "page_stat"), stats.now),
        }
    end)
    context.error = err
    context.sessions=result and result.sessions or {}
    local metric = {minutes=0,pages=0,finished=0,best_streak=0,active_days=0,highlights=0,notes=0,authors=0,books_read=0}
    local by_book, activity = {}, {}
    for _, row in ipairs(result and result.daily or {}) do
        local date, pages, seconds = row[1], tonumber(row[2]) or 0, tonumber(row[3]) or 0
        context.daily[date] = {date=date,pages=pages,seconds=seconds,books=0}
        metric.pages = metric.pages + pages
    end
    for _, row in ipairs(result and result.hours or {}) do
        local id,date,hour,seconds = tonumber(row[1]),row[2],tonumber(row[3]),tonumber(row[4]) or 0
        context.hours[#context.hours+1] = {book_id=id,date=date,hour=hour,seconds=seconds}
        by_book[id] = by_book[id] or {seconds=0,days={}}
        by_book[id].seconds = by_book[id].seconds + seconds
        by_book[id].days[date] = (by_book[id].days[date] or 0) + seconds
        activity[date] = (activity[date] or 0) + seconds
    end
    local previous, streak, authors, total_seconds = nil,0,{},0
    local dates = {}; for date in pairs(activity) do dates[#dates+1]=date end; table.sort(dates)
    for _, date in ipairs(dates) do
        context.activity_days[#context.activity_days+1] = {date=date,seconds=activity[date]}
        context.daily[date] = context.daily[date] or {date=date,pages=0,books=0}
        context.daily[date].seconds = activity[date]
        total_seconds,metric.active_days = total_seconds + activity[date],metric.active_days+1
        local ordinal = Journey.ordinal(date)
        streak = previous and ordinal == previous+1 and streak+1 or 1
        metric.best_streak,previous = math.max(metric.best_streak,streak),ordinal
    end
    metric.minutes = total_seconds / 60
    for _, book in ipairs(stats.books) do
        local data = by_book[book.id]
        if data then
            local item = {id=book.id,title=book.title,author=book.author,seconds=data.seconds,days={}}
            for date, seconds in pairs(data.days) do
                item.days[#item.days+1] = {date=date,seconds=seconds}
                context.daily[date].books = context.daily[date].books+1
            end
            table.sort(item.days,function(a,b) return a.date<b.date end)
            context.books[#context.books+1] = item
            metric.highlights,metric.notes = metric.highlights + book.highlights,metric.notes + book.notes
            if data.seconds >= 900 then
                metric.books_read = metric.books_read+1
                local author = Achievements.normalize(book.author)
                if author ~= "" and author ~= "n a" then authors[author]=true end
            end
        end
    end
    for _ in pairs(authors) do metric.authors=metric.authors+1 end
    for _, record in pairs(owner.settings:readSetting("finished_books") or {}) do
        for _, date in pairs(record.dates or {}) do
            if goals and goals:validDate(date) then
                metric.finished=metric.finished+1
                context.finished[#context.finished+1] = {title=record.title,author=record.author,date=date}
                break
            end
        end
    end
    context.metrics=metric
    return context
end

function Achievements.metrics(owner) return Achievements.context(owner).metrics end

local function progress(value,target,unit,label)
    value,target = math.max(0,tonumber(value) or 0),tonumber(target) or 1
    assert(positive(target) and value < math.huge,"invalid achievement progress")
    return {value=value,target=target,ratio=math.min(1,value/target),ready=value>=target,
        label=label or string.format("%s / %s %s",Stats.number(math.floor(math.min(value,target))),Stats.number(target),unit or "")}
end

local evaluate
evaluate = function(trigger, context)
    if type(trigger)=="function" then
        local result=trigger(context)
        if type(result)=="boolean" then return progress(result and 1 or 0,1,nil,result and "Complete" or "Not yet") end
        assert(type(result)=="table","custom trigger must return boolean or progress table")
        return progress(result.value,result.target,result.unit,result.label)
    end
    local kind,value,unit=trigger.type,0,""
    if kind=="metric" then value,unit=context.metrics[trigger.metric] or 0,units[trigger.metric]
    elseif kind=="daily" then
        unit=trigger.metric=="minutes" and "min in a day" or trigger.metric .. " in a day"
        for _,day in pairs(context.daily) do
            local allowed=not trigger.weekdays or #trigger.weekdays==0
            local weekday=tonumber(os.date("%w",Stats.date(day.date)))
            for _,candidate in ipairs(trigger.weekdays or {}) do if candidate==weekday then allowed=true end end
            if allowed then value=math.max(value,trigger.metric=="minutes" and day.seconds/60 or day[trigger.metric] or 0) end
        end
    elseif kind=="window" then
        unit="min in this time window"
        local days={}
        for _,hour in ipairs(context.hours) do
            local inside=trigger.start_hour<trigger.end_hour and hour.hour>=trigger.start_hour and hour.hour<trigger.end_hour
                or trigger.start_hour>trigger.end_hour and (hour.hour>=trigger.start_hour or hour.hour<trigger.end_hour)
            if inside then days[hour.date]=(days[hour.date] or 0)+hour.seconds end
        end
        for _,seconds in pairs(days) do value=trigger.per_day and math.max(value,seconds) or value+seconds end
        value=value/60
    elseif kind=="return" then
        unit="returns"
        local key=trigger.scope .. ":" .. trigger.min_gap
        if context.return_counts[key]==nil then
            local function count(days)
                local total,previous=0,nil
                for _,day in ipairs(days) do
                    local ordinal=Journey.ordinal(day.date)
                    if previous and ordinal-previous-1>=trigger.min_gap then total=total+1 end
                    previous=ordinal
                end
                return total
            end
            local total=0
            if trigger.scope=="reading" then total=count(context.activity_days)
            else for _,book in ipairs(context.books) do total=total+count(book.days) end end
            context.return_counts[key]=total
        end
        value=context.return_counts[key]
    elseif kind=="book" then
        if trigger.action=="open" then
            for _,book in ipairs(context.opened or {}) do if matches(book,trigger) then value=1; break end end
            return progress(value,1,nil,value==1 and "Book opened" or "Open this book")
        end
        if trigger.action=="finish" then
            for _,book in ipairs(context.finished) do if matches(book,trigger) then value=1; break end end
            return progress(value,1,nil,value==1 and "Finish recorded" or "Finish this book")
        end
        unit="min in this book"
        for _,book in ipairs(context.books) do if matches(book,trigger) then value=value+book.seconds end end
        value=value/60
    elseif kind=="session" then
        value=((context.sessions or {})[trigger.max_gap or 60] or {}).seconds or 0
        value=value/60
        unit="min in one session"
    elseif kind=="all" or kind=="any" then
        local ratio,complete=kind=="all" and 1 or 0,0
        for _,condition in ipairs(trigger.conditions) do
            local result=evaluate(condition,context)
            ratio=kind=="all" and math.min(ratio,result.ratio) or math.max(ratio,result.ratio)
            if result.ready then complete=complete+1 end
        end
        return {value=complete,target=#trigger.conditions,ratio=ratio,ready=kind=="all" and complete==#trigger.conditions or kind=="any" and complete>0,
            label=string.format("%d / %d conditions",complete,#trigger.conditions)}
    else error("unknown achievement trigger") end
    return progress(value,trigger.target,unit)
end

function Achievements.progress(item, context)
    if not context.metrics then context={metrics=context,daily={},hours={},books={},finished={},activity_days={},return_counts={}} end
    local ok,result=pcall(evaluate,item.trigger,context)
    if ok then return result end
    logger.warn("Kindlevel: achievement trigger failed",item.id,result)
    return {value=0,ratio=0,ready=false,label="Trigger unavailable",error=true}
end

local function openingTrigger(trigger, book)
    if not book or type(trigger) ~= "table" then return false end
    if trigger.type=="book" and trigger.action=="open" then return matches(book,trigger) end
    for _,condition in ipairs(trigger.conditions or {}) do if openingTrigger(condition,book) then return true end end
    return false
end

-- Awards are monotonic. Previewing never calls this function or grants rewards.
function Achievements.check(owner, notify, context)
    context=context or Achievements.context(owner)
    local unlocks=owner.settings:readSetting("achievement_unlocks",{})
    local known=owner.settings:readSetting("achievement_known_ids",{})
    local initialized=owner.settings:has("achievement_known_ids")
    local fresh,changed={},false
    for _,item in ipairs(Achievements.catalog) do
        local opening=openingTrigger(item.trigger,context.open_event)
        if not unlocks[item.id] and (not context.error or context.error=="missing" or opening) and Achievements.progress(item,context).ready then
            local historical=(not initialized or not known[item.id]) and not opening
            unlocks[item.id]={unlocked_at=context.now,source=historical and "history" or "reading"}
            if notify and not historical then fresh[#fresh+1]=item end
            changed=true
        end
        if (context.error ~= "unavailable" or opening) and not known[item.id] then known[item.id]=true; changed=true end
    end
    if changed then
        owner.settings:saveSetting("achievement_unlocks",unlocks)
        owner.settings:saveSetting("achievement_known_ids",known)
        owner.settings:flush()
    end
    owner.achievement_open_event,context.open_event=nil,nil
    return fresh,context,unlocks
end

for _,item in ipairs(require("kindlevel_achievement_catalog")) do Achievements.register(item) end
local ok,custom=pcall(require,"custom_achievements")
if ok and type(custom)=="table" then for _,item in ipairs(custom) do Achievements.register(item) end
elseif ok then logger.warn("Kindlevel: custom achievements must return a list")
elseif not ok and not tostring(custom):find("module 'custom_achievements' not found",1,true) then logger.warn("Kindlevel: custom achievements failed",custom) end

return Achievements
