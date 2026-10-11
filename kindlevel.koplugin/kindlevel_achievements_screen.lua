local Achievements = require("kindlevel_achievements")
local UIManager = require("ui/uimanager")
local View = {}

function View:achievementItems()
    local unlocks = self.owner.settings:readSetting("achievement_unlocks", {})
    local filter, items = self.achievement_filter or "all", {}
    for _, item in ipairs(Achievements.catalog) do
        if filter == "all" or filter == "earned" and unlocks[item.id]
            or filter == "locked" and not unlocks[item.id] or filter == "books" and item.group == "books" then
            items[#items + 1] = item
        end
    end
    return items, unlocks
end

function View:achievementNext(direction)
    local items = self:achievementItems()
    self.achievement_page = math.max(1, math.min(math.max(1, math.ceil(#items / 4)), (self.achievement_page or 1) + direction))
    self:rebuild()
    return true
end

function View:achievementDetails(item, progress, unlock)
    local status = unlock and "Unlocked · recognized on " .. os.date("%d %b %Y", unlock.unlocked_at)
        or "Locked · " .. progress.label
    UIManager:show(require("ui/widget/infomessage"):new{
        text = item.text .. "\n\n" .. item.description .. "\n\n" .. status
            .. "\n\n" .. tostring(item.xp) .. " XP reserved for future progression. No XP is awarded yet.",
    })
end

function View:achievementPanel()
    local p, width = self:px(28), self.width - self:px(56)
    local context = self.owner.getAchievementContext and self.owner:getAchievementContext() or Achievements.context(self.owner)
    local items, unlocks = self:achievementItems()
    local earned = 0
    for _, item in ipairs(Achievements.catalog) do if unlocks[item.id] then earned = earned + 1 end end
    self:text("Achievements", p, self:px(144), width, self:px(43), 30, { single = true, serif = true })
    self:text(string.format("%d / %d unlocked · XP reserved for later", earned, #Achievements.catalog), p,
        self:px(191), width, self:px(21), 11, { single = true, gray = 90 })
    local cell = width / 4
    for index, filter in ipairs{ {"all","All"}, {"earned","Earned"}, {"locked","Locked"}, {"books","Book quests"} } do
        local x = p + (index - 1) * cell
        self:text(filter[2], x, self:px(219), cell, self:px(22), 12, { center = true, single = true })
        if (self.achievement_filter or "all") == filter[1] then self:rect(x + self:px(12), self:px(240), cell - self:px(24), self:px(1), 0) end
        self:hit(x, self:px(212), cell, self:px(34), function()
            self.achievement_filter, self.achievement_page = filter[1], 1; self:rebuild()
        end, "achievement-filter-" .. filter[1])
    end
    local pages = math.max(1, math.ceil(#items / 4))
    self.achievement_page = math.max(1, math.min(self.achievement_page or 1, pages))
    local first = (self.achievement_page - 1) * 4 + 1
    for slot = 0, 3 do
        local item = items[first + slot]
        if item then
            local y = self:px(254 + slot * 99)
            local progress, unlock = Achievements.progress(item, context), unlocks[item.id]
            local icon = self:px(43)
            self:rect(p, y + self:px(3), icon, icon, unlock and 235 or 248)
            self:addWidget(Achievements.iconWidget(item, self.owner.plugin_dir, icon), p, y + self:px(3))
            local tx, tw = p + self:px(56), width - self:px(56)
            self:text(item.text, tx, y, tw - self:px(87), self:px(29), 19, { serif = true, single = true })
            self:text(tostring(item.xp) .. " XP", self.width - p - self:px(81), y + self:px(5), self:px(81), self:px(23), 11,
                { center = true, single = true, gray = 95 })
            self:text(item.description, tx, y + self:px(31), tw, self:px(30), 11, { gray = 90 })
            self:rect(tx, y + self:px(65), tw, self:px(2), 227)
            self:rect(tx, y + self:px(65), math.floor(tw * (unlock and 1 or progress.ratio)), self:px(2), unlock and 35 or 145)
            self:text(unlock and "Unlocked · " .. os.date("%d %b %Y", unlock.unlocked_at) or progress.label,
                tx, y + self:px(73), tw, self:px(19), 9, { single = true, gray = unlock and 55 or 100 })
            self:hit(p, y, width, self:px(93), function()
                self:achievementDetails(item, progress, unlock)
            end, "achievement-details-" .. item.id)
        end
    end
    if #items == 0 then self:text("No achievements in this view yet.", p, self:px(400), width, self:px(60), 19, { center = true, gray = 90 }) end
    self:button("‹", p, self:px(695), self:px(49), self:px(30), function() self:achievementNext(-1) end, false, "achievements-previous")
    self:text(string.format("%d / %d · Swipe to browse", self.achievement_page, pages), p + self:px(60), self:px(701), width - self:px(120), self:px(23), 11,
        { center = true, single = true, gray = 90 })
    self:button("›", self.width - p - self:px(49), self:px(695), self:px(49), self:px(30), function() self:achievementNext(1) end, false, "achievements-next")
end

return View
