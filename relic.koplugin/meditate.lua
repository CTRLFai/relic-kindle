--[[
Relic: full-screen countdown for Meditate and Pomodoro.

A ring of 60 dots around the time left. Elapsed dots fade as the session runs.
E-ink friendly: redraws only the ring area, once every TICK seconds, with a
non-flashing partial refresh. The screen stays awake for the session (the
Kindle would otherwise sleep after about 10 minutes) and is allowed to sleep
again as soon as the time is up or the screen closes.

Usage: Meditate.show{ game = Game, state = s, on_done = fn, on_stop = fn, on_close = fn }
]]
local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local InputContainer = require("ui/widget/container/inputcontainer")
local PluginShare = require("pluginshare")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local Screen = Device.screen

local Meditate = {}
Meditate.TICK = 10     -- seconds between redraws
Meditate.DOTS = 60

-- Keep awake --------------------------------------------------------------------------------
-- Kindle: powerd's own sleep timer is held off with preventScreenSaver (what KOReader's
-- KeepAlive plugin does); KOReader's AutoSuspend is paused through PluginShare. A flag in
-- G_reader_settings records that Relic set it; Exit and Restart release it, and
-- Meditate.releaseStale() clears one left by a crash the next time KOReader starts.

local FLAG = "relic_keep_awake"

local function setPreventScreenSaver(on)
    if Device:isKindle() then
        os.execute("lipc-set-prop com.lab126.powerd preventScreenSaver " .. (on and "1" or "0"))
    end
end

function Meditate.keepAwake()
    if G_reader_settings:isTrue(FLAG) then return end
    Meditate.had_keepalive = PluginShare.keepalive
    Meditate.had_pause = PluginShare.pause_auto_suspend
    PluginShare.pause_auto_suspend = true
    -- AutoSuspend must not reset powerd's timer while preventScreenSaver is on (it crashes);
    -- the keepalive flag tells it to skip that.
    PluginShare.keepalive = true
    setPreventScreenSaver(true)
    G_reader_settings:makeTrue(FLAG)
    G_reader_settings:flush()
end

function Meditate.allowSleep()
    if not G_reader_settings:isTrue(FLAG) then return end
    PluginShare.pause_auto_suspend = Meditate.had_pause or nil
    PluginShare.keepalive = Meditate.had_keepalive or nil
    if not Meditate.had_keepalive then setPreventScreenSaver(false) end
    G_reader_settings:delSetting(FLAG)
    G_reader_settings:flush()
end

-- Called at plugin start: if the flag survived a crash, undo it.
function Meditate.releaseStale()
    if G_reader_settings:isTrue(FLAG) then
        logger.warn("Relic: clearing keep-awake left over from an interrupted meditation")
        Meditate.had_keepalive, Meditate.had_pause = nil, nil
        Meditate.allowSleep()
    end
end

-- Screen --------------------------------------------------------------------------------------

local Screen_ = InputContainer:extend{
    covers_fullscreen = true,
}

function Screen_:init()
    local w, h = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = w, h = h }
    self.ges_events = { Tap = { GestureRange:new{ ges = "tap", range = self.dimen } } }
    local R = math.floor(math.min(w, h) * 0.40)
    self.cx, self.cy, self.R = math.floor(w / 2), math.floor(h / 2), R
    self.dot = math.max(4, math.floor(R * 2 * math.pi / self.DOTS_N / 2.6))
    local m = self.dot + 2
    self.ring = Geom:new{ x = self.cx - R - m, y = self.cy - R - m, w = 2 * (R + m), h = 2 * (R + m) }
    self.tick_fn = function() self:tick() end
    if self:left() > 0 then Meditate.keepAwake() end
    self:schedule()
end

function Screen_:left()
    local left, se = self.game.sessionLeft(self.state, os.time())
    return left or 0, se
end

local function text(str, size, bold)
    return TextWidget:new{ text = str, face = Font:getFace(bold and "tfont" or "cfont", size), bold = bold }
end

local function centered(bb, tw, cx, y)
    local sz = tw:getSize()
    tw:paintTo(bb, cx - math.floor(sz.w / 2), y)
    local h = sz.h
    tw:free()
    return h
end

