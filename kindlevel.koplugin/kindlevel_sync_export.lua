-- Read-only adapter: export book/day aggregates from KOReader's normalized view.
local Export={}
local Stats=require("kindlevel_stats")
local Goals=require("kindlevel_goals")
local DocSettings=require("docsettings")
local colors={"olive","sage","clay","ink","sand","rose"}

local function number(value) return math.max(0,math.floor(tonumber(value) or 0)) end
local function author(value) return type(value)=="table" and table.concat(value,", ") or value or "" end

function Export.snapshot(owner,sequence)
    local stats=owner:getStats():refresh()
    assert(stats.error~="unavailable","Cannot read reading statistics. Try syncing again after closing your book.")
    local goals=owner:getGoals()
    local payload={schema=1,sequence=sequence,captured_at=os.time(),version=require("kindlevel_version"),books={},activity={},achievements={},current_book="",
        goals={daily_minutes=number(owner.settings:readSetting("daily_minutes") or 20),yearly_books=goals:target(tonumber(os.date("%Y")))}}
    local utc=os.date("!*t",payload.captured_at);utc.isdst=os.date("*t",payload.captured_at).isdst
    payload.timezone_offset=os.difftime(payload.captured_at,os.time(utc))
    local by_id={}
    local finishes=owner.settings:readSetting("finished_books",{})
    for index,book in ipairs(stats.books) do
        assert(index<=5000,"Too many books to sync in this version.")
        local finished=""
        for _,date in pairs((finishes[Goals.key(book)] or {}).dates or {}) do if goals:validDate(date) and date>finished then finished=date end end
        local value={id="stats:" .. book.id,title=book.title,author=book.author,format="BOOK",status=finished~="" and "finished" or book.seconds>0 and "reading" or "unread",
            progress=0,progress_known=false,pages=number(book.total_pages),color=colors[(book.id-1)%#colors+1],description="",finished=finished}
        by_id[book.id]=value;payload.books[#payload.books+1]=value
    end
    local files,seen={},{}
    local reader=owner.ui and owner.ui.document and owner.ui
    local current=reader and reader.document and reader.document.file or owner.settings:readSetting("selected_file")
    if current then files[#files+1]=current end
    for _,item in ipairs(require("readhistory").hist or {}) do files[#files+1]=item.file end
    local library=owner.home and owner.home.library or owner.goal_library
    if library then for _,book in ipairs(library.books) do files[#files+1]=book.file end end
    for _,file in ipairs(files) do
        if not seen[file] and DocSettings:hasSidecarFile(file) then
            local config=reader and reader.document and reader.document.file==file and reader.doc_settings or DocSettings:open(file)
            local props=config:readSetting("doc_props") or config:readSetting("stats") or {}
            local book=stats:findBook{file=file,title=props.title or props.display_title,author=author(props.authors)}
            local value=book and by_id[book.id]
            if value then
                value.format=(file:match("%.([^.]+)$") or "BOOK"):upper()
                local percent=tonumber(config:readSetting("percent_finished"))
                if percent then value.progress=math.floor(math.max(0,math.min(1,percent))*100+0.5);value.progress_known=true end
                if file==current then payload.current_book=value.id end
            end
        end
        seen[file]=true
    end
    if payload.current_book=="" then
        for _,book in ipairs(payload.books) do if book.status=="reading" then payload.current_book=book.id;break end end
    end
    local result,err=stats:query(function(conn)
        local stmt=conn:prepare([[SELECT id_book,strftime('%Y-%m-%d',start_time,'unixepoch','localtime'),count(DISTINCT page),sum(duration)
            FROM page_stat WHERE duration>0 GROUP BY 1,2 ORDER BY 2,1;]])
        local rows={}
        for row in stmt:rows() do
            local id,date=tonumber(row[1]),row[2]
            if by_id[id] then
                assert(#rows<100000,"Too much reading history to sync in this version.")
                rows[#rows+1]={id="stats:" .. id .. ":" .. date,book_id="stats:" .. id,date=date,pages=number(row[3]),seconds=number(row[4])}
            end
        end
        stmt:close();return rows
    end)
    assert(err~="unavailable","Cannot read reading history. Your server copy has been kept.")
    payload.activity=result or {}
    local achievements=require("kindlevel_achievements")
    local context=achievements.context(owner)
    local unlocks=owner.settings:readSetting("achievement_unlocks",{})
    for _,item in ipairs(achievements.catalog) do
        local progress=achievements.progress(item,context)
        local icon=item.icon:match("^achievements/([%w_-]+)%.svg$") or "book"
        payload.achievements[#payload.achievements+1]={id=item.id,title=item.title,description=item.description,icon=icon,xp=item.xp,
            progress=number(progress.value),target=math.max(1,number(progress.target)),unit=progress.label and progress.label:match("%s([%a]+)$") or "conditions",
            unlocked=unlocks[item.id] and os.date("%Y-%m-%d",unlocks[item.id].unlocked_at) or ""}
    end
    for _,key in ipairs{"books","activity","achievements"} do require("json").util.InitArray(payload[key]) end
    return payload
end

return Export
