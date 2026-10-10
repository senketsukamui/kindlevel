local Achievements = require("kindlevel_achievements")
local ImageWidget = require("ui/widget/imagewidget")
local View = {}

function View:achievementPanel()
    local p, width = self:px(28), self.width - self:px(56)
    self:text("Your next chapter", p, self:px(144), width, self:px(52), 30, { single = true, serif = true })
    self:text("ACHIEVEMENTS · VISUAL PREVIEW", p, self:px(201), width, self:px(24), 10, { single = true, gray = 95 })
    local metrics = Achievements.metrics(self.owner)
    for index, item in ipairs(Achievements.catalog) do
        local y = self:px(247 + (index - 1) * 101)
        local progress = Achievements.progress(item, metrics)
        local icon = self:px(39)
        self:addWidget(ImageWidget:new{ file = self.owner.plugin_dir .. "/assets/achievement.svg",
            width = icon, height = icon, alpha = true }, p, y + self:px(6))
        local tx, tw = p + self:px(56), width - self:px(56)
        self:text(item.title, tx, y, tw - self:px(87), self:px(30), 20, { serif = true, single = true })
        self:text("+" .. tostring(item.xp) .. " XP", self.width - p - self:px(81), y + self:px(5), self:px(81), self:px(23), 12,
            { center = true, single = true, gray = 80 })
        self:text(item.description, tx, y + self:px(33), tw, self:px(24), 11, { single = true, gray = 95 })
        self:rect(tx, y + self:px(66), tw - self:px(83), self:px(2), 227)
        self:rect(tx, y + self:px(66), math.floor((tw - self:px(83)) * progress.ratio), self:px(2), progress.ready and 75 or 145)
        self:text(progress.label, tx, y + self:px(73), tw - self:px(87), self:px(20), 9, { single = true, gray = 100 })
        self:text("Preview →", self.width - p - self:px(82), y + self:px(67), self:px(82), self:px(25), 11,
            { single = true })
        self:hit(p, y, width, self:px(93), function() self.owner:previewAchievement(item.id) end,
            "preview-achievement-" .. item.id)
    end
    self:text("Preview rewards are illustrative; no XP or unlocks are saved.", p, self:px(680), width, self:px(25), 10,
        { center = true, single = true, gray = 100 })
    self:text("Try over a book →", p, self:px(711), width, self:px(23), 13, { center = true, single = true })
    self:hit(p, self:px(704), width, self:px(26), function() self.owner:previewAchievementInBook() end, "achievement-in-book")
end

return View
