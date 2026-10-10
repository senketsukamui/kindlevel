-- Visual POC: criteria read existing history; previewing never grants XP or awards.
local Stats = require("kindlevel_stats")
local Achievements = {}
Achievements.catalog = {
    { id = "first_pages", title = "First Pages", description = "Spend 15 minutes with a book.",
      notification = "15 minutes of reading", threshold = 15, metric = "minutes", unit = "min", xp = 25, icon = "achievement" },
    { id = "consistent_reader", title = "Consistent Reader", description = "Read on seven consecutive days.",
      notification = "A seven-day reading streak", threshold = 7, metric = "streak", unit = "days", xp = 75, icon = "achievement" },
    { id = "page_turner", title = "Page Turner", description = "Read 1,000 pages, one page at a time.",
      notification = "1,000 pages read", threshold = 1000, metric = "pages", unit = "pages", xp = 100, icon = "achievement" },
    { id = "first_book", title = "First Book", description = "Finish a book and record its finish date.",
      notification = "Your first finished book", threshold = 1, metric = "finished", unit = "book", xp = 150, icon = "achievement" },
}

function Achievements.find(id)
    for _, item in ipairs(Achievements.catalog) do if item.id == id then return item end end
end

function Achievements.metrics(owner)
    local stats = owner:getStats():load()
    local _, totals = stats:series("all")
    local finished = 0
    local goals = owner:getGoals()
    for _, record in pairs(owner.settings:readSetting("finished_books") or {}) do
        for _, date in pairs(record.dates or {}) do
            if goals:validDate(date) then finished = finished + 1; break end
        end
    end
    return { minutes = math.floor(totals.seconds / 60), pages = totals.pages, streak = stats:streak(), finished = finished }
end

function Achievements.progress(item, metrics)
    local value = metrics[item.metric] or 0
    return { value = value, ratio = math.min(1, value / item.threshold), ready = value >= item.threshold,
        label = string.format("%s / %s %s", Stats.number(math.min(value, item.threshold)), Stats.number(item.threshold), item.unit) }
end

return Achievements
