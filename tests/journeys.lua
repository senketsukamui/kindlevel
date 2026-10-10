-- Native SQLite/widget integration: breaks, return scope, positions and navigation.
require("setupkoenv")
G_defaults = require("luadefaults"):open()
G_reader_settings = require("luasettings"):open("/tmp/kindlevel-journey-reader.lua")
G_reader_settings:saveSetting("sdl_window", { width = 1072, height = 1448 })
local Device = require("device")
require("document/canvascontext"):init(Device)
require("ui/bidi").setup()
package.path = "/workspace/kindlevel.koplugin/?.lua;plugins/statistics.koplugin/?.lua;" .. package.path
local SQ3 = require("lua-ljsqlite3/init")
local Stats = require("kindlevel_stats")
local Journey = require("kindlevel_journey")
local LuaSettings = require("luasettings")
local UIManager = require("ui/uimanager")
local Blitbuffer = require("ffi/blitbuffer")
local Geom = require("ui/geometry")
local function timestamp(day, hour)
    return os.time{ year = 2026, month = 3, day = day, hour = hour or 9, min = 0, sec = 0 }
end
local path = "/tmp/kindlevel-journey-test.sqlite3"
local conn = SQ3.open(path)
dofile("plugins/statistics.koplugin/main.lua"):createDB(conn)
conn:exec("INSERT INTO book (id,title,authors,pages,highlights,notes,md5) VALUES (1,'A Quiet Beginning','Kindlevel',20,0,0,'one'),(2,'Notes on Reading','Kindlevel',20,0,0,'two');")
local insert = conn:prepare("INSERT INTO page_stat_data VALUES (?,?,?,?,?);")
for _, row in ipairs{
    {1,2,timestamp(1),60,10}, {1,6,timestamp(2),60,10},
    {1,4,timestamp(6),60,10}, {1,8,timestamp(7),60,20}, {1,10,timestamp(8),60,20},
    {1,15,timestamp(12),60,20}, {1,4,timestamp(12,10),60,10},
    {2,2,timestamp(3),60,20}, {2,3,timestamp(4),60,20}, {2,4,timestamp(5),60,20},
    {1,20,timestamp(21),60,20}, {1,20,timestamp(20,18),60,20}, {1,20,timestamp(10),0,20},
} do insert:reset():bind(unpack(row)):step() end
insert:close(); conn:close()
local stats = Stats:new{ path = path, now = timestamp(20,12) }:load()
local history = Journey:new(stats)
assert(Journey.ordinal("2024-03-01") - Journey.ordinal("2024-02-28") == 2, "leap days")
assert(Journey.ordinal("2025-01-01") - Journey.ordinal("2024-12-31") == 1, "year boundary")
assert(Journey.ordinal("2100-03-01") - Journey.ordinal("2100-02-28") == 1, "century leap rule")
local summary = history:book(1, 3)
assert(summary.active_days == 6 and summary.elapsed_days == 12, "reading days differ from inclusive recorded span")
assert(#summary.returns == 2 and #summary.episodes == 3, "exactly three full inactive days separates periods")
assert(summary.returns[1].gap == 3 and summary.returns[2].gap == 3, "DST does not shorten a calendar break")
assert(summary.idle_days == 8 and summary.on_break, "ongoing break is visible but is not a return")
assert(summary.seconds == 420, "raw durations avoid rescaling duplication")
assert(summary.days[2].position == 0.6 and summary.days[3].position == 0.4,
    "position uses the event's layout and may move backward")
assert(summary.days[6].position == 0.75, "furthest position per day is not cumulative coverage")
assert(#history:book(1,7).returns == 0, "changing threshold regroups the same history")
assert(#history:book(99,3).days == 0, "unknown book")
local recovery = history:recovery(3)
assert(#recovery.returns == 1 and recovery.returns[1].date == "2026-03-12", "other books bridge a global reading gap")
assert(recovery.recent_returns == 1 and recovery.typical_break == 3, "recent returns and median completed gaps")
assert(#history:recovery(3,"books").returns == 2, "book and global return counts are separate")
assert(Journey.median({{gap=3},{gap=4},{gap=9},{gap=14}}) == 6.5, "even median")
assert(not Journey.median({}), "no completed breaks has no median")
local short_gap = Journey.summarize({{date="2026-03-01",seconds=60},{date="2026-03-04",seconds=60}}, timestamp(6),3)
assert(#short_gap.returns==0 and #short_gap.episodes==1, "two full inactive days do not meet a three-day threshold")
local ongoing = Journey.summarize({{date="2026-03-01",seconds=60}},timestamp(4),3)
assert(ongoing.idle_days==3 and ongoing.inactive_days==2 and not ongoing.on_break,"today is not a full inactive day")
local settings = LuaSettings:open("/tmp/kindlevel-journey-settings.lua")
local Goals = require("kindlevel_goals")
local goals = Goals:new{ stats = stats, settings = settings }
goals:record(stats:book(1),"2026-03-12","manual")
summary = history:book(1,3,goals)
assert(#summary.finishes == 1 and summary.finishes[1] == "2026-03-12", "only confirmed finishes are shown")
assert(#history:book(2,3,goals).finishes == 0, "positions do not create finishes")
conn = SQ3.open(path)
conn:exec(string.format("INSERT INTO page_stat_data VALUES (2,8,%d,60,20);",timestamp(16)))
conn:close()
assert(#history:recovery(3).returns == 1, "snapshot remains consistent until refresh")
stats:refresh()
assert(#history:recovery(3).returns == 2, "refresh invalidates journey aggregates")

local missing = Journey:new(Stats:new{path="/tmp/no-kindlevel-journeys.sqlite3",now=timestamp(20)})
assert(missing:recovery(3).error == "missing" and #missing:book(1,3).days == 0, "missing history")
-- Older databases lack per-event layout sizes: keep dates/time without fabricating positions.
local legacy_path = "/tmp/kindlevel-journey-legacy.sqlite3"
conn = SQ3.open(legacy_path)
conn:exec("CREATE TABLE page_stat(id_book INTEGER,page INTEGER,start_time INTEGER,duration INTEGER);")
conn:exec(string.format("INSERT INTO page_stat VALUES(1,4,%d,60);",timestamp(1)))
conn:close()
local legacy = Journey:new(Stats:new{path=legacy_path,now=timestamp(20)}):load()
assert(#legacy.books[1] == 1 and legacy.books[1][1].position == nil, "legacy date/time support")

local Library = require("kindlevel_library")
local owner = {plugin_dir="/workspace/kindlevel.koplugin",settings=settings,
    getStats=function() return stats end,getGoals=function() return goals end,recordFinish=function() end}
local library = Library:new{root=owner.plugin_dir .. "/books"}; library:scan()
local home = require("kindlevel_screen"):new{owner=owner,library=library,initial_tab="stats"}
UIManager:show(home)
local function render(name)
    home:rebuild()
    local bb=Blitbuffer.new(home.width,home.height,Blitbuffer.TYPE_BB8)
    home:paintTo(bb,0,0); bb:writePNG("/workspace/dist/previews/" .. name .. ".png"); bb:free()
    for _,hit in ipairs(home.hits) do
        assert(hit.x>=0 and hit.y>=0 and hit.x+hit.w<=home.width+1 and hit.y+hit.h<=home.height+1,"hit bounds: " .. (hit.id or "?"))
    end
end
local function tap(id)
    for _,hit in ipairs(home.hits) do if hit.id==id then
        home:onGesture{ges="tap",pos=Geom:new{x=hit.x+hit.w/2,y=hit.y+hit.h/2,w=0,h=0}}; return
    end end
    error("Missing hit " .. id)
end
tap("return-statistics"); assert(home.stats_view=="recovery","overview navigation")
render("return-statistics")
tap("recovery-books"); render("book-returns")
tap("recovery-return-1"); assert(home.stats_view=="journey" and home.stats_book_id==2,"book return opens matching journey")
render("book-journey")
tap("break-14"); assert(settings:readSetting("return_break_days")==14,"threshold persistence")
tap("break-3")
tap("journey-episode-2"); assert(home.stats_view=="day" and home.stats_date=="2026-03-16","episode opens return-day journal")
home:onBack(); assert(home.stats_view=="journey","journal back restores journey")
home:onBack(); assert(home.stats_view=="recovery" and home.stats_recovery_mode=="books","journey back restores book returns")
home:onBack(); tap("stats-books"); tap("history-book-1"); tap("book-journey")
assert(home.stats_view=="journey" and home.stats_book_id==1,"book details navigation")
render("book-journey-confirmed")
home:onBack(); assert(home.stats_view=="book","back restores book details")
-- More than one page of reading periods and return cards; page survives drilling down.
conn=SQ3.open(path)
conn:exec("INSERT INTO book(id,title,authors,pages,highlights,notes,md5) VALUES(3,'L’été · 東京 — A very long book title for the journey view','Kindlevel',20,0,0,'three');")
for _,key in ipairs{"2026-01-01","2026-01-10","2026-01-20","2026-01-30","2026-02-10"} do
    conn:exec(string.format("INSERT INTO page_stat_data VALUES(3,2,%d,60,20);",Stats.date(key)+36000))
end
conn:close(); stats:refresh()
home:statsNavigate("journey"); home.stats_book_id,home.stats_list_page=3,1
render("book-journey-many-periods")
tap("journey-next"); assert(home.stats_list_page==2,"journey pager")
tap("journey-episode-2"); home:onBack(); assert(home.stats_list_page==2,"back preserves journey page")
home.stats_view,home.stats_recovery_mode,home.stats_list_page="recovery","books",1
home:rebuild(); tap("journey-next"); assert(home.stats_list_page==2,"return pager")
tap("recovery-return-4"); home:onBack(); assert(home.stats_view=="recovery" and home.stats_list_page==2,"back preserves return page")
home:onNext(); home:onNext(); home:onNext(); assert(home.stats_list_page==math.ceil(#history:recovery(3,"books").returns/3),"paging clamps at last page")
home.owner.getStats=function() return missing.stats end
home.stats_view="recovery"; render("returns-empty")
home.stats_view="journey"; render("journey-empty")
home:onClose()
print("ALL journey, recovery, DST, legacy database, refresh, and native UI checks passed")
