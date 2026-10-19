-- Real KOReader schema, persistence, extensibility, icons and paginated widgets.
require("setupkoenv")
G_defaults=require("luadefaults"):open()
G_reader_settings=require("luasettings"):open("/tmp/kindlevel-rules-reader.lua")
G_reader_settings:saveSetting("sdl_window",{width=1072,height=1448})
local Device=require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
package.path="/workspace/kindlevel.koplugin/?.lua;plugins/statistics.koplugin/?.lua;" .. package.path
local SQ3=require("lua-ljsqlite3/init")
local Stats=require("kindlevel_stats")
local LuaSettings=require("luasettings")
local Goals=require("kindlevel_goals")
local A=require("kindlevel_achievements")
local UIManager=require("ui/uimanager")
local Blitbuffer=require("ffi/blitbuffer")
local Geom=require("ui/geometry")
assert(#A.catalog==42,"forty-two built-in definitions")
local function ts(day,hour) return os.time{year=2026,month=10,day=day,hour=hour or 7,min=0,sec=0} end
local path="/tmp/kindlevel-achievement-rules.sqlite3"
local conn=SQ3.open(path)
local Native=dofile("plugins/statistics.koplugin/main.lua")
Native:createDB(conn)
local insert_book=conn:prepare("INSERT INTO book(id,title,authors,pages,highlights,notes,md5) VALUES(?,?,?,?,?,?,?);")
for _,row in ipairs{
    {1,"THE HITCHHIKER’S GUIDE TO THE GALAXY","Douglas Adams",100,10,1,"one"},
    {2,"Children of Arrakis","Frank Herbert",100,0,0,"two"},
    {3,"ДЮНА","Фрэнк Герберт",100,0,0,"three"},
    {4,"Moby—Dick","Herman Melville",100,0,0,"four"},
    {5,"The Hobbit","J. R. R. Tolkien",100,0,0,"five"},
} do insert_book:reset():bind(unpack(row)):step() end
insert_book:close()
local insert=conn:prepare("INSERT INTO page_stat_data VALUES(?,?,?,?,?);")
for _,row in ipairs{
    {1,1,ts(1,7),900,50}, -- rescaled into two pages, but remains 15 minutes
    {1,2,ts(2,23),900,100}, {1,3,ts(3,7),60,100},
    {2,1,ts(4,7),3600,100}, -- does not match Dune
    {3,1,ts(8,7),1799,100}, -- one second below the Dune threshold
    {4,1,ts(8,12),900,100}, {5,1,ts(9,7),600,100},
    {1,4,ts(20,7),9000,100}, {1,5,ts(10,18),9000,100}, -- future rows
    {1,6,ts(5,7),0,100}, -- placeholder, not an activity day
} do insert:reset():bind(unpack(row)):step() end
insert:close(); conn:close()
local stats=Stats:new{path=path,now=ts(10,12)}:load()
local settings=LuaSettings:open("/tmp/kindlevel-achievement-rules.lua")
local goals=Goals:new{settings=settings,stats=stats}
local owner={plugin_dir="/workspace/kindlevel.koplugin",settings=settings,
    getStats=function() return stats end,getGoals=function() return goals end}
local context=A.context(owner)
assert(context.metrics.active_days==6 and context.metrics.best_streak==4,"zero/future events excluded; historical best streak")
assert(context.metrics.minutes==(900+900+60+3600+1799+900+600)/60,"raw duration not multiplied by layout rescaling")
assert(context.metrics.pages==8,"native normalized daily page count")
assert(A.progress(A.find("dont_panic"),context).ready,"Unicode case, apostrophe and title aliases")
assert(not A.progress(A.find("spice_must_flow"),context).ready,"unrelated title does not count; minute threshold remains exact")
assert(A.progress(A.find("spice_must_flow"),{metrics={},books={{title="Dune Messiah",seconds=1800}}}).ready,
    "a book name containing the alias qualifies")
assert(A.progress(A.find("dont_panic"),{metrics={},books={{title="Collected Works: The Hitchhiker’s Guide to the Galaxy (Illustrated)",seconds=900}}}).ready,
    "reading triggers accept prefixes and edition suffixes")
assert(A.progress(A.find("white_whale"),{metrics={},finished={{title="Moby-Dick: Annotated Edition"}}}).ready,
    "finish triggers use the same substring matching")
assert(A.progress(A.find("early_bird"),context).ready and not A.progress(A.find("night_owl"),context).ready,"hour-window boundaries")
assert(A.progress(A.find("lunch_break"),context).ready,"noon window")
assert(A.progress(A.find("welcome_back"),context).ready,"three full inactive days before return")
assert(not A.progress(A.find("white_whale"),context).ready,"reading does not imply finish")
assert(not A.progress(A.find("dude"),context).ready,"reading history or a library entry is not an opening event")
local Sessions=require("kindlevel_sessions")
local continuous=Sessions:new({60},{},20000)
for index=0,179 do continuous:add(1,100+index*60,60) end
assert(continuous.best[60].seconds==10800,"three hours of continuous recorded activity")
local marathon={metrics={},sessions=continuous.best}
assert(A.progress(A.find("marathon_reader"),marathon).ready,"three-hour marathon threshold")
continuous:add(1,100+179*60,60)
assert(continuous.best[60].seconds==10800,"duplicate/overlapping intervals count once")
local broken=Sessions:new({60},{},30000)
for index=0,89 do broken:add(1,100+index*60,60) end
for index=0,89 do broken:add(1,100+90*60+61+index*60,60) end
assert(broken.best[60].seconds==5400,"a gap over sixty seconds prevents stitching two long sessions")
local grace=Sessions:new({60},{},30000)
for index=0,89 do grace:add(1,100+index*60,60) end
for index=0,89 do grace:add(1,100+90*60+60+index*60,60) end
assert(grace.best[60].seconds==10800,"a sixty-second gap is tolerated but contributes zero reading time")
local sleeping=Sessions:new({60},{5500},30000)
for index=0,179 do sleeping:add(1,100+index*60,60) end
assert(sleeping.best[60].seconds==5400,"sleep/close boundary splits adjacent intervals")
local switching=Sessions:new({60},{},30000)
for index=0,179 do switching:add(index<90 and 1 or 2,100+index*60,60) end
assert(switching.best[60].seconds==5400,"switching books ends the session")
local straddling=Sessions:new({60},{130},30000)
straddling:add(1,100,60)
assert(not straddling.best[60],"intervals spanning explicit pauses are excluded rather than guessed")
local bounded=Sessions:new({60},{},150)
bounded:add(1,100,100);bounded:add(1,151,100);bounded:add(1,50,0)
assert(bounded.best[60].seconds==50,"future time and zero-duration placeholders never inflate sessions")
local fresh,_,unlocks=A.check(owner,true,context)
assert(#fresh==0 and unlocks.dont_panic and unlocks.first_pages,"historical backfill is silent")
assert(unlocks.dont_panic.source=="history","backfill provenance")
assert(settings:readSetting("xp")==nil and settings:readSetting("level")==nil,"XP and levels never awarded")
local reopened=LuaSettings:open("/tmp/kindlevel-achievement-rules.lua")
assert(reopened:readSetting("achievement_unlocks").dont_panic,"unlock persistence")
-- Cross a threshold, record a finish, and verify one-time notifications.
conn=SQ3.open(path)
conn:exec(string.format("INSERT INTO page_stat_data VALUES(3,2,%d,1,100);",ts(9,9)))
conn:close(); stats:refresh()
goals:record(stats:book(4),"2026-10-09","manual")
context=A.context(owner)
fresh,_,unlocks=A.check(owner,true,context)
local ids={}; for _,item in ipairs(fresh) do ids[item.id]=true end
assert(ids.spice_must_flow and ids.white_whale and ids.first_book,"new time/book-finish thresholds notify")
assert(#A.check(owner,true,context)==0,"checks do not repeat notifications")
-- Opening quests use metadata from ReaderReady, even with no statistics yet.
local open_owner={settings=LuaSettings:open("/tmp/kindlevel-open-quest.lua")}
A.recordOpen(open_owner,{title="MEIN KAMPF",author="Test metadata"},ts(10))
local opened={now=ts(10),error="missing",metrics={},daily={},hours={},books={},finished={},activity_days={},return_counts={},
    opened={{title="MEIN KAMPF",opened_at=ts(10)}},open_event=open_owner.achievement_open_event}
local opened_fresh=A.check(open_owner,true,opened)
assert(#opened_fresh==1 and opened_fresh[1].id=="dude","the actual first opening notifies, including first install without stats")
assert(LuaSettings:open("/tmp/kindlevel-open-quest.lua"):readSetting("achievement_opened_books"),"opened metadata persists")
A.recordOpen(open_owner,{title="Mein Kampf",author="Test metadata"},ts(10))
opened.open_event=open_owner.achievement_open_event
assert(#A.check(open_owner,true,opened)==0,"reopening cannot award twice")
assert(A.progress(A.find("dude"),{metrics={},opened={{title="Моя борьба: комментированное издание"}}}).ready,"translated title fragments")
assert(A.progress(A.find("dude"),{metrics={},opened={{title="A Study of Mein Kampf"}}}).ready,"opening triggers accept an alias anywhere in the name")
assert(not A.progress(A.find("dude"),{metrics={},opened={{title="Mein Other Book"}}}).ready,"unrelated titles still do not match")
local source=unlocks.spice_must_flow.unlocked_at
local empty={now=context.now+86400,metrics={},daily={},hours={},books={},finished={},activity_days={},return_counts={}}
A.check(owner,true,empty)
assert(settings:readSetting("achievement_unlocks").spice_must_flow.unlocked_at==source,"unlocks never disappear after gaps or data removal")
-- Adding definitions needs no UI, notification or engine edits; malformed entries are isolated.
assert(A.register{id="new_custom",text="My Milestone",description="An optional custom condition.",icon="missing.svg",xp=12,
    trigger=function(c) return c.metrics.minutes>=1 end},"function trigger registration")
assert(#A.check(owner,true,context)==0 and settings:readSetting("achievement_unlocks").new_custom.source=="history","new definitions backfill silently")
assert(not A.register{id="first_book",text="Duplicate",description="No",icon="book.svg",xp=1,trigger={type="metric",metric="minutes",target=1}},"duplicate rejected")
assert(not A.register{id="typo",text="Bad",description="No",icon="book.svg",xp=1,trigger={type="metric",metric="minutess",target=1}},"unknown metric rejected")
assert(not A.register{id="empty_alias",text="Bad",description="No",icon="book.svg",xp=1,
    trigger={type="book",action="open",titles={" ... "}}},"an empty normalized fragment cannot match every book")
assert(A.register{id="broken_custom",text="Broken",description="An error is contained.",icon="missing.svg",xp=0,
    trigger=function() error("expected test error") end},"custom trigger accepted")
assert(A.progress(A.find("broken_custom"),context).error,"one bad callback cannot break the catalog")
local all={trigger={type="all",conditions={{type="metric",metric="minutes",target=15},{type="metric",metric="finished",target=2}}}}
assert(not A.progress(all,context).ready,"all requires every condition")
all.trigger.type="any"; assert(A.progress(all,context).ready,"any supports alternative conditions")
local weekday={trigger={type="daily",metric="minutes",target=30,weekdays={5}}}
assert(not A.progress(weekday,context).ready,"Sunday reading does not count toward a Friday-only criterion")
local gap={trigger={type="return",scope="books",min_gap=30,target=1}}
local gapctx={now=ts(10),metrics={},daily={},hours={},finished={},activity_days={},return_counts={},books={
    {days={{date="2026-08-01",seconds=60},{date="2026-09-01",seconds=60}}}}}
assert(A.progress(gap,gapctx).ready,"custom return length accepts thirty full days")
assert(A.iconPath(A.find("new_custom"),owner.plugin_dir)==owner.plugin_dir .. "/assets/achievement.svg","missing icon fallback")
assert(A.iconPath({icon="../main.svg"},owner.plugin_dir)==owner.plugin_dir .. "/assets/achievement.svg","icon paths stay inside assets")
local unavailable={now=ts(10),metrics={minutes=100000},error="unavailable"}
assert(#A.check(owner,true,unavailable)==0,"unavailable database does not grant awards")

local Library=require("kindlevel_library")
local library=Library:new{root=owner.plugin_dir .. "/books"}; library:scan()
owner.getAchievementContext=function() return context end
owner.previewAchievement=function() end
owner.previewAchievementInBook=function() end
local home=require("kindlevel_screen"):new{owner=owner,library=library,initial_tab="achievements"}
UIManager:show(home)
local function render(name)
    home:rebuild()
    local bb=Blitbuffer.new(home.width,home.height,Blitbuffer.TYPE_BB8)
    home:paintTo(bb,0,0); bb:writePNG("/workspace/dist/previews/" .. name .. ".png"); bb:free()
    for _,hit in ipairs(home.hits) do assert(hit.x>=0 and hit.y>=0 and hit.x+hit.w<=home.width+1 and hit.y+hit.h<=home.height+1,"bounds: " .. hit.id) end
end
local function tap(id)
    for _,hit in ipairs(home.hits) do if hit.id==id then
        home:onGesture{ges="tap",pos=Geom:new{x=hit.x+hit.w/2,y=hit.y+hit.h/2,w=0,h=0}}; return
    end end
    error("Missing hit " .. id)
end
for page=1,math.ceil(#A.catalog/3) do home.achievement_page=page; render("achievement-catalog-" .. page) end
home.achievement_page=1;home:rebuild();tap("achievements-next");assert(home.achievement_page==2,"pager")
tap("achievement-filter-books");assert(#home:achievementItems()==8 and home.achievement_page==1,"book quests filter resets page")
render("achievement-book-quests")
tap("achievement-filter-earned");for _,item in ipairs(home:achievementItems()) do assert(unlocks[item.id] or item.id=="new_custom","earned filter") end
home:onNext();home:onPrevious();assert(home.achievement_page==1,"arrow/swipe pagination")
home:onClose()
-- A user's separate catalog is loaded by the same module entry point.
package.preload.custom_achievements=function() return {{id="custom_pack",text="My Pack",description="A personal milestone.",
    icon="achievements/book.svg",xp=10,trigger={type="metric",metric="minutes",target=2}}} end
package.loaded.kindlevel_achievements=nil
local extended=require("kindlevel_achievements")
assert(#extended.catalog==43 and extended.find("custom_pack"),"optional custom catalog loads without engine/UI edits")
print("ALL achievement rules, persistence, extensibility, Unicode matching, icons and UI checks passed")
