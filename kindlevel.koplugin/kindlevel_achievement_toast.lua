local Blitbuffer = require("ffi/blitbuffer")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local Widget = require("ui/widget/widget")
local Screen = Device.screen
local Theme = require("kindlevel_theme")

local Toast = Widget:extend{
    name = "KindlevelAchievementToast", toast = true, modal = false,
    disable_double_tap = false, timeout = 4,
}

function Toast:init()
    local scale = math.min(Screen:getWidth() / 600, Screen:getHeight() / 800)
    self.scale = scale
    local function px(value) return math.floor(value * scale + 0.5) end
    self.width = math.min(px(324), Screen:getWidth() - px(32))
    self.height = px(94)
    self.dimen = Geom:new{ x = Screen:getWidth() - self.width - px(19), y = Screen:getHeight() - self.height - px(62),
        w = self.width + px(3), h = self.height + px(3) }
    self.resources, self.texts = {}, {}
    local factor = Screen:scaleBySize(1000) / 1000
    local function text(value, x, y, width, size, gray, bold, serif)
        local widget = TextWidget:new{ text = value, padding = 0, bold = bold, max_width = width,
            face = Theme.face(self.plugin_dir, size * scale / factor, {serif=serif}),
            fgcolor = Blitbuffer.Color8(gray) }
        self.resources[#self.resources + 1] = widget
        self.texts[#self.texts + 1] = { widget = widget, x = x, y = y }
    end
    self.icon = require("kindlevel_achievements").iconWidget(self.achievement, self.plugin_dir, px(36))
    self.resources[#self.resources + 1] = self.icon
    local tx = px(82)
    local tw = self.width - tx - px(15)
    text("ACHIEVEMENT UNLOCKED", tx, px(15), tw, 12, 85, false)
    text(self.achievement.title, tx, px(38), tw, 21, 34, false, true)
    text(self.achievement.notification, tx, px(68), tw, 12, 85, false)
    if self.preview then text("PREVIEW", self.width-px(72),px(4),px(65),9,100,false) end
end

function Toast:paintTo(bb, x, y)
    self.dimen.x, self.dimen.y = x, y
    local function px(v) return math.floor(v * self.scale + 0.5) end
    bb:paintRect(x, y, self.width, self.height, Blitbuffer.COLOR_WHITE)
    bb:paintBorder(x, y, self.width, self.height, math.max(1,px(1)), Blitbuffer.Color8(100))
    bb:paintRect(x+px(14),y+px(20),px(54),px(54),Blitbuffer.Color8(238))
    self.icon:paintTo(bb,x+px(23),y+px(29))
    for _, item in ipairs(self.texts) do item.widget:paintTo(bb, x + item.x, y + item.y) end
end

function Toast:onShow()
    self._timeout = function() self:onClose() end
    UIManager:scheduleIn(self.timeout, self._timeout)
end

function Toast:onClose()
    if not self.closed then UIManager:close(self, "ui", self.dimen) end
    return false
end

function Toast:onCloseWidget()
    if self.closed then return end
    self.closed = true
    if self._timeout then UIManager:unschedule(self._timeout); self._timeout = nil end
    for _, widget in ipairs(self.resources) do widget:free() end
    self.resources = {}
    if self.on_done then self.on_done(self) end
end

-- Match KOReader toast behavior: dismiss and let the original input reach the reader.
Toast.onGesture = Toast.onClose
Toast.onKeyPress = Toast.onClose
Toast.onKeyRepeat = Toast.onClose

local Manager = { pending = {}, active = nil }

function Manager:changed()
    if self.observer then self.observer() end
end

function Manager:advance()
    if self.active or #self.pending == 0 then return end
    local request = table.remove(self.pending, 1)
    local toast = Toast:new{
        achievement = request.achievement, plugin_dir = request.plugin_dir, timeout = request.timeout or 4, preview = request.preview,
        on_done = function(widget)
            if self.active == widget then self.active = nil end
            self:changed()
            if #self.pending > 0 then UIManager:scheduleIn(0.2, function() self:advance() end) end
        end,
    }
    self.active = toast
    UIManager:show(toast, "ui", toast.dimen, toast.dimen.x, toast.dimen.y)
    self:changed()
end

function Manager:preview(achievement, plugin_dir, timeout)
    self.pending[#self.pending + 1] = { achievement = achievement, plugin_dir = plugin_dir, timeout = timeout, preview = true }
    self:advance()
end

function Manager:unlock(achievement, plugin_dir)
    self.pending[#self.pending + 1] = { achievement = achievement, plugin_dir = plugin_dir, preview = false }
    self:advance()
end

function Manager:clear()
    self.pending = {}
    if self.active then self.active:onClose() end
end

function Toast:onSuspend()
    Manager:clear()
    return false
end

Manager.Toast = Toast
return Manager