function Screen_:paintTo(bb, x, y)
    local w, h = self.dimen.w, self.dimen.h
    bb:paintRect(x, y, w, h, Blitbuffer.COLOR_WHITE)
    local left, se = self:left()
    local total = se and se.min * 60 or 1
    local N = self.DOTS_N
    -- dots still to go: clockwise from 12 o'clock, the elapsed ones fade first
    local remaining = math.min(N, math.ceil(N * left / total))
    for i = 0, N - 1 do
        local a = 2 * math.pi * i / N - math.pi / 2
        local dx = x + self.cx + math.floor(self.R * math.cos(a) + 0.5)
        local dy = y + self.cy + math.floor(self.R * math.sin(a) + 0.5)
        if i >= N - remaining then
            bb:paintCircle(dx, dy, self.dot, Blitbuffer.COLOR_BLACK)
        else
            bb:paintCircle(dx, dy, self.dot, Blitbuffer.COLOR_GRAY_9, 2)
        end
    end
    -- time left, rounded up to the tick so it never reads 0:00 early
    local big
    if left > 0 then
        local s10 = math.ceil(left / Meditate.TICK) * Meditate.TICK
        big = string.format("%d:%02d", math.floor(s10 / 60), s10 % 60)
    else
        big = "Done"
    end
    local tw = text(big, 96)
    local th = tw:getSize().h
    centered(bb, tw, x + self.cx, y + self.cy - math.floor(th / 2))
    -- title and hint, outside the ring so a tick never repaints them
    local title = "MEDITATE  ·  " .. (se and se.min or "?") .. " min"
    if se and se.kind == "pomodoro" then
        -- Pomodoro uses the same countdown (Mike, 2026-10-22)
        local q = self.game.findQuest(self.state, se.quest)
        local name = q and q.title or "?"
        if #name > 34 then name = name:sub(1, 32):gsub("[\128-\191]*$", ""):gsub("[\192-\255]$", "") .. "..." end
        title = "POMODORO  ·  " .. name
    end
    centered(bb, text(title, 22, true), x + self.cx, y + Screen:scaleBySize(36))
    local hint = left > 0 and "Tap for options" or "Time's up. Tap to finish."
    local hw = text(hint, 22)
    centered(bb, hw, x + self.cx, y + h - Screen:scaleBySize(70))
end

-- Next redraw lands when the shown time changes (every TICK seconds).
function Screen_:schedule()
    UIManager:unschedule(self.tick_fn)
    local left = self:left()
    if left <= 0 then return end
    local wait = left % Meditate.TICK
    if wait == 0 then wait = Meditate.TICK end
    UIManager:scheduleIn(wait, self.tick_fn)
end

function Screen_:tick()
    local left = self:left()
    if left <= 0 then
        -- finished: one full refresh to clear ghosting, then let the Kindle sleep normally
        Meditate.allowSleep()
        UIManager:setDirty(self, "full")
        return
    end
    local ring = self.ring
    UIManager:setDirty(self, function() return "ui", ring end)
    self:schedule()
end

function Screen_:onTap()
    local left = self:left()
    if left <= 0 then
        self:close()
        if self.on_done then self.on_done() end
        return true
    end
    local dialog
    dialog = ButtonDialog:new{
        title = string.format("%d min to go", math.ceil(left / 60)),
        buttons = {
            { { text = "Keep going", callback = function() UIManager:close(dialog) end } },
            { { text = "Back to Relic (timer keeps running)", callback = function()
                UIManager:close(dialog); self:close()
            end } },
            { { text = "Stop (won't count)", callback = function()
                UIManager:close(dialog); self:close()
                -- time may have run out while this dialog was open: then it counts
                if self:left() <= 0 then
                    if self.on_done then self.on_done() end
                elseif self.on_stop then self.on_stop() end
            end } },
        },
    }
    UIManager:show(dialog)
    return true
end

-- Woken by the power button: catch up and resume ticking.
function Screen_:onResume()
    if self:left() > 0 then Meditate.keepAwake() else Meditate.allowSleep() end
    UIManager:setDirty(self, "full")
    self:schedule()
end

-- Asleep: nothing to hold the screen on for. Taken back on resume if time is left.
function Screen_:onSuspend()
    UIManager:unschedule(self.tick_fn)
    Meditate.allowSleep()
end

-- KOReader quitting doesn't close widgets, so release on these too (don't consume them).
function Screen_:onExit() Meditate.allowSleep() end
function Screen_:onRestart() Meditate.allowSleep() end

function Screen_:close()
    UIManager:unschedule(self.tick_fn)
    Meditate.allowSleep()
    UIManager:close(self, "flashui")
    if self.on_close then self.on_close() end
end

function Screen_:onCloseWidget()
    UIManager:unschedule(self.tick_fn)
    Meditate.allowSleep()
end

function Meditate.show(opts)
    opts.DOTS_N = Meditate.DOTS
    local w = Screen_:new(opts)
    UIManager:show(w, "full")
    return w
end

return Meditate
