--[[
Relic prototype: KOReader plugin UI.
Plain, unstyled. Goal: prove the interaction loop works on a Kindle PW2.
Open from the Tools menu (Relic) or bind "Open Relic" to a gesture.
]]

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local ButtonTable = require("ui/widget/buttontable")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local ProgressWidget = require("ui/widget/progresswidget")
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local TextWidget = require("ui/widget/textwidget")
local InfoMessage = require("ui/widget/infomessage")
local TextViewer = require("ui/widget/textviewer")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local LuaSettings = require("luasettings")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
-- Relic warnings (any module, first arg starting "Relic") also go to the status report's error ring.
local logger = require("logger")
local logger_warn_raw = logger.raw_warn_before_relic or logger.warn
logger.raw_warn_before_relic = logger_warn_raw
local relicErrors  -- set below, once DataStorage is loaded
local in_ring = false
logger.warn = function(...)
    logger_warn_raw(...)
    local first = ...
    if relicErrors and not in_ring and type(first) == "string" and first:match("^Relic") then
        in_ring = true
        pcall(relicErrors, ...)
        in_ring = false
    end
end
local logger_warn = function(...) return logger.warn(...) end
local Screen = Device.screen

-- game.lua lives next to this file
local plugin_dir = debug.getinfo(1, "S").source:match("^@(.*/)[^/]*$") or "./"
local Game = dofile(plugin_dir .. "game.lua")
Game.SKILLS = dofile(plugin_dir .. "skills.lua")
Game.BOOK = dofile(plugin_dir .. "recipes.lua")
Game.setRoute(dofile(plugin_dir .. "route.lua"))
local Gear = dofile(plugin_dir .. "gear.lua")
local Combat = dofile(plugin_dir .. "combat.lua")
Combat.bind(Game, Gear)
Game.GEAR, Game.COMBAT = Gear, Combat
local Updater = dofile(plugin_dir .. "updater.lua")
local Event = require("ui/event")
local Lock = dofile(plugin_dir .. "lockscreen.lua")
local Inbox = dofile(plugin_dir .. "inbox.lua")
Inbox.parseRecurrence = Game.parseRecurrence
local Backup = dofile(plugin_dir .. "backup.lua")
local Chronicle = dofile(plugin_dir .. "chronicle.lua")
local Meditate = dofile(plugin_dir .. "meditate.lua")
local Story = dofile(plugin_dir .. "story.lua")
Story.load(dofile(plugin_dir .. "story_act1.lua"))
Story.load(dofile(plugin_dir .. "story_act2.lua"))
Updater.setPluginDir(plugin_dir)
local Status = dofile(plugin_dir .. "status.lua")
local C = dofile(plugin_dir .. "console.lua")
local RUNNING_VERSION = Updater.installedVersion()

-- Error ring for the status report: Relic warnings since the last report, kept on disk so a
-- crash or restart doesn't lose them. Cleared after each report is sent.
local ERR_MAX = 30
-- Own file: relic_inbox.lua is held open by pull/backup, whose later save would overwrite these.
local function errorStore() return LuaSettings:open(DataStorage:getSettingsDir() .. "/relic_errors.lua") end
relicErrors = function(...)
    local parts = {}
    for i = 1, select("#", ...) do table.insert(parts, tostring((select(i, ...)))) end
    local st = errorStore()
    local list = st:readSetting("status_errors") or {}
    table.insert(list, os.date("%m-%d %H:%M ") .. table.concat(parts, " "):sub(1, 300))
    while #list > ERR_MAX do table.remove(list, 1) end
    st:saveSetting("status_errors", list)
    st:flush()
end

local SAVE_PATH = DataStorage:getSettingsDir() .. "/relic_state.lua"
local QUESTS_PER_PAGE = 10

-- Screen ------------------------------------------------------------------

local Relic_ref  -- set to the plugin class below, so the screen can unregister itself
local writeLockScreen  -- defined in the Lock screen section; forward-declared for RelicScreen:onClose
local RelicScreen = InputContainer:extend{
    tab = "quests",
    page = 1,
    covers_fullscreen = true,
}

function RelicScreen:init()
    self.dimen = Geom:new{ x = 0, y = 0, w = Screen:getWidth(), h = Screen:getHeight() }
    self.store = LuaSettings:open(SAVE_PATH)
    self.state = Game.migrate(self.store:readSetting("state") or Game.newState(os.time()))
    self:render()
end

function RelicScreen:save()
    if Relic_ref and Relic_ref.restoring then return end
    self.store:saveSetting("state", self.state)
    self.store:flush()
end

-- NOTE: never name a method "toast": UIManager treats any truthy widget.toast as the toast flag.
function RelicScreen:notify(text)
    UIManager:show(InfoMessage:new{ text = text, timeout = 2 })
end

-- Small layout helpers ---------------------------------------------------

-- LCARS frame: page bodies are built as if the screen were the frame's content width.
local W_OVERRIDE, LCARS_BUTTONS = nil, false
local W = function() return W_OVERRIDE or Screen:getWidth() end
local PAD = Screen:scaleBySize(12)
local BTN_H = Screen:scaleBySize(56) -- about 9 mm on a PW2: comfortable tap target

-- Body text face. Inside the LCARS frame every page body uses Antonio, like the frame
-- (Mike, 2026-10-20: fonts didn't match). Antonio is narrow, so it runs 2 pt larger.
local function bface(bold, size)
    if LCARS_BUTTONS then
        local f = C.pointFace(bold and "lcars" or "lcarsr", (size or 20) + 2)
        if f then return f, false end
    end
    return Font:getFace(bold and "tfont" or "cfont", size or 20), bold
end

local function text(str, size, bold)
    local face, fake_bold = bface(bold, size)
    return TextBoxWidget:new{
        text = str,
        face = face,
        width = W() - 2 * PAD,
        bold = fake_bold,
    }
end

local function rule()
    return LineWidget:new{
        background = Blitbuffer.COLOR_BLACK,
        dimen = Geom:new{ w = W() - 2 * PAD, h = Size.line.thick },
    }
end

local function gap(h) return VerticalSpan:new{ width = h or PAD } end

-- Popups with a Close / Back / Cancel row pinned under the list, so a long list that scrolls
-- never hides the way out (Mike, 2026-10-08). A trailing single Close/Back/Cancel row moves
-- into the pinned footer; a dialog without one gets a Close.
local CLOSE_WORDS = { CLOSE = true, BACK = true, CANCEL = true }
local PinnedDialog = ButtonDialog:extend{}
function PinnedDialog:init()
    if not self._foot then
        local rows = self.buttons
        local last = rows[#rows]
        if #rows > 1 and #last == 1 and CLOSE_WORDS[tostring(last[1].text or ""):upper()] then
            self._foot = table.remove(rows)
        else
            self._foot = { { text = "Close", callback = function() UIManager:close(self) end } }
        end
    end
    self.layout = nil  -- (a re-init must not keep the previous button layout)
    ButtonDialog.init(self)
    local vg = self.movable[1][1]
    local w = self.buttontable:getSize().w
    local foot = ButtonTable:new{ buttons = { self._foot }, width = w, show_parent = self }
    table.insert(vg, LineWidget:new{ background = Blitbuffer.COLOR_GRAY, dimen = Geom:new{ w = w, h = Size.line.medium } })
    table.insert(vg, foot)
    vg._size = nil
    if self.layout and foot.layout then
        for _, r in ipairs(foot.layout) do table.insert(self.layout, r) end
        foot.layout = nil
    end
    -- The footer made the dialog taller: if it no longer fits, show fewer list rows per page.
    local over = self.movable[1]:getSize().h - (Screen:getHeight() - 2 * Size.margin.default)
    if over > 0 and self.cropping_widget and not self._shrunk then
        local grid = self.buttontable:getStepScrollGrid()
        local rh = grid[1].bottom + 1 - grid[1].top
        self.rows_per_page = math.max(1, math.floor(self.cropping_widget.dimen.h / rh) - math.ceil(over / rh))
        self._shrunk = true
        self:init()
    end
end

function RelicScreen:buttons(rows)
    if LCARS_BUTTONS then return self:lcarsButtons(rows) end
    return ButtonTable:new{
        width = W() - 2 * PAD,
        buttons = rows,
        zero_sep = true,
        show_parent = self,
    }
end

-- Header: always-visible stats --------------------------------------------

function RelicScreen:header()
    local s = self.state
    local now = os.time()
    Game.buffTotal(s, "", now)  -- drops expired buffs before counting them
    local px = C.px
    local cw = W() - 2 * PAD
    -- status lines: where on the route, plugin version, last phone pull
    local st = Game.currentStage(s)
    local where = string.format("STAGE %d/%d // TO %s  %.1f KM", st, #Game.STAGE_KM,
        C.upper(Game.STAGE_NAMES[st] or "?"), s.route.km)
    local pulled
    -- read-only copy, never written, so it can't overwrite the inbox's own saves
    local ok, store = pcall(LuaSettings.open, LuaSettings, DataStorage:getSettingsDir() .. "/relic_inbox.lua")
    if ok and store then pulled = store:readSetting("last_pull") end
    local link = "LINK --"
    if pulled and pulled > 0 then
        link = "LINK " .. os.date(os.date("%Y%m%d", pulled) == os.date("%Y%m%d", now) and "%H:%M" or "%d %b %H:%M", pulled):upper()
    end
    local sys = string.format("SYS %s   %s", tostring(RUNNING_VERSION or "?"), link)
    local bars = {
        { "XP", s.xp, Game.xpToNext(s.level), string.format("%d/%d", s.xp, Game.xpToNext(s.level)) },
        { "CHARGE", s.charge, Game.maxCharge(s.level, s), string.format("%d/%d", s.charge, Game.maxCharge(s.level, s)) },
        -- HP in place of Integrity (Mike, 2026-10-08); Integrity moved to the Status tab
        { "HP", s.hp, Game.maxHp(s.level, s), string.format("%d/%d", s.hp, Game.maxHp(s.level, s)) },
    }
    local extra = string.format("STREAK %02d   SHIELDS %02d   GOLD %d", s.streak, s.shields, math.floor(Game.goldBalance(s)))
    if #(s.buffs or {}) > 0 then extra = extra .. "   BUFFS " .. #s.buffs end
    local line = ">> " .. C.upper(Game.companionLine(s, now))
    local H = px(208)
    return C.Canvas:new{ w = cw, h = H, draw = function(_, bb, x, y)
        local cx = x
        for ch in ("RELIC"):gmatch(".") do
            cx = cx + C.put(bb, C.text(ch, "bold", 34), cx, y, px(44)) + px(8)
        end
        C.put(bb, C.text(where, "mono", 14, C.TXT, cw - px(172)), x + px(172), y + px(3), px(19))
        C.put(bb, C.text(sys, "mono", 14, C.TXT), x + px(172), y + px(23), px(19))
        bb:paintRect(x, y + px(52), cw, 1, Blitbuffer.Color8(C.DIM))
        local by = y + px(60)
        for _, b in ipairs(bars) do
            C.put(bb, C.text(b[1], "bold", 15), x, by, px(22))
            local n = 20
            local filled = b[3] > 0 and math.floor(n * math.min(b[2], b[3]) / b[3] + 0.5) or 0
            C.segments(bb, x + px(132), by + px(6), px(430), px(10), n, filled, px(3))
            C.put(bb, C.text(b[4], "mono", 15), x + px(578), by, px(22))
            by = by + px(24)
        end
        local lw = C.put(bb, C.text("LV " .. s.level .. "  " .. Game.RANKS[Game.rankIndex(s.level)].abbr, "bold", 15, C.TXT), x, by + px(2), px(22))
        C.put(bb, C.text(extra, "mono", 15, C.TXT), x + math.max(px(62), lw + px(16)), by + px(2), px(22))
        local ly = by + px(30)
        C.chamfer(bb, x, ly, cw, px(32), px(8), { false, false, true, false }, C.PANEL, C.DIM, 1)
        C.put(bb, C.text(line, "mono", 15, C.TXT, cw - px(24)), x + px(12), ly, px(32))
    end }
end

-- Tabs -----------------------------------------------------------------------

function RelicScreen:nav()
    local tabs = { { "quests", "QUESTS" }, { "practice", "PRACTICE" }, { "bake", "BAKE" }, { "explore", "MAP" },
        { "status", "STATUS" }, { "menu", "MENU" } }
    local cw = W() - 2 * PAD
    local sp = C.px(6)
    local tw = math.floor((cw - sp * (#tabs - 1)) / #tabs)
    local h = C.px(56)
    local group = HorizontalGroup:new{}
    for i, t in ipairs(tabs) do
        local id, label = t[1], t[2]
        local active = self.tab == id
        table.insert(group, C.Canvas:new{ w = tw, h = h,
            draw = function(_, bb, x, y)
                C.slant(bb, x, y, tw, h, C.px(8), active and C.LINE or C.PANEL, active and C.LINE or C.DIM)
                local tx = C.text(label, "bold", #label < 8 and 15 or 13, active and C.BG or C.TXT)
                local w = tx:getSize().w
                C.put(bb, tx, x + math.floor((tw - w) / 2), y, h)
            end,
            on_tap = function()
                if id == "menu" then return self:exitMenu() end
                self.tab, self.page, self.detail_id, self.gear_view, self.inv_view = id, 1, nil, nil, nil
                self.quest_all, self.moving, self.records_view, self.move_mode, self.pick_id = nil, nil, nil, nil, nil
                self:render("flashui")
            end })
        if i < #tabs then table.insert(group, HorizontalSpan:new{ width = sp }) end
    end
    return VerticalGroup:new{ align = "left",
        C.Canvas:new{ w = cw, h = C.px(8), draw = function(_, bb, x, y) bb:paintRect(x, y, cw, 1, Blitbuffer.Color8(C.DIM)) end },
        group }
end

-- Paused: the whole screen is one notice and RESUME; nothing else works until then.
function RelicScreen:renderPaused(refresh)
    local p = self.state.paused
    local function ctext(str, size, bold)
        return TextBoxWidget:new{ text = str, face = (bface(bold, size)), width = W() - 2 * PAD,
            bold = bold, alignment = "center" }
    end
    local since = os.date("%A %d %B", p.since)
    local days = math.floor((os.time() - p.since) / 86400)
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = PAD,
        width = Screen:getWidth(), height = Screen:getHeight(),
        VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = math.floor(Screen:getHeight() * 0.28) },
            ctext("RELIC IS PAUSED", 28, true),
            gap(),
            ctext("Since " .. since .. (days > 0 and string.format(" (%d day%s)", days, days == 1 and "" or "s") or ""), 18),
            gap(PAD / 2),
            ctext("Nothing counts while paused: no missed days,\nno streak change, no regen, no steps.", 16),
            gap(PAD * 3),
            self:buttons({
                { { text = "RESUME", callback = function()
                    UIManager:show(ConfirmBox:new{ text = "Resume Relic now?", ok_text = "Resume",
                        ok_callback = function()
                            local _, d = Game.resume(self.state, os.time())
                            self:save(); self:render("full")
                            self:notify(d and d > 0 and ("Welcome back. " .. d .. " paused day" .. (d == 1 and "" or "s") .. " skipped.") or "Resumed.")
                        end })
                end } },
                { { text = "KOReader (menus and settings)", callback = function() self:onClose() end } },
            }),
        },
    }
    self:save()
    UIManager:setDirty(self, refresh or "ui")
end

function RelicScreen:exitMenu()
    local dialog
    dialog = PinnedDialog:new{
        title = "Menu",
        buttons = {
            { { text = "Pause Relic (trip, break)", callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = "Pause Relic?\n\nEverything stops until you tap RESUME: no missed Daily Directives, streak held, no regen, steps don't count, nothing usable.",
                    ok_text = "Pause",
                    ok_callback = function()
                        Game.pause(self.state, os.time()); self:save(); self:render("full")
                    end,
                })
            end } },
            { { text = "Theme", callback = function()
                UIManager:close(dialog); self:themeMenu()
            end } },
            { { text = "Repeating quests", callback = function()
                UIManager:close(dialog); self:recurringDialog()
            end } },
            { { text = "Pull quests from phone", callback = function()
                UIManager:close(dialog); if Relic_ref then Relic_ref:pullInbox(true) end
            end } },
            { { text = "KOReader (menus and settings)", callback = function()
                UIManager:close(dialog); self:onClose()
            end } },
            { { text = "Kindle home screen", callback = function()
                UIManager:close(dialog); self:save()
                UIManager:broadcastEvent(Event:new("Exit"))
            end } },
            { { text = "Cancel", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

-- QUESTS tab ------------------------------------------------------------------

local TIER_STARS = { minor = 1, standard = 2, major = 3, epic = 4 }  -- stars out of 4 (Mike, 2026-10-07)

-- Short flags shown after a quest title (console look: capitals, mono).
function RelicScreen:questFlags(q)
    local f = {}
    if q.id == self.state.daily_id then f[#f + 1] = "DAILY" end
    if q.main then f[#f + 1] = "MAIN" end
    if q.waiting then f[#f + 1] = "WAITING" end
    local due = Game.dueText(q, os.time())
    if due then f[#f + 1] = C.upper(due) end
    if q.out then f[#f + 1] = "OUT" end
    if q.dread then f[#f + 1] = "DREAD" end
    if q.rep then f[#f + 1] = "REPEATS" end
    local done, n = Game.stepProgress(q)
    local nxt = Game.nextStep(q)
    if n > 0 then f[#f + 1] = done .. "/" .. n .. (nxt and (" > " .. C.upper(nxt)) or "") end
    return table.concat(f, "  ")
end

function RelicScreen:questRow(q, w, h)
    local px = C.px
    local heavy = q.tier == "major" or q.tier == "epic"
    local title = C.upper(q.title)
    local flags = self:questFlags(q)
    local picked = self.move_mode and self.pick_id == q.id
    local TXT = picked and C.BG or C.TXT
    return C.Canvas:new{ w = w, h = h,
        draw = function(_, bb, x, y)
            C.chamfer(bb, x, y, w, h, px(10), { true, false, true, false }, picked and C.LINE or C.PANEL, picked and C.LINE or C.DIM, 1)
            bb:paintRect(x, y + px(10), px(5), h - px(20), Blitbuffer.Color8(heavy and C.LINE or C.MID))
            -- tier as stars out of 4, filled from the left
            local n = TIER_STARS[q.tier] or 0
            local stars = C.text(("★"):rep(n) .. ("☆"):rep(4 - n), "bold", 22, TXT)
            local sw = stars:getSize().w
            local tagx = x + w - px(14) - sw
            C.put(bb, stars, tagx, y, h)
            -- title, then flags in what room is left
            local tx = x + px(18)
            local avail = tagx - px(12) - tx
            local title_max = flags ~= "" and math.floor(avail * 0.66) or avail
            local tcol = picked and C.BG or (q.waiting and C.MID or C.TXT)
            local tw = C.put(bb, C.text(title, "bold", 19, tcol, title_max), tx, y, h)
            if flags ~= "" then
                local fx = tx + tw + px(12)
                if tagx - px(12) - fx > px(30) then
                    C.put(bb, C.text(flags, "mono", 14, picked and C.BG or C.LINE, tagx - px(12) - fx), fx, y + px(2), h)
                end
            end
        end,
        on_tap = function()
            if self.move_mode then self.pick_id = q.id; return self:render() end
            self.detail_id = q.id; self.step_page = 1; self:render()
        end,
        on_hold = function() if not self.move_mode then self:questMenu(q) end end,
    }
end

-- Move mode (Mike, 2026-10-22): MOVE, tap a quest to pick it, then TOP / UP / DOWN; DONE ends.
function RelicScreen:startMove(pick_id)
    self.move_mode, self.pick_id = true, pick_id
    self.detail_id, self.quest_all, self.moving = nil, nil, nil
    self.tab = "quests"
    if pick_id then self:followPick() end
    self:render("flashui")
end

-- show the page the picked quest is on
function RelicScreen:followPick()
    for i, q in ipairs(Game.orderedQuests(self.state, os.time())) do
        if q.id == self.pick_id then self.page = math.ceil(i / QUESTS_PER_PAGE) end
    end
end

function RelicScreen:nudge(dir)
    if not self.pick_id then return end
    local ok, why = Game.nudgeQuest(self.state, self.pick_id, dir, os.time())
    if ok then self:save(); self:followPick() end
    self:render()
    if not ok and why then self:notify(why) end
end

function RelicScreen:questsBody()
    local s = self.state
    local px = C.px
    local cw = W() - 2 * PAD

    -- Daily Directive slot
    local label, mark
    local dq = s.daily_id and Game.findQuest(s, s.daily_id)
    if s.daily_done then label, mark = "COMPLETE", "[ OK ]"
    elseif dq then label, mark = C.upper(dq.title), "[ >> ]"
    else label, mark = "UNASSIGNED  -  HOLD A QUEST TO SET", "[ -- ]" end
    if self.move_mode then
        label = self.pick_id and "TOP / ARROWS MOVE THE DARK ONE" or "MOVE: TAP THE QUEST TO MOVE"
    end
    local daily = C.Canvas:new{ w = cw, h = px(56),
        draw = function(_, bb, x, y)
            C.brackets(bb, x, y, cw, px(56), px(14), px(3))
            C.put(bb, C.text("DAILY DIRECTIVE", "bold", 14, C.LINE), x + px(16), y + px(4), px(18))
            C.put(bb, C.text(label, "bold", 19, C.TXT, cw - px(130)), x + px(16), y + px(22), px(28))
            local m = C.text(mark, "mono", 16, C.LINE)
            C.put(bb, m, x + cw - px(16) - m:getSize().w, y, px(56))
        end,
        on_tap = function()
            if s.daily_id and not s.daily_done then self.detail_id = s.daily_id; self.step_page = 1; self:render() end
        end,
    }

    local list = VerticalGroup:new{ align = "left", daily, gap(px(10)) }
    -- Quest rows (paged): overdue first, then your order, waiting last.
    local ordered = Game.orderedQuests(s, os.time())
    self.page = math.max(1, math.min(self.page, math.ceil(#ordered / QUESTS_PER_PAGE)))
    local start = (self.page - 1) * QUESTS_PER_PAGE + 1
    local rh, rgap = px(52), px(6)
    for i = start, start + QUESTS_PER_PAGE - 1 do
        local q = ordered[i]
        if q then table.insert(list, self:questRow(q, cw, rh))
        else table.insert(list, VerticalSpan:new{ width = rh }) end
        table.insert(list, gap(rgap))
    end

    -- pager: < + ADD QUEST  MOVE >   (move mode: < TOP UP DOWN DONE >)
    local pages = math.max(1, math.ceil(#ordered / QUESTS_PER_PAGE))
    local sp = px(10)
    local small = math.floor((cw - 3 * sp) * 0.18)
    local big = math.floor((cw - 3 * sp - 2 * small) / 2)
    local function btn(w, txt, kind, enabled, cb)
        local BH = px(44)
        return C.Canvas:new{ w = w, h = BH,
            draw = function(_, bb, x, y)
                local filled = kind == "primary"
                C.chamfer(bb, x, y, w, BH, px(10), { false, true, false, true }, filled and C.LINE or C.BG,
                    enabled and C.LINE or C.DIM, 2)
                local fg = filled and C.BG or (enabled and C.TXT or C.DIM)
                if txt == "UP" or txt == "DOWN" then
                    C.tri(bb, x + math.floor(w / 2), y + math.floor(BH / 2), px(16), txt == "UP", fg)
                else
                    local t = C.text(txt, "bold", 18, fg)
                    C.put(bb, t, x + math.floor((w - t:getSize().w) / 2), y, BH)
                end
            end,
            on_tap = enabled and cb or nil,
        }
    end
    local prev = function() self.page = self.page - 1; self:render() end
    local nxt = function() self.page = self.page + 1; self:render() end
    local pager
    if self.move_mode then
        local sm = math.floor((cw - 5 * sp) * 0.11)
        local mid = math.floor((cw - 5 * sp - 2 * sm) / 4)
        local has = self.pick_id ~= nil
        pager = HorizontalGroup:new{
            btn(sm, "<", nil, self.page > 1, prev), HorizontalSpan:new{ width = sp },
            btn(mid, "TOP", nil, has, function() self:nudge("top") end), HorizontalSpan:new{ width = sp },
            btn(mid, "UP", nil, has, function() self:nudge("up") end), HorizontalSpan:new{ width = sp },
            btn(mid, "DOWN", nil, has, function() self:nudge("down") end), HorizontalSpan:new{ width = sp },
            btn(mid, "DONE", "primary", true, function() self.move_mode, self.pick_id = nil, nil; self:render("flashui") end),
            HorizontalSpan:new{ width = sp },
            btn(sm, ">", nil, self.page < pages, nxt),
        }
    else
        pager = HorizontalGroup:new{
            btn(small, "<", nil, self.page > 1, prev),
            HorizontalSpan:new{ width = sp },
            btn(big, "+ ADD QUEST", "primary", true, function() self:addQuestDialog() end),
            HorizontalSpan:new{ width = sp },
            btn(big, "MOVE", nil, #ordered > 1, function() self:startMove(nil) end),
            HorizontalSpan:new{ width = sp },
            btn(small, ">", nil, self.page < pages, nxt),
        }
    end
    return list, pager
end

-- LCARS theme (Quests page only, 2026-10-19) -----------------------------------------------
-- Picked under MENU > Theme; kept in KOReader's settings, not the save. Other tabs, the quest
-- detail and ALL / MOVE views keep the console look.

local THEME_KEY = "relic_theme"
local THEMES = { { "console", "Console" }, { "lcars", "Beam Me Up" } }

local function currentTheme()
    local ok, v = pcall(function() return G_reader_settings:readSetting(THEME_KEY) end)
    return (ok and v) or "console"
end

local function setTheme(id)
    pcall(function() G_reader_settings:saveSetting(THEME_KEY, id); G_reader_settings:flush() end)
end

function RelicScreen:themeMenu()
    local dialog
    local rows = {}
    local cur = currentTheme()
    for _, t in ipairs(THEMES) do
        table.insert(rows, { { text = (t[1] == cur and "> " or "") .. t[2], callback = function()
            UIManager:close(dialog); setTheme(t[1]); self:render("full")
        end } })
    end
    table.insert(rows, { { text = "Cancel", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = "Theme", buttons = rows }
    UIManager:show(dialog)
end

-- ButtonTable rows drawn as LCARS pills (same row format: text / text_func, callback,
-- hold_callback, enabled, align). Used while an LCARS frame builds a page body.
function RelicScreen:lcarsButtons(rows)
    local px = C.px
    local cw = W() - 2 * PAD
    local h, gap = px(50), px(6)
    local tones = { 204, 153 }
    local group = VerticalGroup:new{ align = "left" }
    for ri, row in ipairs(rows) do
        local n = #row
        local hg = HorizontalGroup:new{}
        local bw = math.floor((cw - gap * (n - 1)) / n)
        for bi, b in ipairs(row) do
            local w = bi == n and (cw - (bw + gap) * (n - 1)) or bw
            local label = b.text_func and b.text_func() or b.text or ""
            local enabled = b.enabled ~= false
            local tone = enabled and tones[(ri + bi) % 2 + 1] or 221
            local r = math.floor(h / 2)
            local radii = { bi == 1 and r or 0, bi == n and r or 0, bi == n and r or 0, bi == 1 and r or 0 }
            local left = b.align == "left"
            table.insert(hg, C.Canvas:new{ w = w, h = h,
                draw = function(_, bb, x, y)
                    C.round(bb, x, y, w, h, radii, tone)
                    local padl = (bi == 1) and r or px(12)
                    local padr = (bi == n) and r or px(12)
                    local t = C.text(C.upper(label), "lcars", 20, enabled and 0 or 102, w - padl - padr)
                    local tw = t:getSize().w
                    C.put(bb, t, left and (x + padl) or (x + w - padr - tw), y, h)
                end,
                on_tap = enabled and b.callback or nil,
                on_hold = enabled and b.hold_callback or nil })
            if bi < n then table.insert(hg, HorizontalSpan:new{ width = gap }) end
        end
        table.insert(group, hg)
        if ri < #rows then table.insert(group, VerticalSpan:new{ width = gap }) end
    end
    return group
end

-- gray levels (0 black .. 255 white), on the PW2's 16 steps
local L = { BG = 255, INK = 0, A1 = 153, A2 = 204, A3 = 119, HEAVY = 51, LIGHT = 170, DIM = 221, PANEL = 238, MID = 102 }

function RelicScreen:renderLcars(refresh)
    local s = self.state
    local now = os.time()
    Game.buffTotal(s, "", now)
    local px = C.px
    local cw, ch = W() - 2 * PAD, Screen:getHeight() - 2 * PAD
    local col = Blitbuffer.Color8
    local layers = { dimen = Geom:new{ w = cw, h = ch }, allow_mirroring = false }

    -- text right-aligned, sitting on the bottom of a box
    local function putBR(bb, tw, x, y, w, h, padr, padb)
        local sz = tw:getSize()
        tw:paintTo(bb, x + w - padr - sz.w, y + h - padb - sz.h)
        tw:free()
    end

    -- header data (same as the console header)
    local st = Game.currentStage(s)
    local where = string.format("STAGE %02d/%d // TO %s", st, #Game.STAGE_KM, C.upper(Game.STAGE_NAMES[st] or "?"))
    local pulled
    local ok, store = pcall(LuaSettings.open, LuaSettings, DataStorage:getSettingsDir() .. "/relic_inbox.lua")
    if ok and store then pulled = store:readSetting("last_pull") end
    local link = "LINK --"
    if pulled and pulled > 0 then
        link = "LINK " .. os.date(os.date("%Y%m%d", pulled) == os.date("%Y%m%d", now) and "%H:%M" or "%d %b %H:%M", pulled):upper()
    end
    local sys = string.format("%.1f KM   SYS %s   %s", s.route.km, tostring(RUNNING_VERSION or "?"), link)
    if #(s.buffs or {}) > 0 then sys = sys .. "   BUFFS " .. #s.buffs end
    local bars = {
        { "XP", s.xp, Game.xpToNext(s.level) },
        { "CHARGE", s.charge, Game.maxCharge(s.level, s) },
        { "HP", s.hp, Game.maxHp(s.level, s) },
    }
    local line = ">> " .. C.upper(Game.companionLine(s, now))
    local _, reg = Game.currentRegion(s)
    local region = reg and C.upper(reg.name) or ""

    -- what goes in the frame: the LCARS quest list, or the tab's own page drawn at the frame's width
    local quest_mode = self.tab == "quests" and not self.detail_id and not self.quest_all
    local frame_label, body, foot
    if not quest_mode then
        local names = { quests = "QUESTS", practice = "PRACTICE", bake = "BAKE", explore = "MAP", status = "STATUS" }
        frame_label = names[self.tab] or C.upper(self.tab)
        if self.tab == "quests" then frame_label = self.detail_id and "QUEST DETAIL" or "ALL QUESTS // MOVE" end
        if self.tab == "status" and self.gear_view then frame_label = "STATUS // GEAR" end
        if self.tab == "status" and self.inv_view then frame_label = "STATUS // INVENTORY" end
        if self.tab == "status" and self.records_view then frame_label = "STATUS // RECORDS" end
        local frame_w = W() - 2 * PAD - C.px(148) + 2 * PAD
        local function build(shrink)
        W_OVERRIDE, LCARS_BUTTONS = frame_w - (shrink or 0), true
        local okb, res, res2 = pcall(self.pageBody, self)
        W_OVERRIDE, LCARS_BUTTONS = nil, false
        if not okb then error(res) end
        return res, res2
        end
        -- the page's buttons sit pinned at the bottom of the frame; the page above them scrolls
        -- when it's too tall (Mike, 2026-10-22)
        local first
        first, foot = build()
        local fh = foot and (foot:getSize().h + px(8)) or 0
        body = self:fitBody(first, build, frame_w - 2 * PAD, ch - px(252 + 8 + 30) - fh)
    end

    -- quests on this page
    local ordered = Game.orderedQuests(s, now)
    local pages = math.max(1, math.ceil(#ordered / QUESTS_PER_PAGE))
    self.page = math.max(1, math.min(self.page or 1, pages))
    local start = (self.page - 1) * QUESTS_PER_PAGE + 1
    local open_n = #ordered

    local TOP_H, GAP = px(252), px(8)
    local B0 = TOP_H + GAP          -- top of the bottom frame
    local COLW, CX = px(132), px(148) -- side column width, content x
    local CWID = cw - CX

    -- background: both frames, header text, labels
    table.insert(layers, C.Canvas:new{ w = cw, h = ch, draw = function(_, bb, x, y)
        bb:paintRect(x, y, cw, ch, col(L.BG))
        -- top frame
        C.rect(bb, x, y, COLW, px(92), L.A3)
        local rk = Game.RANKS[Game.rankIndex(s.level)]
        local idw = C.insigniaWidth(rk, px(14))
        C.insignia(bb, x + COLW - px(12) - idw, y + px(12), rk, px(14), L.BG, L.A3)
        putBR(bb, C.text("LV " .. s.level, "lcars", 30, L.BG), x, y, COLW, px(92), px(12), px(8))
        C.rect(bb, x, y + px(98), COLW, px(52), L.A2)
        putBR(bb, C.text(string.format("STREAK %02d", s.streak), "lcars", 20, L.INK), x, y + px(98), COLW, px(52), px(12), px(6))
        C.round(bb, x, y + px(156), cw, TOP_H - px(156), { 0, 0, 0, px(64) }, L.A1)
        C.round(bb, x + COLW, y + px(156), cw - COLW, TOP_H - px(156) - px(24), { 0, 0, 0, px(32) }, L.BG)
        putBR(bb, C.text(string.format("SHIELDS %02d", s.shields), "lcars", 20, L.INK), x, y + px(156), COLW, px(72), px(12), px(6))
        local sy = y + TOP_H - px(24)
        C.rect(bb, x + px(330), sy, px(6), px(24), L.BG)
        C.rect(bb, x + px(520), sy, px(6), px(24), L.BG)
        C.rect(bb, x + px(526), sy, px(120), px(24), L.A2)
        -- gold with the other stats (Mike, 2026-10-22)
        local gt = C.text("GOLD " .. math.floor(Game.goldBalance(s)), "lcars", 17, L.INK, px(108))
        C.put(bb, gt, x + px(646) - px(6) - gt:getSize().w, sy, px(24))
        C.rect(bb, x + px(646), sy, px(6), px(24), L.BG)
        if region ~= "" then
            local t = C.text(region, "lcars", 17, L.INK, px(170))
            local w = t:getSize().w
            C.rect(bb, x + px(340), sy, w + px(16), px(24), L.BG)
            C.put(bb, t, x + px(348), sy, px(24))
        end
        -- header text
        local title = C.text("RELIC", "lcars", 64, L.INK)
        local tw = title:getSize().w
        C.put(bb, title, x + cw - tw, y, px(64))
        C.put(bb, C.text(where, "mono", 15, L.INK, CWID - tw - px(12)), x + CX, y + px(6), px(20))
        C.put(bb, C.text(sys, "mono", 15, L.INK, CWID - tw - px(12)), x + CX, y + px(26), px(20))
        local by = y + px(72)
        for _, b in ipairs(bars) do
            C.put(bb, C.text(b[1], "lcars", 19, L.INK), x + CX, by, px(24))
            local n, gap = 20, px(3)
            local sx, sw = x + CX + px(92), cw - CX - px(92) - px(94)
            local filled = b[3] > 0 and math.floor(n * math.min(b[2], b[3]) / b[3] + 0.5) or 0
            local segw = (sw - gap * (n - 1)) / n
            for i = 0, n - 1 do
                local xx = math.floor(sx + i * (segw + gap))
                local r = px(7)
                C.round(bb, xx, by + px(5), math.floor(segw), px(14),
                    { i == 0 and r or 0, i == n - 1 and r or 0, i == n - 1 and r or 0, i == 0 and r or 0 },
                    i < filled and L.INK or L.DIM)
            end
            local v = C.text(string.format("%d/%d", b[2], b[3]), "mono", 15, L.INK)
            C.put(bb, v, x + cw - v:getSize().w, by, px(24))
            by = by + px(26)
        end
        C.put(bb, C.text(line, "mono", 15, L.INK, CWID), x + CX, y + px(186), px(30))

        -- bottom frame
        local b0 = y + B0
        C.round(bb, x, b0, cw, px(96), { px(64), 0, 0, 0 }, L.A1)
        C.round(bb, x + COLW, b0 + px(24), cw - COLW, px(72), { px(32), 0, 0, 0 }, L.BG)
        C.rect(bb, x + px(400), b0, px(6), px(24), L.BG)
        C.rect(bb, x + px(600), b0, px(6), px(24), L.BG)
        C.round(bb, x + px(606), b0, cw - px(606), px(24), { 0, px(12), px(12), 0 }, L.A3)
        local lab = C.text(frame_label or string.format("QUEST LOG // %d OPEN // PAGE %d OF %d", open_n, self.page, pages), "lcars", 17, L.INK, px(234))
        C.rect(bb, x + px(150), b0, lab:getSize().w + px(16), px(24), L.BG)
        C.put(bb, lab, x + px(158), b0, px(24))
    end })

    local function add(w, ox, oy)
        w.overlap_offset = { ox, oy }
        table.insert(layers, w)
    end

    -- side tabs
    local tabs = { { "quests", "QUESTS", L.A1 }, { "practice", "PRACTICE", L.A2 }, { "bake", "BAKE", L.A3 },
        { "explore", "MAP", L.A2 }, { "status", "STATUS", L.A1 }, { "menu", "MENU", L.A3 } }
    for _, t in ipairs(tabs) do if t[1] == self.tab then t[3] = L.INK end end
    local navy, navh = B0 + px(102), ch - B0 - px(102)
    local tgap = px(6)
    local th = math.floor((navh - tgap * (#tabs - 1)) / #tabs)
    for i, t in ipairs(tabs) do
        local id, label, tone = t[1], t[2], t[3]
        local last = i == #tabs
        local h = last and (navh - (th + tgap) * (#tabs - 1)) or th
        add(C.Canvas:new{ w = COLW, h = h,
            draw = function(_, bb, x, y)
                C.round(bb, x, y, COLW, h, { 0, 0, 0, last and px(64) or 0 }, tone)
                local fg = (tone == L.INK or tone == L.A3) and L.BG or L.INK
                putBR(bb, C.text(label, "lcars", 21, fg), x, y, COLW, h, px(12), px(8))
            end,
            on_tap = function()
                if id == "menu" then return self:exitMenu() end
                self.tab, self.page, self.detail_id, self.gear_view, self.inv_view = id, 1, nil, nil, nil
                self.quest_all, self.moving, self.records_view, self.move_mode, self.pick_id = nil, nil, nil, nil, nil
                self:render("flashui")
            end }, 0, navy + (th + tgap) * (i - 1))
    end

    if not quest_mode then
        add(body, CX, B0 + px(30))
        if foot then add(foot, CX, ch - foot:getSize().h) end
    else
    -- Daily Directive
    local label, mark
    local dq = s.daily_id and Game.findQuest(s, s.daily_id)
    if s.daily_done then label, mark = "COMPLETE", "OK"
    elseif dq then label, mark = C.upper(dq.title), ">>"
    else label, mark = "UNASSIGNED - HOLD A QUEST TO SET", "--" end
    if self.move_mode then label = self.pick_id and "TOP / ARROWS MOVE THE DARK ONE" or "MOVE: TAP THE QUEST TO MOVE" end
    local DH = px(62)
    add(C.Canvas:new{ w = CWID, h = DH,
        draw = function(_, bb, x, y)
            local r = math.floor(DH / 2)
            C.round(bb, x, y, px(18), DH, { r, 0, 0, r }, L.INK)
            local lx = x + px(22)
            C.rect(bb, lx, y, px(112), DH, L.A2)
            local d1, d2 = C.text("DAILY", "lcars", 15, L.INK), C.text("DIRECTIVE", "lcars", 15, L.INK)
            local h1 = d1:getSize().h
            d1:paintTo(bb, lx + px(10), y + DH - px(6) - 2 * h1); d1:free()
            d2:paintTo(bb, lx + px(10), y + DH - px(6) - h1); d2:free()
            local mx = x + px(138)
            local ew = px(70)
            local mw = CWID - px(138) - ew
            C.rect(bb, mx, y, mw, px(3), L.A2)
            C.rect(bb, mx, y + DH - px(3), mw, px(3), L.A2)
            C.put(bb, C.text(label, "lcars", 25, L.INK, mw - px(28)), mx + px(14), y, DH)
            C.round(bb, x + CWID - ew, y, ew, DH, { 0, r, r, 0 }, L.INK)
            local m = C.text(mark, "mono", 16, L.BG)
            C.put(bb, m, x + CWID - ew + math.floor((ew - m:getSize().w) / 2), y, DH)
        end,
        on_tap = function()
            if s.daily_id and not s.daily_done then self.detail_id = s.daily_id; self.step_page = 1; self:render() end
        end }, CX, B0 + px(30))

    -- quest rows
    local RH, RG = px(50), px(5)
    local ry = B0 + px(104)
    for i = start, start + QUESTS_PER_PAGE - 1 do
        local q = ordered[i]
        if q then
            local heavy = q.tier == "major" or q.tier == "epic"
            local title = C.upper(q.title)
            local flags = self:questFlags(q)
            local picked = self.move_mode and self.pick_id == q.id
            local PANEL = picked and L.INK or L.PANEL
            local INK = picked and L.BG or L.INK
            add(C.Canvas:new{ w = CWID, h = RH,
                draw = function(_, bb, x, y)
                    local r = math.floor(RH / 2)
                    C.round(bb, x, y, px(26), RH, { r, 0, 0, r }, q.waiting and L.DIM or (heavy and L.HEAVY or L.LIGHT))
                    local bx = x + px(30)
                    local bw = CWID - px(30)
                    C.round(bb, bx, y, bw, RH, { 0, r, r, 0 }, PANEL)
                    -- tier as rank pips out of 4: solid for the tier, hollow for the rest (Mike, 2026-10-19)
                    local n = TIER_STARS[q.tier] or 0
                    local d, pg, ring = px(14), px(6), math.max(2, px(2))
                    local sw = 4 * d + 3 * pg
                    local tagx = bx + bw - px(20) - sw
                    local pyy = y + math.floor((RH - d) / 2)
                    for k = 0, 3 do
                        local cx = tagx + k * (d + pg)
                        local rr = math.floor(d / 2)
                        C.round(bb, cx, pyy, d, d, { rr, rr, rr, rr }, INK)
                        if k >= n then
                            local ir = rr - ring
                            C.round(bb, cx + ring, pyy + ring, d - 2 * ring, d - 2 * ring, { ir, ir, ir, ir }, PANEL)
                        end
                    end
                    local tx = bx + px(12)
                    local avail = tagx - px(12) - tx
                    local title_max = flags ~= "" and math.floor(avail * 0.66) or avail
                    local tw = C.put(bb, C.text(title, "lcars", 23, picked and L.BG or (q.waiting and L.MID or L.INK), title_max), tx, y, RH)
                    if flags ~= "" then
                        local fx = tx + tw + px(12)
                        if tagx - px(12) - fx > px(30) then
                            C.put(bb, C.text(flags, "mono", 14, INK, tagx - px(12) - fx), fx, y + px(1), RH)
                        end
                    end
                end,
                on_tap = function()
                    if self.move_mode then self.pick_id = q.id; return self:render() end
                    self.detail_id = q.id; self.step_page = 1; self:render()
                end,
                on_hold = function() if not self.move_mode then self:questMenu(q) end end,
            }, CX, ry)
        end
        ry = ry + RH + RG
    end

    -- pager
    local PH = px(50)
    local py = ch - PH
    local sp, small = px(6), px(64)
    local big = math.floor((CWID - 3 * sp - 2 * small) / 2)
    local function btn(w, txt, fill, fg, radii, enabled, cb, right)
        return C.Canvas:new{ w = w, h = PH,
            draw = function(_, bb, x, y)
                C.round(bb, x, y, w, PH, radii, fill)
                local f = enabled and fg or L.MID
                if txt == "UP" or txt == "DOWN" then
                    C.tri(bb, x + math.floor(w / 2), y + math.floor(PH / 2), px(16), txt == "UP", f)
                    return
                end
                local t = C.text(txt, "lcars", right and 22 or 24, f)
                local tw = t:getSize().w
                C.put(bb, t, right and (x + w - px(14) - tw) or (x + math.floor((w - tw) / 2)), y, PH)
            end,
            on_tap = enabled and cb or nil }
    end
    local r = math.floor(PH / 2)
    local bx = CX
    add(btn(small, "<", L.DIM, L.INK, { r, 0, 0, r }, self.page > 1, function() self.page = self.page - 1; self:render() end), bx, py)
    bx = bx + small + sp
    if self.move_mode then
        -- move mode (Mike, 2026-10-22): TOP / UP / DOWN / DONE between the page arrows
        local has = self.pick_id ~= nil
        local mid = math.floor((CWID - 5 * sp - 2 * small) / 4)
        add(btn(mid, "TOP", L.A2, L.INK, { 0, 0, 0, 0 }, has, function() self:nudge("top") end), bx, py)
        bx = bx + mid + sp
        add(btn(mid, "UP", L.A2, L.INK, { 0, 0, 0, 0 }, has, function() self:nudge("up") end), bx, py)
        bx = bx + mid + sp
        add(btn(mid, "DOWN", L.A2, L.INK, { 0, 0, 0, 0 }, has, function() self:nudge("down") end), bx, py)
        bx = bx + mid + sp
        add(btn(mid, "DONE", L.INK, L.BG, { 0, 0, 0, 0 }, true,
            function() self.move_mode, self.pick_id = nil, nil; self:render("flashui") end), bx, py)
        bx = bx + mid + sp
    else
        add(btn(big, "+ ADD QUEST", L.INK, L.BG, { 0, 0, 0, 0 }, true, function() self:addQuestDialog() end, true), bx, py)
        bx = bx + big + sp
        add(btn(big, "MOVE", L.A2, L.INK, { 0, 0, 0, 0 }, open_n > 1, function() self:startMove(nil) end, true), bx, py)
        bx = bx + big + sp
    end
    add(btn(cw - bx, ">", L.DIM, L.INK, { 0, r, r, 0 }, self.page < pages, function() self.page = self.page + 1; self:render() end), bx, py)
    end

    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = PAD,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        OverlapGroup:new(layers),
    }
    self:save()
    UIManager:setDirty(self, refresh or "ui")
end

function RelicScreen:practiceBody()
    local s = self.state
    local now = os.time()
    local p = Game.practiceDay(s, now)
    local rows = {}
    -- TRAIN
    local left, slots = Game.trainLeft(s, now)
    local grit = string.format("Grit %d/%d", s.grit or 0, Game.gritCap(s))
    table.insert(rows, { {
        text = left > 0
            and string.format("TRAIN: %d pushups, squats or dumbbells  (%d of %d left)  %s", Game.TRAIN_REPS, left, slots, grit)
            or string.format("TRAIN: done for today (%d of %d)  %s", slots, slots, grit),
        align = "left",
        callback = function()   -- always tappable: the day may have turned since this was drawn
            if Game.trainLeft(s, os.time()) > 0 then self:trainDialog() else self:render(); self:notify("No training left today.") end
        end,
    } })
    -- running session, or start buttons (same rows either way, so nothing shifts under a tap)
    local sleft, se = Game.sessionLeft(s, now)
    local function done()
        local msg, why = Game.finishSession(s, os.time())
        self:save(); self:render("flashui"); self:notify(msg or why)
    end
    local function stop()
        UIManager:show(ConfirmBox:new{ text = "Stop this session? It won't count.", ok_text = "Stop",
            ok_callback = function() Game.stopSession(s); self:save(); self:render() end })
    end
    if se then
        local what = se.kind == "meditate" and ("Meditating " .. se.min .. " min")
            or ("Pomodoro on " .. ((Game.findQuest(s, se.quest) or {}).title or "?"))
        table.insert(rows, { { text = what .. (sleft > 0 and string.format(": %d min left", math.ceil(sleft / 60)) or ": time's up"),
            align = "left", callback = function()
                self:openMeditate()  -- both open the full-screen countdown (Pomodoro too since v38)
            end } })
        table.insert(rows, { { text = "DONE", callback = done }, { text = "STOP", callback = stop } })
    else
        local med = { }
        for _, m in ipairs(Game.MED_OPTIONS) do
            table.insert(med, { text = "MEDITATE " .. m, callback = function()
                local ok, why = Game.startMeditate(s, m, os.time())
                self:save(); self:render(); if not ok then self:notify(why) else self:openMeditate() end
            end })
        end
        table.insert(rows, med)
        table.insert(rows, { { text = "POMODORO: " .. Game.POMO_MIN .. " min on a quest", callback = function() self:pickPomodoro() end } })
    end
    -- time log
    local lines = {}
    for _, tier in ipairs({ "minor", "standard", "major", "epic" }) do
        local tl = s.timelog and s.timelog[tier]
        if tl and tl.n > 0 then table.insert(lines, string.format("%s: %d quests, about %d min each", tier:gsub("^%l", string.upper), tl.n, math.floor(tl.min / tl.n + 0.5))) end
    end
    local focus = s.skills.focus
    return VerticalGroup:new{
        align = "left",
        text("Meditate and Pomodoro open a full-screen countdown. Tap the running session to open it again.", 16),
        gap(PAD / 2),
        self:buttons(rows),
        gap(),
        text(string.format("Today: meditated %d min (pays up to %d), %d Pomodoros.   Focus %s",
            p.med_min, Game.MED_DAILY_CAP, p.pomos, focus and ("rank " .. focus.rank) or "not yet found"), 18),
        gap(PAD / 2),
        text("TIME LOG (quests with Pomodoros)\n" .. (#lines > 0 and table.concat(lines, "\n") or "Nothing timed yet."), 18),
    }
end

-- Full-screen countdown for a running meditation or Pomodoro (closing it leaves the timer running).
function RelicScreen:openMeditate()
    local s = self.state
    Meditate.show{
        game = Game, state = s,
        on_close = function() self:render("flashui") end,
        on_done = function()
            local msg, why = Game.finishSession(s, os.time())
            self:save(); self:render("flashui"); self:notify(msg or why)
        end,
        on_stop = function() Game.stopSession(s); self:save(); self:render("flashui") end,
    }
end

function RelicScreen:pickPomodoro()
    local s = self.state
    local dialog
    local rows = {}
    for _, q in ipairs(s.quests) do
        table.insert(rows, { { text = q.title .. ((q.pomos or 0) > 0 and ("  (" .. q.pomos .. ")") or ""), align = "left", callback = function()
            UIManager:close(dialog)
            local ok, why = Game.startPomodoro(s, q.id, os.time())
            self:save(); self:render(); if not ok then self:notify(why) else self:openMeditate() end
        end } })
    end
    if #rows == 0 then table.insert(rows, { { text = "No open quests.", enabled = false } }) end
    table.insert(rows, { { text = "Cancel", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = "Pomodoro: which quest?", buttons = rows }
    UIManager:show(dialog)
end

function RelicScreen:trainDialog()
    local dialog
    local function go(kind)
        return function()
            UIManager:close(dialog)
            local msg, why = Game.train(self.state, kind, os.time())
            self:save()
            self:render()
            self:notify(msg or why)
        end
    end
    dialog = PinnedDialog:new{
        title = "TRAIN: " .. Game.TRAIN_REPS .. " reps. Which one did you do?",
        buttons = {
            { { text = "PUSHUPS", callback = go("pushups") }, { text = "SQUATS", callback = go("squats") } },
            { { text = "DUMBBELLS", callback = go("dumbbells") } },
            { { text = "Cancel", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function RelicScreen:confirmComplete(id)
    local q = Game.findQuest(self.state, id)
    if not q then return end
    UIManager:show(ConfirmBox:new{
        text = "Complete \"" .. q.title .. "\"?",
        ok_text = "Complete",
        ok_callback = function()
            local now = os.time()
            local msg, rec = Game.completeQuest(self.state, id, now)
            if rec then Chronicle.record(rec, now) end
            if self.detail_id == id then self.detail_id = nil end
            self:save()
            self:render()
            self:notify(msg)
        end,
    })
end

-- rows built with "cond and {...} or nil" leave holes; drop them (n = largest possible index)
local function compactRows(t, n)
    local out = {}
    for k = 1, n or table.maxn(t) do if t[k] then table.insert(out, t[k]) end end
    return out
end

function RelicScreen:questMenu(q)
    local dialog
    dialog = PinnedDialog:new{
        title = q.title,
        buttons = compactRows({
            { { text = "Rename", callback = function()
                UIManager:close(dialog)
                self:textDialog("Rename quest", q.title, function(t) q.title = t end)
            end } },
            { { text = "Size: " .. ((Game.tierByKey(q.tier) or {}).label or q.tier) .. "  (change)", callback = function()
                UIManager:close(dialog); self:sizeDialog(q)
            end } },
            { { text = "Move to top", callback = function()
                UIManager:close(dialog)
                local first = self.state.quests[1]
                if first and first.id ~= q.id then
                    local ok, why = Game.moveQuest(self.state, q.id, first.id, os.time())
                    if ok == false and why then self:notify(why) end
                end
                self:save(); self:render()
            end },
              { text = "Move (arrows)", callback = function()
                UIManager:close(dialog)
                self:startMove(q.id)
            end } },
            { { text = "Repeat: " .. (Game.repText(q.rep) or "off") .. "  (change)", callback = function()
                UIManager:close(dialog); self:repeatDialog(q)
            end } },
            { { text = "Set as Daily Directive", callback = function()
                UIManager:close(dialog)
                local ok, why = Game.setDaily(self.state, q.id)
                if not ok then self:notify(why) end
                self:save(); self:render()
            end } },
            { { text = "Skill: " .. self:tagLabel(q), callback = function()
                UIManager:close(dialog); self:tagDialog(q)
            end } },
            { { text = q.main and "Unmark Main Quest" or "Mark as Main Quest", callback = function()
                UIManager:close(dialog)
                q.main = (not q.main) or nil
                self:save(); self:render()
            end } },
            { { text = q.waiting and "Not waiting anymore" or "Waiting on someone", callback = function()
                UIManager:close(dialog)
                q.waiting = (not q.waiting) or nil
                self:save(); self:render()
            end } },
            { { text = "Due: " .. (Game.dueText(q, os.time()) or "none") .. "  (change)", callback = function()
                UIManager:close(dialog); self:dueDialog(q)
            end } },
            { { text = q.out and "Not out of the house" or "Out of the house", callback = function()
                UIManager:close(dialog)
                q.out = (not q.out) or nil
                self:save(); self:render()
            end } },
            { { text = q.dread and "Not dreading it" or "Dreading it (pays double)", callback = function()
                UIManager:close(dialog)
                q.dread = (not q.dread) or nil
                self:save(); self:render()
            end } },
            q.rep and { { text = "Skip this time (back " .. Game.nextRepDay(q.rep, os.time()):sub(6) .. ")", callback = function()
                UIManager:close(dialog)
                Chronicle.record(Game.chronicleEntry(q, "skipped", 0, self.state.daily_id == q.id), os.time())
                Game.skipRecurring(self.state, q.id, os.time())
                if self.detail_id == q.id then self.detail_id = nil end
                self:save(); self:render()
            end } } or nil,
            { { text = q.rep and "Delete (stops repeating)" or "Delete", callback = function()
                UIManager:close(dialog)
                Chronicle.record(Game.chronicleEntry(q, "deleted", q.paid or 0, self.state.daily_id == q.id), os.time())
                Game.deleteQuest(self.state, q.id, true)
                if self.detail_id == q.id then self.detail_id = nil end
                self:save(); self:render()
            end } },
            { { text = "Cancel", callback = function() UIManager:close(dialog) end } },
        }, 30),
    }
    UIManager:show(dialog)
end

-- Change a quest's size (tier). XP and gold follow the new size when it's finished.
function RelicScreen:sizeDialog(q)
    local dialog
    local rows = {}
    for _, t in ipairs(Game.TIERS) do
        table.insert(rows, { { text = (t.key == q.tier and "> " or "") .. t.label .. "  (" .. t.xp .. " XP)", callback = function()
            UIManager:close(dialog)
            Game.setTier(self.state, q.id, t.key)
            self:save(); self:render()
        end } })
    end
    table.insert(rows, { { text = "Cancel", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = "Size: " .. q.title, buttons = rows }
    UIManager:show(dialog)
end

-- Repeat (Mike, 2026-10-22): one copy only. A missed one stays on the list; a done one
-- comes back on its next day.
function RelicScreen:repeatDialog(q)
    local s = self.state
    local dialog
    local function set(rep)
        return function()
            UIManager:close(dialog)
            if rep == nil and q.rep then Game.stopRecurring(s, q.id) else Game.setRepeat(s, q.id, rep) end
            self:save(); self:render()
        end
    end
    dialog = PinnedDialog:new{
        title = "Repeat: " .. q.title,
        buttons = {
            { { text = "Every day", callback = set({ kind = "daily" }) }, { text = "Weekdays", callback = set({ kind = "weekdays" }) } },
            { { text = "Pick days of the week", callback = function() UIManager:close(dialog); self:repeatDaysDialog(q) end } },
            { { text = "Every N days", callback = function()
                UIManager:close(dialog)
                self:textDialog("Every how many days?", q.rep and q.rep.kind == "every" and tostring(q.rep.n) or "2", function(t)
                    local n = tonumber(t)
                    if not n or n < 1 or n > 365 or n ~= math.floor(n) then return self:notify("Use a whole number from 1 to 365.") end
                    Game.setRepeat(s, q.id, { kind = "every", n = n })
                end)
            end } },
            { { text = "Don't repeat", callback = set(nil) } },
            { { text = "Cancel", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

-- toggle Mon..Sun, then SAVE
function RelicScreen:repeatDaysDialog(q, picked)
    local s = self.state
    if not picked then
        picked = {}
        if q.rep and q.rep.kind == "days" then for w, on in pairs(q.rep.days) do picked[w] = on end end
    end
    local dialog
    local function toggle(w)
        return function()
            UIManager:close(dialog)
            picked[w] = (not picked[w]) or nil
            self:repeatDaysDialog(q, picked)
        end
    end
    local row1, row2 = {}, {}
    for i, w in ipairs({ 2, 3, 4, 5, 6, 7, 1 }) do
        local b = { text = (picked[w] and "[x] " or "") .. Game.WDAY_NAMES[w], callback = toggle(w) }
        table.insert(i <= 4 and row1 or row2, b)
    end
    dialog = PinnedDialog:new{
        title = "Which days?",
        buttons = {
            row1, row2,
            { { text = "Save", enabled = next(picked) ~= nil, callback = function()
                UIManager:close(dialog)
                Game.setRepeat(s, q.id, { kind = "days", days = picked })
                self:save(); self:render()
            end } },
            { { text = "Cancel", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

-- MENU > Repeating quests: every repeating quest, on the list or waiting for its day.
-- Tap one to stop it repeating.
function RelicScreen:recurringDialog()
    local s = self.state
    local dialog
    local rows = {}
    for _, r in ipairs(Game.recurringList(s)) do
        local when = r.wake and ("back " .. r.wake:sub(6)) or "on the list"
        table.insert(rows, { { text = r.q.title .. "  (" .. Game.repText(r.q.rep) .. ", " .. when .. ")", align = "left", callback = function()
            UIManager:close(dialog)
            UIManager:show(ConfirmBox:new{
                text = "Stop repeating \"" .. r.q.title .. "\"?" .. (r.wake and "\n\nIt's waiting for its day, so it goes away." or "\n\nIt stays on the list as a normal quest."),
                ok_text = "Stop",
                ok_callback = function() Game.stopRecurring(s, r.q.id); self:save(); self:render() end,
            })
        end } })
    end
    if #rows == 0 then table.insert(rows, { { text = "None yet. Hold a quest > Repeat.", enabled = false } }) end
    dialog = PinnedDialog:new{ title = "Repeating quests", buttons = rows }
    UIManager:show(dialog)
end

function RelicScreen:dueDialog(q)
    local s = self.state
    local dialog
    local function set(due)
        return function()
            UIManager:close(dialog)
            Game.setDue(s, q.id, due)
            self:save(); self:render()
        end
    end
    local now = os.time()
    dialog = PinnedDialog:new{
        title = "Due date: " .. q.title,
        buttons = {
            { { text = "Today", callback = set(Game.dueIn(0, now)) }, { text = "Tomorrow", callback = set(Game.dueIn(1, now)) } },
            { { text = "In 3 days", callback = set(Game.dueIn(3, now)) }, { text = "In a week", callback = set(Game.dueIn(7, now)) } },
            { { text = "Pick a date (YYYY-MM-DD)", callback = function()
                UIManager:close(dialog)
                self:textDialog("Due date (YYYY-MM-DD)", q.due or Game.dueIn(0, now), function(t)
                    if not Game.setDue(s, q.id, t) then self:notify("Use YYYY-MM-DD, like " .. Game.dueIn(2, now) .. ".") end
                end)
            end } },
            { { text = "No due date", callback = set(nil) }, { text = "Cancel", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

-- ALL / MOVE: every quest in a compact list. In move mode, tap the quest it should go above.
local ALL_PER_PAGE = 11
function RelicScreen:allQuestsBody()
    local s = self.state
    local list = Game.orderedQuests(s, os.time())
    local moving = self.moving and Game.findQuest(s, self.moving)
    if self.moving and not moving then self.moving = nil end
    local pages = math.max(1, math.ceil(#list / ALL_PER_PAGE))
    local page = math.min(self.all_page or 1, pages)
    local rows = {}
    for i = (page - 1) * ALL_PER_PAGE + 1, math.min(#list, page * ALL_PER_PAGE) do
        local q = list[i]
        local label = self:questLabel(q)
        if moving and q.id == moving.id then label = ">> " .. label .. " <<" end
        table.insert(rows, { {
            text = label, align = "left", font_size = 16, font_bold = false,
            callback = function()
                if moving then
                    local ok, why = true, nil
                    if q.id ~= moving.id then ok, why = Game.moveQuest(s, moving.id, q.id, os.time()) end
                    self.moving = nil
                    self:save(); self:render()
                    if not ok and why then self:notify(why) end
                else
                    self.detail_id, self.step_page = q.id, 1
                    self:render("flashui")
                end
            end,
            hold_callback = function() if not moving then self:questMenu(q) end end,
        } })
    end
    for _ = #rows + 1, ALL_PER_PAGE do
        table.insert(rows, { { text = " ", enabled = false, font_size = 16 } })
    end
    local foot = {}
    table.insert(foot, {
        { text = "<", enabled = page > 1, callback = function() self.all_page = page - 1; self:render() end },
        moving and { text = "TO END", callback = function()
                local ok, why = Game.moveQuest(s, moving.id, nil, os.time()); self.moving = nil; self:save(); self:render()
                if not ok and why then self:notify(why) end end }
            or { text = "BACK", callback = function() self.quest_all = nil; self:render("flashui") end },
        moving and { text = "CANCEL", callback = function() self.moving = nil; self:render() end }
            or { text = " ", enabled = false },
        { text = ">", enabled = page < pages, callback = function() self.all_page = page + 1; self:render() end },
    })
    local head = moving and ("MOVING: " .. moving.title .. ". Tap the quest it goes above.")
        or string.format("ALL QUESTS (%d). Tap to open, hold to edit or move.", #list)
    local note = "Late quests sit on top; waiting ones at the bottom."
    return VerticalGroup:new{
        align = "left",
        text(head, 16),
        text(note, 14),
        gap(PAD / 2),
        self:buttons(rows),
    }, self:buttons(foot)
end

function RelicScreen:questLabel(q)
    local flags = ""
    if q.id == self.state.daily_id then flags = flags .. "* " end
    if q.waiting then flags = flags .. "WAITING: " end
    if q.main then flags = flags .. "MAIN: " end
    local due = Game.dueText(q, os.time())
    if due then flags = flags .. "[" .. due .. "] " end
    if q.out then flags = flags .. "OUT: " end
    local tail = "  [" .. q.tier .. (q.dread and ", dread" or "") .. "]"
    local done, n = Game.stepProgress(q)
    if n > 0 then tail = tail .. "  " .. done .. "/" .. n end
    local nxt = Game.nextStep(q)
    return flags .. q.title .. tail .. (nxt and ("  > " .. nxt) or "")
end

-- One-line text entry. on_ok(text) runs only for non-empty text.
function RelicScreen:textDialog(title, value, on_ok)
    local input
    input = InputDialog:new{
        title = title,
        input = value or "",
        buttons = { {
            { text = "Cancel", id = "close", callback = function() UIManager:close(input) end },
            { text = "Save", is_enter_default = true, callback = function()
                local t = input:getInputText()
                UIManager:close(input)
                if t and t:match("%S") then on_ok(t); self:save(); self:render() end
            end },
        } },
    }
    UIManager:show(input)
    input:onShowKeyboard()
end

-- Quest detail: steps, complete, options ------------------------------------------------

local STEPS_PER_PAGE = 5

function RelicScreen:detailBody()
    local s = self.state
    local q = Game.findQuest(s, self.detail_id)
    if not q then self.detail_id = nil; return self:questsBody() end
    local done, n = Game.stepProgress(q)
    local info = string.format("%s quest, %d XP%s%s%s", q.tier:gsub("^%l", string.upper), Game.questXp(q),
        q.dread and " (dread x2)" or "", q.main and ", Main Quest" or "", q.waiting and ", waiting" or "")
    local due = Game.dueText(q, os.time())
    if due or q.out then info = info .. "\n" .. (due and (due:gsub("^due ", "Due ") .. (q.due and (" (" .. q.due .. ")") or "")) or "") .. ((due and q.out) and "   " or "") .. (q.out and "Out of the house" or "") end
    if q.rep then info = info .. "\nRepeats " .. Game.repText(q.rep) .. ". Done or skipped, it comes back on its next day." end
    if (q.pomos or 0) > 0 then info = info .. string.format("\nPomodoros: %d (%d min). Finishing pays +20%%.", q.pomos, q.minutes or 0) end
    if n > 0 then info = info .. string.format("\nSteps %d/%d%s", done, n,
        Game.nextStep(q) and ("   Next: " .. Game.nextStep(q)) or "   All steps done") end

    local rows = {}
    local pages = math.max(1, math.ceil(n / STEPS_PER_PAGE))
    self.step_page = math.min(self.step_page or 1, pages)
    local start = (self.step_page - 1) * STEPS_PER_PAGE + 1
    for i = start, math.min(n, start + STEPS_PER_PAGE - 1) do
        local st = q.steps[i]
        table.insert(rows, { {
            text = (st.done and "[x] " or "[  ] ") .. st.text,
            align = "left",
            callback = function()
                local msg = Game.toggleStep(s, q.id, i, os.time())
                self:save(); self:render(); if msg ~= "" then self:notify(msg) end
            end,
            hold_callback = function() self:stepMenu(q, i) end,
        } })
    end
    for _ = (n > 0 and math.min(n - start + 1, STEPS_PER_PAGE) or 0), STEPS_PER_PAGE - 1 do
        table.insert(rows, { { text = " ", enabled = false } })
    end
    local foot = {}
    table.insert(foot, {
        { text = "<", enabled = self.step_page > 1, callback = function() self.step_page = self.step_page - 1; self:render() end },
        { text = "+ STEP", callback = function()
            self:textDialog("New step", "", function(t)
                Game.addStep(s, q.id, t)
                self.step_page = math.ceil(#q.steps / STEPS_PER_PAGE)
            end)
        end },
        { text = ">", enabled = self.step_page < pages, callback = function() self.step_page = self.step_page + 1; self:render() end },
    })
    table.insert(foot, {
        { text = "BACK", callback = function() self.detail_id = nil; self:render() end },
        { text = "EDIT", callback = function() self:questMenu(q) end },
        { text = "COMPLETE", callback = function() self:confirmComplete(q.id) end },
    })
    return VerticalGroup:new{
        align = "left",
        text(q.title, 22, true),
        text(info, 16),
        gap(PAD / 2),
        text(n > 0 and "Tap a step to check it. Hold to edit, move or remove." or "No steps yet. Break it down with + STEP.", 16),
        gap(PAD / 2),
        #rows > 0 and self:buttons(rows) or gap(0),
    }, self:buttons(foot)
end

function RelicScreen:stepMenu(q, i)
    local s = self.state
    local dialog
    local function act(f) return function() UIManager:close(dialog); f(); self:save(); self:render() end end
    dialog = PinnedDialog:new{
        title = q.steps[i].text,
        buttons = {
            { { text = "Edit", callback = function()
                UIManager:close(dialog)
                self:textDialog("Edit step", q.steps[i].text, function(t) Game.editStep(s, q.id, i, t) end)
            end } },
            { { text = "Move up", enabled = i > 1, callback = act(function() Game.moveStep(s, q.id, i, -1) end) },
              { text = "Move down", enabled = i < #q.steps, callback = act(function() Game.moveStep(s, q.id, i, 1) end) } },
            { { text = "Remove", callback = act(function() Game.removeStep(s, q.id, i) end) } },
            { { text = "Cancel", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function RelicScreen:tagLabel(q)
    local tags = q.tags or Game.tagQuest(q.title)
    local names = {}
    for _, k in ipairs(tags) do local sk = Game.skillByKey(k); if sk then table.insert(names, sk.name) end end
    return #names > 0 and table.concat(names, ", ") or "none"
end

function RelicScreen:tagDialog(q)
    local dialog
    local rows = {}
    for _, sk in ipairs(Game.SKILLS) do
        local known = self.state.skills[sk.key]
        if not sk.train_only then table.insert(rows, { { text = known and sk.name or "? (undiscovered)", callback = function()
            UIManager:close(dialog); q.tags = { sk.key }; self:save(); self:render()
        end } }) end
    end
    table.insert(rows, { { text = "None", callback = function() UIManager:close(dialog); q.tags = {}; self:save(); self:render() end } })
    dialog = PinnedDialog:new{ title = "Which skill does this train?", buttons = rows }
    UIManager:show(dialog)
end

function RelicScreen:addQuestDialog(as_daily)
    local input
    input = InputDialog:new{
        title = as_daily and "Today's Daily Directive" or "New quest",
        input_hint = "What needs doing?",
        buttons = { {
            { text = "Cancel", id = "close", callback = function() UIManager:close(input) end },
            { text = "Next", is_enter_default = true, callback = function()
                local title = input:getInputText()
                UIManager:close(input)
                if title and title:match("%S") then self:tierDialog(title, as_daily) end
            end },
        } },
    }
    UIManager:show(input)
    input:onShowKeyboard()
end

function RelicScreen:tierDialog(title, as_daily)
    local dialog
    local rows = {}
    for _, t in ipairs(Game.TIERS) do
        table.insert(rows, { { text = t.label .. "  (" .. t.xp .. " XP)", callback = function()
            UIManager:close(dialog)
            local q = Game.addQuest(self.state, title, t.key)
            if as_daily then Game.setDaily(self.state, q.id) end
            self:save(); self:render()
        end } })
    end
    dialog = PinnedDialog:new{ title = "How big is it?", buttons = rows }
    UIManager:show(dialog)
end

-- BAKE tab ------------------------------------------------------------------------

function RelicScreen:lockedBody(feature, what)
    local n = Game.daysUntil(self.state, feature)
    return VerticalGroup:new{
        align = "left",
        text(what .. " is still offline.", 22, true),
        gap(),
        text(string.format("It comes back in %d day%s. Keep your Daily Directives.", n, n == 1 and "" or "s"), 20),
    }
end

function RelicScreen:bakeBody()
    -- Every button keeps the same position in every state. On e-ink, a layout
    -- that shifts after a tap turns the next tap into a mis-tap.
    local s = self.state
    local now = os.time()
    local rows = {}
    for i = 1, 2 do
        local btn
        if i > Game.barrelCount(s) then
            btn = { text = "Barrel " .. i .. ": opens at level 3", enabled = false }
        else
            local status, left = Game.barrelStatus(s, i, now)
            local b = s.barrels[i]
            if status == "empty" then
                btn = { text = "Barrel " .. i .. ": empty. Tap to bake or salvage", callback = function() self:barrelChoice(i) end }
            elseif status == "baking" then
                local what = b.salvage and ("salvaging " .. Game.BOOK.salvage.count .. " " .. Game.ingLabel(b.salvage):lower())
                    or (b.merge and ("merging into " .. (Gear.SLOT_NAMES[Gear.mergeHost(b.merge[1], b.merge[2]).slot] or "gear"):lower()))
                    or (b.regrow and ("regrowing " .. b.label))
                    or (s.journal[b.combo] and b.label or "an experiment")
                local mins = math.ceil(left / 60)
                local when = mins < 120 and (mins .. " min") or (mins < 2880 and (math.ceil(mins / 60) .. " hr") or (math.ceil(mins / 1440) .. " days"))
                btn = { text = string.format("Barrel %d: %s, %s left", i, what, when),
                        callback = function() self:cancelBarrelDialog(i, what) end }
            else
                btn = { text = "Barrel " .. i .. ": READY. Tap to collect", callback = function()
                    local label, fine, new, extra = Game.collect(s, i, os.time())
                    self:save(); self:render("flashui")
                    if label then
                        local plain = b.salvage or b.merge or b.regrow
                        local msg = plain and extra or (label .. (new and "\nNew recipe in the journal." or ""))
                        if extra and not plain then msg = msg .. "\n\n" .. extra end
                        self:notify(msg)
                    end
                end }
            end
        end
        table.insert(rows, { btn })
    end
    local tools = {}
    table.insert(tools, {
        { text = "PANTRY", callback = function() self:pantryDialog() end },
        { text = "JOURNAL", callback = function() self:journalDialog() end },
        { text = "MERGE LOG", callback = function() self:mergeLogDialog() end },
    })
    local have = {}
    for _, ing in ipairs(Game.shownIngredients(s)) do
        table.insert(have, ing.label .. " " .. (s.inv[ing.key] or 0))
    end
    local known = 0
    for _ in pairs(s.journal) do known = known + 1 end
    local total = 0
    for _ in pairs(Game.BOOK.recipes) do total = total + 1 end
    return VerticalGroup:new{
        align = "left",
        text("Put any two things in a barrel and see what comes out. Baked goods count.", 18),
        gap(PAD / 2),
        self:buttons(rows),
        gap(),
        text("Ingredients: " .. table.concat(have, ", "), 18),
        text(string.format("Recipes found: %d of %d", known, total), 18),
    }, self:buttons(tools)
end

-- Cancel a bake, salvage, merge or regrow (Mike, 2026-10-20). Everything that went in comes back.
function RelicScreen:cancelBarrelDialog(i, what)
    local s = self.state
    local dialog
    dialog = PinnedDialog:new{
        title = "Barrel " .. i .. ": " .. what,
        buttons = {
            { { text = "Refresh", callback = function() UIManager:close(dialog); self:render() end } },
            { { text = "Cancel it (everything comes back)", callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = "Empty barrel " .. i .. "? What went in comes back. The time so far is lost.",
                    ok_text = "Empty it",
                    ok_callback = function()
                        local back = Game.cancelBarrel(s, i, os.time())
                        self:save(); self:render("flashui")
                        self:notify(back and ("Barrel emptied. Back: " .. back .. ".") or "It finished first. Tap to collect.")
                    end })
            end } },
            { { text = "Keep baking", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

function RelicScreen:barrelChoice(slot)
    local s = self.state
    local dialog
    local sv = Game.BOOK.salvage
    dialog = PinnedDialog:new{
        title = "Barrel " .. slot,
        buttons = {
            { { text = "BAKE: any two things", callback = function() UIManager:close(dialog); self:pickIngredient(slot) end } },
            { { text = string.format("SALVAGE: %d of one into 1 rarer (%d min)", sv.count, sv.minutes),
                callback = function() UIManager:close(dialog); self:pickSalvage(slot) end } },
            { { text = "MERGE GEAR: two pieces into one", enabled = #s.gear.bag >= 2,
                callback = function() UIManager:close(dialog); self:pickMerge(slot) end } },
            { { text = "REGROW: a starter back into its item", enabled = (function() for _, n in pairs(s.starters or {}) do if n > 0 then return true end end return false end)(),
                callback = function() UIManager:close(dialog); self:pickRegrow(slot) end } },
            { { text = "Cancel", callback = function() UIManager:close(dialog) end } },
        },
    }
    UIManager:show(dialog)
end

local function gearLabel(it)
    return string.format("%s: %s (%s)", Gear.SLOT_NAMES[it.slot] or it.slot, it.name, Gear.RARITY[it.rarity].name)
end

function RelicScreen:pickMerge(slot, first)
    local s = self.state
    local dialog
    local list = {}
    for _, it in ipairs(s.gear.bag) do
        if not first or it.id ~= first.id then table.insert(list, it) end
    end
    table.sort(list, function(a, b)
        if a.slot ~= b.slot then return a.slot < b.slot end
        return Gear.score(a) > Gear.score(b)
    end)
    local rows = {}
    for _, it in ipairs(list) do
        table.insert(rows, { { text = gearLabel(it), align = "left", callback = function()
            UIManager:close(dialog)
            if not first then return self:pickMerge(slot, it) end
            local d, m = Gear.mergeDust(first, it), Gear.mergeMinutes(first, it)
            local host = Gear.mergeHost(first, it)
            local into = Gear.SLOT_NAMES[host.slot] or host.slot
            local when = m < 120 and (m .. " min") or (m < 2880 and (math.floor(m / 60) .. " hr") or (math.floor(m / 1440) .. " days"))
            UIManager:show(ConfirmBox:new{
                text = string.format("Merge\n%s\n+ %s\n\nComes out as: %s (%s).\nCosts %d dust (you have %d). Takes %s.\nBoth pieces go into the barrel.",
                    first.name, it.name, host.name, into, d, s.inv.dust or 0, when),
                ok_text = "Merge",
                ok_callback = function()
                    local ok, why = Game.startMerge(s, first.id, it.id, os.time())
                    if not ok then self:notify(why) end
                    self:save(); self:render()
                end,
            })
        end } })
    end
    if #list == 0 then table.insert(rows, { { text = first and "Nothing else in your pack." or "Your pack is empty.", enabled = false } }) end
    table.insert(rows, { { text = "Cancel", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = first and ("Merge with " .. first.name .. ": any piece") or "Merge: first piece (from your pack)",
        buttons = rows }
    UIManager:show(dialog)
end

function RelicScreen:pickRegrow(slot)
    local s = self.state
    local dialog
    local keys = {}
    for k, n in pairs(s.starters or {}) do if n > 0 then table.insert(keys, k) end end
    table.sort(keys)
    local rows = {}
    for _, k in ipairs(keys) do
        local r = Game.itemRecipe(k)
        table.insert(rows, { { text = string.format("%s  (starters %d)", r.label, s.starters[k]),
            enabled = (s.inv.dust or 0) >= Game.regrowDust(k), callback = function()
                UIManager:close(dialog)
                local ok, why = Game.startRegrow(s, k, os.time())
                if not ok then self:notify(why) end
                self:save(); self:render()
            end } })
    end
    if #keys == 0 then table.insert(rows, { { text = "No starters yet. Using baked items sometimes keeps one.", enabled = false } }) end
    table.insert(rows, { { text = "Cancel", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = "Regrow (2 dust; second bakes 4)", buttons = rows }
    UIManager:show(dialog)
end

function RelicScreen:mergeLogDialog()
    local s = self.state
    local lines = {}
    for _, e in ipairs(s.merge_log or {}) do
        table.insert(lines, string.format("%s + %s\n  = %s  (worth %d -> %d, generation %d)", e.a, e.b, e.out, e.before, e.after, e.gen or 2))
    end
    local body = #lines > 0 and table.concat(lines, "\n\n") or
        "No merges yet. Merge any two pieces in a barrel; what carries over is for you to work out."
    UIManager:show(TextViewer:new{ title = "MERGE LOG", text = body })
end

function RelicScreen:pickSalvage(slot)
    local s = self.state
    local sv = Game.BOOK.salvage
    local dialog
    local rows = {}
    for _, ing in ipairs(Game.shownIngredients(s)) do
        local n = s.inv[ing.key] or 0
        table.insert(rows, { { text = ing.label .. "  (" .. n .. ")", enabled = n >= sv.count, callback = function()
            UIManager:close(dialog)
            UIManager:show(ConfirmBox:new{
                text = string.format("Salvage %d %s?\nBecomes 1 of whichever rarer ingredient you have least of.\n%d min",
                    sv.count, ing.label, sv.minutes),
                ok_text = "Salvage",
                ok_callback = function()
                    local ok, why = Game.startSalvage(s, ing.key, os.time())
                    if not ok then self:notify(why) end
                    self:save(); self:render()
                end,
            })
        end } })
    end
    table.insert(rows, { { text = "Cancel", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = "Salvage which? (need " .. sv.count .. ")", buttons = rows }
    UIManager:show(dialog)
end

-- What a second pick would make, shown on its button: the recipe if found, "tried" if it failed before.
local function pairNote(s, first, key)
    if not first then return "" end
    local combo = Game.comboKey(first, key)
    if s.journal[combo] then return "  = " .. Game.BOOK.recipes[combo].label end
    if s.tried and s.tried[combo] then return "  (tried: nothing)" end
    return ""
end

function RelicScreen:pickIngredient(slot, first, baked)
    local s = self.state
    local dialog
    local rows = {}
    local function pick(key)
        return function()
            UIManager:close(dialog)
            if not first then self:pickIngredient(slot, key) else self:confirmBake(slot, first, key) end
        end
    end
    if baked then
        local items = {}
        for key, n in pairs(s.inv) do
            if n > 0 and Game.isBakedInput(key) then table.insert(items, key) end
        end
        table.sort(items)
        for _, key in ipairs(items) do
            local n = s.inv[key] - (first == key and 1 or 0)
            local label = (key:match("_fine$") and "Fine " or "") .. Game.itemRecipe(key).label
            table.insert(rows, { { text = label .. "  (" .. math.max(0, n) .. ")" .. pairNote(s, first, key),
                enabled = n > 0, callback = pick(key) } })
        end
        if #items == 0 then table.insert(rows, { { text = "Nothing baked yet", enabled = false } }) end
        table.insert(rows, { { text = "Back", callback = function() UIManager:close(dialog); self:pickIngredient(slot, first) end } })
    else
        for _, ing in ipairs(Game.shownIngredients(s)) do
            local n = (s.inv[ing.key] or 0) - (first == ing.key and 1 or 0)
            table.insert(rows, { { text = ing.label .. "  (" .. math.max(0, n) .. ")" .. pairNote(s, first, ing.key),
                enabled = n > 0, callback = pick(ing.key) } })
        end
        table.insert(rows, { { text = "BAKED GOODS...", callback = function()
            UIManager:close(dialog); self:pickIngredient(slot, first, true) end } })
        table.insert(rows, { { text = "Cancel", callback = function() UIManager:close(dialog) end } })
    end
    local title = first and ("With " .. (first:match("_fine$") and "Fine " or "") .. Game.ingLabel(Game.baseKey(first)) .. ": second thing") or "First thing"
    dialog = PinnedDialog:new{ title = title, buttons = rows }
    UIManager:show(dialog)
end

function RelicScreen:confirmBake(slot, a, b)
    local s = self.state
    local r, combo = Game.bakeResult(a, b)
    local what = s.journal[combo] and r.label
        or ((s.tried and s.tried[combo]) and "Tried before. It didn't take." or "Unknown. An experiment")
    local function name(k) return (k:match("_fine$") and "Fine " or "") .. Game.ingLabel(Game.baseKey(k)) end
    UIManager:show(ConfirmBox:new{
        text = string.format("%s + %s\n%s\n%d min", name(a), name(b), what, Game.bakeMinutes(a, b)),
        ok_text = "Bake",
        ok_callback = function()
            local ok, why = Game.startBake(s, a, b, os.time())
            if not ok then self:notify(why) end
            self:save(); self:render()
        end,
    })
end

local function effectText(e)
    local t = {}
    if e.xp_pct then table.insert(t, "+" .. e.xp_pct .. "% XP, " .. e.hours .. "h") end
    if e.skill_pct then table.insert(t, "+" .. e.skill_pct .. "% skill XP, " .. e.hours .. "h") end
    if e.regen_x then table.insert(t, "Charge regen x" .. e.regen_x .. ", " .. e.hours .. "h") end
    if e.hp then table.insert(t, e.hp >= 999 and "full heal" or ("+" .. e.hp .. " HP")) end
    if e.integrity then table.insert(t, "+" .. e.integrity .. "% integrity") end
    if e.charge then table.insert(t, "+" .. e.charge .. " Charge") end
    if e.luck_flips then table.insert(t, "double finds on " .. e.luck_flips .. " flips") end
    if e.whet then table.insert(t, "+" .. e.whet .. " attack next fight") end
    if e.shield then table.insert(t, "+1 shield") end
    if e.seal then table.insert(t, "double skill XP on next quest") end
    if e.xp then table.insert(t, "+" .. e.xp .. " XP") end
    return table.concat(t, ", ")
end

-- Pantry groups, in the order you'd reach for them (Mike, 2026-10-06: sort by effect).
local PANTRY_GROUPS = {
    { "HEALING", { "hp" } },
    { "REPAIR", { "integrity" } },
    { "CHARGE", { "charge", "regen_x" } },
    { "COMBAT", { "whet" } },
    { "XP", { "xp_pct", "xp" } },
    { "SKILL XP", { "skill_pct", "seal" } },
    { "EXPLORING", { "luck_flips" } },
    { "SHIELDS", { "shield" } },
}
local function pantryGroup(effect)
    for i, g in ipairs(PANTRY_GROUPS) do
        for _, k in ipairs(g[2]) do if effect and effect[k] then return i end end
    end
    return #PANTRY_GROUPS + 1
end
local function pantryLabel(key) return (key:match("_fine$") and "Fine " or "") .. Game.itemRecipe(key).label end
-- baked items in the pack, sorted by group then name
local function pantryItems(s)
    local items = {}
    for key, n in pairs(s.inv) do
        if n > 0 and Game.itemRecipe(key) then table.insert(items, key) end
    end
    table.sort(items, function(a, b)
        local ga, gb = pantryGroup(Game.itemRecipe(a).effect), pantryGroup(Game.itemRecipe(b).effect)
        if ga ~= gb then return ga < gb end
        return pantryLabel(a) < pantryLabel(b)
    end)
    return items
end
-- the effect a baked item actually has (Fine ones are half again as strong, as Game.useBaked applies)
local function itemEffect(key)
    local e = Game.itemRecipe(key).effect or {}
    if not key:match("_fine$") then return e end
    local f = {}
    for k, v in pairs(e) do f[k] = v end
    for _, k in ipairs({ "xp_pct", "skill_pct", "hours", "integrity", "charge", "luck_flips", "whet" }) do
        if f[k] then f[k] = math.floor(f[k] * 1.5) end
    end
    if f.hp and f.hp < 999 then f.hp = math.floor(f.hp * 1.5) end
    return f
end
local function groupName(key) return (PANTRY_GROUPS[pantryGroup(Game.itemRecipe(key).effect)] or { "OTHER" })[1] end

function RelicScreen:pantryDialog()
    local s = self.state
    local dialog
    local rows = {}
    local items = pantryItems(s)
    local label = pantryLabel
    local last
    for _, key in ipairs(items) do
        local r = Game.itemRecipe(key)
        local g = groupName(key)
        if g ~= last then
            last = g
            table.insert(rows, { { text = g, enabled = false } })
        end
        local fx = effectText(itemEffect(key))
        table.insert(rows, { { text = label(key) .. "  x" .. s.inv[key] .. (fx ~= "" and ("   " .. fx) or ""), align = "left", callback = function()
            UIManager:close(dialog)
            local msg = Game.useBaked(s, key, os.time())
            self:save(); self:render()
            if msg then self:notify(msg) end
        end } })
    end
    if #items == 0 then table.insert(rows, { { text = "Nothing baked yet", enabled = false } }) end
    table.insert(rows, { { text = "Close", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = "Pantry: tap to use", buttons = rows }
    UIManager:show(dialog)
end

function RelicScreen:journalDialog()
    local s = self.state
    local found, hints = {}, {}
    local combos = {}
    for combo in pairs(Game.BOOK.recipes) do table.insert(combos, combo) end
    table.sort(combos)
    -- a second bake's hint shows once you've found the recipe that makes its baked input
    local makes = {}
    for c, r in pairs(Game.BOOK.recipes) do makes[r.key] = c end
    local hidden = 0
    for _, combo in ipairs(combos) do
        local r = Game.BOOK.recipes[combo]
        if s.journal[combo] then
            local a, b = combo:match("^(.-)%+(.+)$")
            table.insert(found, string.format("%s + %s = %s: %s", Game.ingLabel(a), Game.ingLabel(b), r.label, effectText(r.effect)))
        elseif (r.from and not s.journal[makes[r.from] or ""]) or (r.uses and not (s.ing_seen or {})[r.uses]) then
            hidden = hidden + 1
        else
            table.insert(hints, "? " .. r.hint)
        end
    end
    local tried = 0
    for c in pairs(s.tried or {}) do if not Game.BOOK.recipes[c] then tried = tried + 1 end end
    local body = (#found > 0 and table.concat(found, "\n") or "Nothing found yet.") ..
        "\n\nNOT YET FOUND\n" .. table.concat(hints, "\n") ..
        (hidden > 0 and string.format("\n\n%d more, not yet hinted.", hidden) or "") ..
        string.format("\n\nDead ends tried: %d. The barrel picker marks them.", tried)
    UIManager:show(TextViewer:new{ title = "CRAFTING JOURNAL", text = body })
end

-- BATTLE view: classic handheld battle layout (enemy top, you bottom, text box, 2x2 menu).
-- Monochrome by design, like the early handheld games, which suits e-ink.

-- The Trial: pick 2 of 6 first abilities, once, before the first fight.
function RelicScreen:abilityPickView()
    local s = self.state
    self.pick = self.pick or {}
    local chosen = {}
    for k in pairs(self.pick) do table.insert(chosen, k) end
    local rows = {}
    for _, a in ipairs(Combat.ABILITIES) do
        table.insert(rows, { {
            text = (self.pick[a.key] and "[x] " or "[ ] ") .. a.name,
            callback = function()
                if self.pick[a.key] then self.pick[a.key] = nil
                elseif #chosen < 2 then self.pick[a.key] = true end
                self:render()
            end,
        } })
    end
    table.insert(rows, { { text = "CONFIRM (" .. #chosen .. " of 2)", enabled = #chosen == 2, callback = function()
        table.sort(chosen)
        Combat.pickAbilities(s, chosen[1], chosen[2])
        self.pick = nil
        self:save(); self:render("flashui")
    end } })
    local desc = {}
    for _, a in ipairs(Combat.ABILITIES) do table.insert(desc, a.name .. ": " .. a.text) end
    return VerticalGroup:new{
        align = "left",
        text("THE TRIAL. Before you fight, choose two abilities. This can't be undone.", 20, true),
        gap(PAD / 2),
        text(table.concat(desc, "\n"), 15),
        gap(PAD / 2),
        self:buttons(rows),
    }
end

function RelicScreen:battleView()
    local s = self.state
    if not s.abilities then return self:abilityPickView() end
    local f = s.fight
    local w = W() - 2 * PAD
    local sprite_size = Screen:scaleBySize(140)
    local box_w = math.floor(w * 0.58)

    local function sprite(name)
        return ImageWidget:new{
            file = plugin_dir .. "sprites/" .. name .. ".png",
            width = sprite_size, height = sprite_size,
        }
    end

    local function infobox(name, lv, cur, max, extra)
        local inner = box_w - 2 * PAD
        local rows = VerticalGroup:new{
            align = "left",
            TextWidget:new{ text = name .. "   Lv" .. lv, face = (bface(true, 20)), bold = true, max_width = inner },
            gap(PAD / 3),
            HorizontalGroup:new{
                align = "center",
                TextWidget:new{ text = "HP ", face = (bface(true, 16)), bold = true },
                ProgressWidget:new{
                    width = inner - Screen:scaleBySize(40),
                    height = Screen:scaleBySize(14),
                    percentage = math.max(0, cur) / max,
                    fillcolor = Blitbuffer.COLOR_BLACK,
                    bordersize = Size.border.thick,
                },
            },
            TextWidget:new{ text = string.format("%d / %d%s", math.max(0, cur), max, extra or ""), face = (bface(false, 16)), max_width = inner },
        }
        return FrameContainer:new{
            bordersize = Size.border.thick,
            radius = Size.radius.window,
            padding = PAD / 2,
            width = box_w,
            rows,
        }
    end

    local status = Combat.statusLine(f)
    local enemy_box = infobox(f.name, f.lv or 1, f.hp, f.max, status ~= "" and ("   " .. status) or nil)
    local enemy_img = sprite(f.sprite or "scrap_hound")
    enemy_box.overlap_align = "left"
    enemy_img.overlap_align = "right"
    local enemy_row = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = math.max(sprite_size, enemy_box:getSize().h) },
        enemy_box, enemy_img,
    }

    local player_img = sprite("player")
    local player_box = infobox("YOU", s.level, s.hp, Game.maxHp(s.level, s), "   Charge " .. s.charge .. "/" .. Game.maxCharge(s.level, s))
    player_img.overlap_align = "left"
    local pb = player_box:getSize()
    player_box.overlap_offset = { w - box_w, math.max(0, sprite_size - pb.h) }
    local player_row = OverlapGroup:new{
        dimen = Geom:new{ w = w, h = math.max(sprite_size, pb.h) },
        allow_mirroring = false,
        player_img, player_box,
    }

    local message = FrameContainer:new{
        bordersize = Size.border.thick,
        radius = Size.radius.window,
        padding = PAD,
        width = w,
        TextBoxWidget:new{
            text = self.last_line or ((f.boss and "The " or "A wild ") .. f.name .. " blocks the road!"),
            face = (bface(false, 18)),
            width = w - 2 * PAD - 2 * Size.border.thick,
            height = Screen:scaleBySize(120),  -- room for hit + phase change + wind-up, or hit + loot
        },
    }

    local function act(a)
        return function()
            self.last_line = Game.fightAction(s, a)
            self.battle_menu = nil
            self.item_page = nil
            self:save(); self:render()
        end
    end
    local rows
    if self.battle_menu == "items" then
        -- same 2x2 as everywhere in battle: three items and BACK; MORE pages when there are more
        local held = Game.heldBattleItems(s)
        local per = #held > 3 and 2 or 3
        local pages = math.max(1, math.ceil(#held / per))
        local page = math.min(self.item_page or 1, pages)
        local btn = {}
        for i = 1, per do
            local it = held[(page - 1) * per + i]
            if it then btn[i] = { text = it.label:gsub("^Fine (.*)$", "%1*") .. " x" .. it.n, callback = act("item:" .. it.key) }
            else btn[i] = { text = "—", enabled = false, callback = function() end } end
        end
        if per == 2 then
            btn[3] = { text = "MORE (" .. page .. "/" .. pages .. ")", callback = function()
                self.item_page = page % pages + 1; self:render() end }
        end
        rows = {
            { btn[1], btn[2] },
            { btn[3], { text = "BACK", callback = function() self.battle_menu = nil; self.item_page = nil; self:render() end } },
        }
    elseif self.battle_menu == "abilities" then
        local btn = {}
        for i = 1, 3 do
            local key = s.abilities and s.abilities[i]
            local a = key and Combat.ABILITY[key]
            if a and a.passive then
                btn[i] = { text = a.name .. " (passive)", enabled = false, callback = function() end }
            elseif a then
                local cost = Combat.cost(s, Game.gearTotals(s), key)
                btn[i] = { text = a.name .. "  (" .. cost .. ")", enabled = s.charge >= cost, callback = act("ability:" .. key) }
            elseif i == 3 and (s.skills.might or (s.grit or 0) > 0) then
                btn[i] = { text = string.format("BREAKER (Grit %d)", s.grit or 0),
                    enabled = Combat.canBreak(s, f), callback = act("breaker") }
            else
                btn[i] = { text = "—", enabled = false, callback = function() end }
            end
        end
        rows = {
            { btn[1], btn[2] },
            { btn[3], { text = "BACK", callback = function() self.battle_menu = nil; self:render() end } },
        }
    else
        rows = {
            { { text = "ATTACK", callback = act("attack") },
              { text = "ABILITIES", callback = function() self.battle_menu = "abilities"; self:render() end } },
            { { text = "ITEM  x" .. Game.potionCount(s), enabled = Game.potionCount(s) > 0,
                callback = function() self.battle_menu = "items"; self.item_page = 1; self:render() end },
              { text = "RUN", callback = act("run") } },
        }
        if Combat.canResolve(s, f) then
            table.insert(rows, { { text = "RESOLVE (you far outclass it)", callback = act("resolve") } })
        end
    end
    local menu = self:buttons(rows)

    local quirk = TextBoxWidget:new{
        text = Combat.quirkText(f),
        face = (bface(false, 16)),
        width = w,
    }

    return VerticalGroup:new{
        align = "left",
        enemy_row,
        gap(PAD / 2),
        quirk,
        gap(PAD),
        player_row,
        gap(PAD),
        message,
        gap(PAD),
        menu,
    }
end

-- EXPLORE tab (includes combat) ---------------------------------------------------------

-- MAP views cycle THIS REGION -> MY ROAD -> FULL ROUTE; the button names the next one.
local MAP_NEXT = { region = "road", road = "route", route = "region" }
local MAP_NEXT_LABEL = { region = "MY ROAD", road = "FULL ROUTE", route = "THIS REGION" }
-- Zoom and pan (Mike, 2026-10-20): + and - step through MAP_ZOOMS; tapping the map
-- centers it on the tap; holding the map jumps back to where you are.
local MAP_ZOOMS = { 1, 1.5, 2, 3 }

function RelicScreen:zoomMap(dir)
    local z = self.map_zoom or 1
    local idx = 1
    for i, v in ipairs(MAP_ZOOMS) do if v == z then idx = i end end
    idx = math.max(1, math.min(#MAP_ZOOMS, idx + dir))
    self.map_zoom = MAP_ZOOMS[idx]
    if self.map_zoom == 1 then self.map_center = nil end
    self:render("flashui")
end

function RelicScreen:exploreBody()
    local s = self.state
    if not Game.unlocked(s, "map") and not s.fight then return self:lockedBody("map", "The map") end
    if s.fight then return self:battleView() end
    local st = Game.currentStage(s)
    local today = Game.stepsToday(s)
    -- Three short lines only: the map is tall, and the tab bar must stay on screen.
    local last = self.last_line or "Flip a card to explore."
    if #last > 110 then
        local cut = 105
        while cut > 1 and last:byte(cut + 1) and last:byte(cut + 1) >= 0x80 and last:byte(cut + 1) < 0xC0 do cut = cut - 1 end
        last = last:sub(1, cut):gsub("[%s%p]*$", "") .. "... (STATUS > RECENT)"
    end
    local total = (Game.ROUTE and Game.ROUTE.total_km) or 1862
    local left = Game.kmToNextStage(s)
    local next_line = Game.routeDone(s) and "Rome reached." or string.format("Stage %d/%d: %.1f km to %s (%d flips)",
        st, #Game.STAGE_KM, left, Game.STAGE_NAMES[st] or "?", math.ceil(left / 0.75 - 1e-9))
    local info = string.format("%.1f km of %s km  ·  Range %d  ·  Steps %s\n%s\n%s",
        s.route.km, (tostring(math.floor(total)):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")),
        s.range, today > 0 and tostring(today) or "not synced", next_line, last)
    if self.map_view == "road" then
        info = string.format("Walked %.1f km  ·  %.1f%% of the way to Rome\n%s\n%s",
            s.route.km, 100 * s.route.km / total, next_line, last)
    end
    local rows = {
        { { text = "FLIP CARD", callback = function()
                local _, msg = Game.flipCard(s)
                self.last_line = msg
                self:save(); self:render("flashui")
            end },
          { text = "SYNC", callback = function() if Relic_ref then Relic_ref:pullInbox(true) end end },
          { text = MAP_NEXT_LABEL[self.map_view or "region"], callback = function()
                self.map_view = MAP_NEXT[self.map_view or "region"]
                self.map_zoom, self.map_center = nil, nil
                self:render("flashui")
            end },
        },
        -- zoom on its own row (Mike, 2026-10-22); the middle button shows the zoom and resets it
        { { text = "ZOOM OUT", enabled = (self.map_zoom or 1) > 1, callback = function() self:zoomMap(-1) end },
          { text = string.format("%gx", self.map_zoom or 1), enabled = (self.map_zoom or 1) > 1, callback = function()
                self.map_zoom, self.map_center = nil, nil
                self:render("flashui")
            end },
          { text = "ZOOM IN", enabled = (self.map_zoom or 1) < MAP_ZOOMS[#MAP_ZOOMS], callback = function() self:zoomMap(1) end } },
    }
    return VerticalGroup:new{
        align = "left",
        self:mapView(),
        gap(PAD / 2),
        text(info, 18),
    }, self:buttons(rows)
end

-- Map: pre-drawn trail image (tools/map/make_map.py) with stamps on reached towns and a
-- "you are here" marker, both placed from route.lua geometry.
function RelicScreen:mapView()
    local s = self.state
    local R = Game.ROUTE
    local mw = math.min(R.image_w, W() - 2 * PAD)
    local fit = mw / R.image_w
    local mh = math.floor(R.image_h * fit)
    local zoom = self.map_zoom or 1
    local sc = fit * zoom   -- image pixels -> zoomed pixels
    local bbw, bbh = math.floor(R.image_w * sc), math.floor(R.image_h * sc)
    local file, path, towns
    local j = self.map_view == "road" and Game.journeyFor(s.route.km)
    if j then
        file, path, towns = j.image, j.path, j.towns
    elseif self.map_view == "route" then
        file, path = R.route_image, R.route_path
    else
        local _, reg = Game.currentRegion(s)
        file, path, towns = reg.image, reg.path, reg.towns
    end
    -- the visible window's top-left in zoomed pixels; centered on map_center (image px) or on you
    local hx0, hy0 = Game.mapPoint(path, s.route.km)
    local cx, cy = hx0, hy0
    if self.map_center then cx, cy = self.map_center[1], self.map_center[2] end
    local ox = zoom > 1 and math.floor(math.max(0, math.min(bbw - mw, cx * sc - mw / 2))) or 0
    local oy = zoom > 1 and math.floor(math.max(0, math.min(bbh - mh, cy * sc - mh / 2))) or 0
    local function icon(name, size, x, y)
        local sz = math.floor(size * fit)   -- markers keep their size when zoomed
        local px, py = math.floor(x * sc - ox - sz / 2), math.floor(y * sc - oy - sz / 2)
        if px + sz < 0 or py + sz < 0 or px > mw or py > mh then return nil end
        local w = ImageWidget:new{ file = plugin_dir .. "map/" .. name, width = sz, height = sz, alpha = true }
        w.overlap_offset = { px, py }
        return w
    end
    local base
    if zoom > 1 then
        base = ImageWidget:new{ file = plugin_dir .. file, width = mw, height = mh, scale_factor = sc,
            center_x_ratio = (ox + mw / 2) / bbw, center_y_ratio = (oy + mh / 2) / bbh }
    else
        base = ImageWidget:new{ file = plugin_dir .. file, width = mw, height = mh }
    end
    local layers = {
        dimen = Geom:new{ w = mw, h = mh },
        allow_mirroring = false,
        base,
    }
    if j then
        -- the walked part of the road, inked solid over the dashed trail
        local pts = {}
        for _, p in ipairs(path) do
            if p[3] > s.route.km then break end
            table.insert(pts, { p[1] * sc - ox, p[2] * sc - oy })
        end
        table.insert(pts, { hx0 * sc - ox, hy0 * sc - oy })
        local t = math.max(3, math.floor(4 * fit + 0.5))
        local ink = Blitbuffer.COLOR_BLACK
        local walked = C.Canvas:new{ w = mw, h = mh, draw = function(_, bb, x, y)
            for i = 2, #pts do
                local a, b = pts[i - 1], pts[i]
                local n = math.max(1, math.ceil(math.max(math.abs(b[1] - a[1]), math.abs(b[2] - a[2]))))
                for k = 0, n do
                    local px = a[1] + (b[1] - a[1]) * k / n
                    local py = a[2] + (b[2] - a[2]) * k / n
                    local rx, ry = math.floor(px - t / 2), math.floor(py - t / 2)
                    if rx >= 0 and ry >= 0 and rx + t <= mw and ry + t <= mh then
                        bb:paintRect(x + rx, y + ry, t, t, ink)
                    end
                end
            end
        end }
        walked.overlap_offset = { 0, 0 }
        table.insert(layers, walked)
    end
    for _, t in ipairs(towns or {}) do
        if t[3] > 0 and s.route.km >= t[3] - 1e-9 then
            local w = icon("stamp.png", 16, t[1], t[2])
            if w then table.insert(layers, w) end
        end
    end
    local you = icon("you.png", 30, hx0, hy0)
    if you then table.insert(layers, you) end
    -- tap to pan (zoomed in), hold to come back to where you are
    local touch = C.Canvas:new{ w = mw, h = mh,
        on_tap = function(ges, cv)
            if zoom <= 1 or not ges or not ges.pos then return end
            local tx, ty = ges.pos.x - cv.dimen.x, ges.pos.y - cv.dimen.y
            self.map_center = { (ox + tx) / sc, (oy + ty) / sc }
            self:render("flashui")
        end,
        on_hold = function()
            if not self.map_center then return end
            self.map_center = nil
            self:render("flashui")
        end }
    touch.overlap_offset = { 0, 0 }
    table.insert(layers, touch)
    return OverlapGroup:new(layers)
end

-- STATUS tab ------------------------------------------------------------------------------

-- Skill XP bars: each bar's full length is the XP its next rank needs (scaled so the
-- biggest need fills the row), the dark part is the XP banked toward it.
function RelicScreen:skillBars()
    local s = self.state
    local list, maxneed = {}, 1
    for _, sk in ipairs(Game.SKILLS) do
        local v = s.skills[sk.key]
        if v then
            local need = Game.skillXpToNext(v.rank)
            table.insert(list, { name = sk.name, rank = v.rank, xp = v.xp, need = need })
            if need > maxneed then maxneed = need end
        end
    end
    if #list == 0 then return text("None yet. Finish quests to discover them.", 18) end
    -- Two columns, so ten skills take five rows and the tab bar stays on screen.
    local face = (bface(false, 16))
    local total_w = W() - 2 * PAD
    local col_w = math.floor((total_w - PAD) / 2)
    local label_w = math.floor(col_w * 0.42)
    local num_w = math.floor(col_w * 0.22)
    local bar_max = col_w - label_w - num_w - math.floor(PAD / 2)
    local row_h = Screen:scaleBySize(26)
    local bar_h = Screen:scaleBySize(12)
    local dark, light = Blitbuffer.Color8(34), Blitbuffer.Color8(230)
    local function cell(k)
        local bw = math.max(Screen:scaleBySize(20), math.floor(bar_max * k.need / maxneed))
        local pct = math.max(0, math.min(1, k.xp / k.need))
        local bar = C.Canvas:new{ w = bar_max + math.floor(PAD / 2), h = row_h, draw = function(_, bb, x, y)
            local by = y + math.floor((row_h - bar_h) / 2)
            local t = math.max(1, Size.line.thick)
            bb:paintRect(x, by, bw, bar_h, dark)
            bb:paintRect(x + t, by + t, bw - 2 * t, bar_h - 2 * t, light)
            local fw = math.floor((bw - 2 * t) * pct)
            if fw > 0 then bb:paintRect(x + t, by + t, fw, bar_h - 2 * t, dark) end
        end }
        return LeftContainer:new{ dimen = Geom:new{ w = col_w, h = row_h }, HorizontalGroup:new{
            align = "center",
            LeftContainer:new{ dimen = Geom:new{ w = label_w, h = row_h },
                TextWidget:new{ text = k.name .. "  " .. k.rank, face = face, max_width = label_w - math.floor(PAD / 2) } },
            bar,
            TextWidget:new{ text = k.xp .. "/" .. k.need, face = face, max_width = num_w },
        } }
    end
    local group = VerticalGroup:new{ align = "left" }
    for i = 1, #list, 2 do
        local row = HorizontalGroup:new{ align = "center", cell(list[i]) }
        if list[i + 1] then
            table.insert(row, HorizontalSpan:new{ width = PAD })
            table.insert(row, cell(list[i + 1]))
        end
        table.insert(group, row)
    end
    return group
end

-- SERVICE RECORD: the rank ladder, earned ranks solid, the next one filling, the rest outlined.
function RelicScreen:serviceRecord()
    local s = self.state
    local px = C.px
    local cw = W() - 2 * PAD
    local info = Game.rankInfo(s)
    local n = info.count
    local head = string.format("SERVICE RECORD   %s  (rank %d of %d)", C.upper(info.rank.name), info.index, n)
    local foot = info.next
        and string.format("Next: %s at LV %d (%d%%)   Fleet Admiral at LV %d: %d%% of the way",
            info.next.name, info.next.level, math.floor(info.pct_next * 100), Game.RANKS[n].level, math.floor(info.pct_top * 100))
        or "Fleet Admiral. The top of the ladder."
    local H = px(78)
    return C.Canvas:new{ w = cw, h = H, draw = function(_, bb, x, y)
        local d = px(14)
        local iw = C.insigniaWidth(info.rank, d)
        C.insignia(bb, x, y + px(4), info.rank, d, C.TXT, C.BG)
        C.put(bb, C.text(head, "bold", 15, C.TXT, cw - iw - px(12)), x + iw + px(12), y, px(22))
        local gap = px(4)
        local cwid = (cw - gap * (n - 1)) / n
        local cy, chh = y + px(30), px(18)
        local line = Blitbuffer.Color8(C.TXT)
        for i = 1, n do
            local cx = math.floor(x + (i - 1) * (cwid + gap))
            local w = math.floor(cwid)
            if i <= info.index then
                C.rect(bb, cx, cy, w, chh, C.TXT)
            else
                bb:paintRect(cx, cy, w, chh, line)
                bb:paintRect(cx + 2, cy + 2, w - 4, chh - 4, Blitbuffer.Color8(C.BG))
                if i == info.index + 1 and info.pct_next > 0 then
                    C.rect(bb, cx + 2, cy + 2, math.floor((w - 4) * info.pct_next), chh - 4, C.MID)
                end
            end
        end
        C.put(bb, C.text(foot, "cond", 15, C.TXT, cw), x, y + px(54), px(22))
    end }
end

-- PROMOTION: full screen, once per new rank (only the highest if several came at once).
function RelicScreen:renderPromotion(idx, refresh)
    local s = self.state
    local px = C.px
    local r, nxt = Game.RANKS[idx], Game.RANKS[idx + 1]
    local cw = W() - 2 * PAD
    local d = px(44)
    local iw = C.insigniaWidth(r, d)
    local function ctext(str, size, bold)
        return TextBoxWidget:new{ text = str, face = (bface(bold, size)), width = cw,
            bold = bold, alignment = "center" }
    end
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = PAD,
        width = Screen:getWidth(), height = Screen:getHeight(),
        VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = math.floor(Screen:getHeight() * 0.22) },
            ctext("PROMOTION", 22, true),
            gap(PAD * 2),
            C.Canvas:new{ w = cw, h = d, draw = function(_, bb, x, y)
                C.insignia(bb, x + math.floor((cw - iw) / 2), y, r, d, C.TXT, C.BG)
            end },
            gap(PAD * 2),
            ctext(C.upper(r.name), 34, true),
            gap(PAD),
            ctext(string.format("Rank %d of %d, reached at level %d.", idx, #Game.RANKS, s.level), 18),
            gap(PAD / 2),
            ctext(nxt and string.format("Next: %s at level %d.", nxt.name, nxt.level) or "There is no higher rank.", 18),
            gap(PAD * 3),
            self:buttons({ { { text = "CONTINUE", callback = function()
                s.rank_seen = Game.rankIndex(s.level); self:save(); self:render("full")
            end } } }),
        },
    }
    self:save()
    UIManager:setDirty(self, refresh or "full")
end

function RelicScreen:statusBody()
    local s = self.state
    local st = s.stats
    local lines = {
        string.format("Level %d   XP %d / %d   HP %d / %d   Integrity %d%%", s.level, s.xp, Game.xpToNext(s.level), s.hp, Game.maxHp(s.level, s), s.integrity),
        (function()
            local T = Game.gearTotals(s)
            local function v(k) return (T[k] or 0) ~= 0 and string.format("%d(%+d)", st[k] + T[k], T[k]) or tostring(st[k]) end
            return string.format("STR %s   RES %s   FOC %s   ACU %s   KIN %s", v("str"), v("res"), v("foc"), v("acu"), v("kin"))
        end)(),
        (function()
            local t = s.training
            return string.format("Sets %d (%d pushups, %d squats, %d dumbbells)   Grit %d/%d", t.total, t.pushups or 0, t.squats or 0, t.dumbbells or 0,
                s.grit or 0, Game.gritCap(s))
        end)(),
        s.abilities and ("Abilities: " .. Combat.ABILITY[s.abilities[1]].name .. ", " .. Combat.ABILITY[s.abilities[2]].name) or "Abilities: chosen at your first fight",
        string.format("Class seed: Relic / Footing / Spacetime   Footing rank %d (%d kept day%s)", s.footing.rank, s.footing.kept, s.footing.kept == 1 and "" or "s"),
    }
    local after = {}
    local perks = {}
    for r = 2, Game.mightRank(s), 2 do if Game.MIGHT_PERKS[r] then table.insert(perks, (Game.MIGHT_PERKS[r]:gsub(":.*", ""))) end end
    if #perks > 0 then table.insert(after, "Might perks: " .. table.concat(perks, ", ")) end
    table.insert(after, "")
    table.insert(after, string.format("Route %.1f of 1,862 km   FRONT PRESSURE %d   Best streak %d", s.route.km, Game.frontPressure(s), s.best_streak))
    return VerticalGroup:new{
        align = "left",
        text(table.concat(lines, "\n"), 18),
        gap(math.floor(PAD / 2)),
        self:serviceRecord(),
        gap(math.floor(PAD / 2)),
        text("SKILLS", 18),
        self:skillBars(),
        text(table.concat(after, "\n"), 18),
    }, self:buttons({ {
        -- three buttons (Mike, 2026-10-22): RECENT and story LOGS moved to RECORDS
        { text = "GEAR", callback = function() self.inv_view = { tab = "gear", page = 1 }; self:render("flashui") end },
        { text = "LOOT " .. math.floor(Game.goldBalance(s)) .. "g", callback = function() self:lootDialog() end },
        { text = "RECORDS", callback = function() self.records_view = true; self:render("flashui") end },
    } })
end

-- RECORDS (Mike, 2026-10-22): personal stats from the chronicle, plus RECENT and story LOGS.
function RelicScreen:recordsBody()
    local s = self.state
    local px = C.px
    local cw = W() - 2 * PAD
    local now = os.time()
    local lcars = LCARS_BUTTONS
    local HEAD = lcars and "lcars" or "bold"
    local ok, st = pcall(function() return Game.chronicleStats(Chronicle.lines(), now, 14) end)
    if not ok then
        logger_warn("Relic: records failed", tostring(st))
        st = Game.chronicleStats({}, now, 14)
    end
    local W7, A = st.week, st.all

    -- 14-day bar chart: quests done per day, today darkest
    local CH = px(150)
    local maxd = 1
    for _, d in ipairs(st.days) do maxd = math.max(maxd, d.done) end
    local chart = C.Canvas:new{ w = cw, h = CH, draw = function(_, bb, x, y)
        local n = #st.days
        local gp = px(6)
        local bw = math.floor((cw - gp * (n - 1)) / n)
        local base = y + CH - px(22)
        local top = y + px(22)
        C.rect(bb, x, base, cw, 1, C.DIM)
        for i, d in ipairs(st.days) do
            local bx = x + (i - 1) * (bw + gp)
            local h = math.floor((base - top) * d.done / maxd + 0.5)
            if h > 0 then C.rect(bb, bx, base - h, bw, h, i == n and C.TXT or C.MID) end
            if d.done > 0 then
                local t = C.text(tostring(d.done), "mono", 13, C.TXT)
                C.put(bb, t, bx + math.floor((bw - t:getSize().w) / 2), base - h - px(20), px(20))
            end
            local lab = C.text(Game.WDAY_NAMES[d.wday]:sub(1, 1), "mono", 13, i == n and C.TXT or C.MID)
            C.put(bb, lab, bx + math.floor((bw - lab:getSize().w) / 2), base + px(2), px(20))
        end
    end }

    -- horizontal bars: rows = { { label, n } }
    local function hbars(rows)
        local RH = px(26)
        local maxv = 1
        for _, r in ipairs(rows) do maxv = math.max(maxv, r[2]) end
        return C.Canvas:new{ w = cw, h = RH * #rows, draw = function(_, bb, x, y)
            local lw, nw = px(130), px(50)
            local bwid = cw - lw - nw - px(8)
            for i, r in ipairs(rows) do
                local yy = y + (i - 1) * RH
                C.put(bb, C.text(r[1], HEAD, 15, C.TXT, lw - px(8)), x, yy, RH)
                C.rect(bb, x + lw, yy + px(8), bwid, px(10), C.EMPTY)
                local w = math.floor(bwid * r[2] / maxv + 0.5)
                if w > 0 then C.rect(bb, x + lw, yy + px(8), w, px(10), C.TXT) end
                C.put(bb, C.text(tostring(r[2]), "mono", 14, C.TXT), x + lw + bwid + px(8), yy, RH)
            end
        end }
    end
    local function tierRows(t)
        return { { "Minor", t.minor or 0 }, { "Standard", t.standard or 0 }, { "Major", t.major or 0 }, { "Epic", t.epic or 0 } }
    end

    local since = A.first and os.date("%b %d", os.time{ year = tonumber(A.first:sub(1, 4)), month = tonumber(A.first:sub(6, 7)),
        day = tonumber(A.first:sub(9, 10)), hour = 12 }) or "today"
    local week = string.format("Done %d   Deleted %d   Skipped %d   Daily Directives %d/7\nXP %d   Gold earned $%.2f",
        W7.done, W7.deleted, W7.skipped, W7.dailies, W7.xp, W7.usd)
    local skills = {}
    for i = 1, math.min(4, #st.skills) do
        local sk = Game.skillByKey(st.skills[i].key)
        table.insert(skills, (sk and sk.name or st.skills[i].key) .. " " .. st.skills[i].n)
    end
    local T = s.tally or {}
    local rank = Game.RANKS[Game.rankIndex(s.level)]
    local all = string.format("Quests done %d (%.1f a day)   Best day %d   Deleted %d\n"
        .. "Level %d %s   Best streak %d   %.1f km walked\nFights won %d   Bakes %d",
        A.done, A.done / (A.days or 1), A.best_n, A.deleted, s.level, rank.name, s.best_streak, s.route.km,
        T.wins or 0, T.bakes or 0)

    local body = VerticalGroup:new{
        align = "left",
        text("QUESTS DONE, LAST 14 DAYS", 18, true),
        chart,
        gap(PAD / 2),
        text("THIS WEEK", 18, true),
        text(week, 16),
        hbars(tierRows(W7.tiers)),
        gap(PAD / 2),
        text("WHEN YOU FINISH THINGS", 18, true),
        hbars({ { "Morning", st.hours[1] }, { "Afternoon", st.hours[2] }, { "Evening", st.hours[3] }, { "Night", st.hours[4] } }),
        gap(PAD / 2),
        text("SINCE " .. C.upper(since), 18, true),
        text(all, 16),
        text("Top skills: " .. (#skills > 0 and table.concat(skills, ", ") or "none yet"), 16),
    }
    return body, self:buttons({ {
        { text = "RECENT", callback = function()
            UIManager:show(InfoMessage:new{ text = table.concat(s.log, "\n") ~= "" and table.concat(s.log, "\n") or "Nothing yet." })
        end },
        { text = "STORY LOGS (" .. #s.story.logs .. ")", enabled = #s.story.logs > 0, callback = function() self:logsDialog() end },
        { text = "BACK", callback = function() self.records_view = nil; self:render("flashui") end },
    } })
end

-- LOOT (Mike, 2026-10-20): real-world rewards bought with gold from quests.
-- Tap an item to claim it (the gold is spent; Mike buys it himself); hold to take it off the list.
function RelicScreen:lootDialog()
    local s = self.state
    local dialog
    local bal = math.floor(Game.goldBalance(s))
    local items = {}
    for _, it in ipairs(s.loot.items) do table.insert(items, it) end
    table.sort(items, function(a, b) return Game.lootPrice(a) < Game.lootPrice(b) end)
    local rows = {}
    for _, it in ipairs(items) do
        local price = Game.lootPrice(it)
        local mark = bal >= price and "READY  " or string.format("%d%%  ", math.floor(100 * bal / math.max(1, price)))
        table.insert(rows, { { text = mark .. it.name .. "   " .. price .. "g", align = "left",
            callback = function()
                if bal < price then
                    UIManager:show(InfoMessage:new{ text = string.format("%s costs %d gold. You have %d: %d to go.",
                        it.name, price, bal, price - bal) })
                    return
                end
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = string.format("Claim %s for %d gold?\nThen go buy it. You earned it.", it.name, price),
                    ok_text = "Claim",
                    ok_callback = function()
                        local ok, why = Game.claimLoot(s, it.id, os.time())
                        self:save(); self:render()
                        self:notify(ok and ("Claimed: " .. it.name .. ". Go get it.") or why)
                    end })
            end,
            hold_callback = function()
                UIManager:close(dialog)
                UIManager:show(ConfirmBox:new{
                    text = "Take " .. it.name .. " off the loot list?",
                    ok_text = "Remove",
                    ok_callback = function() Game.removeLoot(s, it.id); self:save(); self:render() end })
            end } })
    end
    if #rows == 0 then table.insert(rows, { { text = "Nothing on the list. Add @loot tasks in Todoist.", enabled = false } }) end
    table.insert(rows, { { text = "CLAIMED (" .. #s.loot.claims .. ")", enabled = #s.loot.claims > 0, callback = function()
        local lines = {}
        for _, c in ipairs(s.loot.claims) do table.insert(lines, string.format("%s  %s  (%dg)", c.date, c.name, c.gold)) end
        UIManager:show(InfoMessage:new{ text = table.concat(lines, "\n") })
    end } })
    table.insert(rows, { { text = "Close", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = string.format("Loot: %d gold. Tap to claim, hold to remove.", bal), buttons = rows }
    UIManager:show(dialog)
end

-- GEAR (inside STATUS) --------------------------------------------------------------------
-- Level 1: the 11 slots. Level 2: items that fit a slot, with a better/worse marker.
-- Level 3: one item's full description with EQUIP.
-- An item's text with its engraving beside it, when its base has art.
local function withArt(item, str, size)
    local art = item and Gear.artFor(item)
    if not art then return text(str, size) end
    local tw = Screen:scaleBySize(160)
    return HorizontalGroup:new{
        align = "top",
        TextBoxWidget:new{ text = str, face = (bface(false, size)), width = W() - 2 * PAD - tw - PAD },
        HorizontalSpan:new{ width = PAD },
        ImageWidget:new{ file = plugin_dir .. "gear_art/" .. art, width = tw, height = tw },
    }
end

function RelicScreen:gearBody()
    local s = self.state
    local g = s.gear
    local view = self.gear_view
    local back = function(to) return function() self.gear_view = to; self:render("flashui") end end
    if view.item then
        local item
        for _, it in ipairs(g.bag) do if it.id == view.item then item = it end end
        if not item then self.gear_view = { slot = view.slot }; return self:gearBody() end
        return VerticalGroup:new{
            align = "left",
            withArt(item, table.concat(Gear.describe(item), "\n"), 18),
            gap(),
            self:buttons({ {
                { text = "EQUIP", callback = function()
                    Game.equip(s, item.id, view.slot)
                    self.gear_view = { slot = nil }
                    self:save(); self:render("flashui")
                end },
                { text = "BACK", callback = back({ slot = view.slot }) },
            } }),
        }
    elseif view.slot then
        local cur = g.equipped[view.slot]
        local rows = {}
        local fits = {}
        for _, it in ipairs(g.bag) do
            for _, sl in ipairs(Gear.slotsFor(it)) do if sl == view.slot then table.insert(fits, it) end end
        end
        table.sort(fits, function(a, b) return Gear.score(a) > Gear.score(b) end)
        for i = 1, math.min(#fits, 6) do
            local it = fits[i]
            local d = Gear.score(it) - Gear.score(cur)
            local mark = d > 0.5 and "▲ " or (d < -0.5 and "▼ " or "= ")
            table.insert(rows, { { text = mark .. it.name .. "   " .. Gear.summary(it), align = "left",
                callback = back({ slot = view.slot, item = it.id }) } })
        end
        table.insert(rows, {
            { text = "UNEQUIP", enabled = cur ~= nil, callback = function()
                Game.unequip(s, view.slot); self:save(); self:render("flashui")
            end },
            { text = "BACK", callback = back({ slot = nil }) },
        })
        local head = (Gear.SLOT_NAMES[view.slot] or view.slot) .. ":  " .. (cur and table.concat(Gear.describe(cur), "\n") or "empty")
        return VerticalGroup:new{
            align = "left",
            withArt(cur, head, 18),
            gap(),
            text(#fits == 0 and "Nothing in your pack fits here yet." or (#fits .. " in your pack. ▲ better, ▼ worse than what you wear."), 16),
            gap(PAD / 2),
            self:buttons(rows),
        }
    end
    local rows, row = {}, nil
    for i, slot in ipairs(Gear.SLOTS) do
        local it = g.equipped[slot]
        local b = { text = (Gear.SLOT_NAMES[slot] or slot) .. ": " .. (it and it.name or "—"), callback = back({ slot = slot }) }
        if i % 2 == 1 then row = { b }; table.insert(rows, row) else table.insert(row, b) end
    end
    table.insert(row, { text = "BACK", callback = back(nil) })
    -- soft-set tally: how many worn pieces lean into each style, and set progress
    local tally, order = {}, {}
    for _, it in pairs(g.equipped) do
        for _, st in ipairs(Gear.styles(it)) do
            if not tally[st] then table.insert(order, st) end
            tally[st] = (tally[st] or 0) + 1
        end
    end
    table.sort(order, function(a, b) return tally[a] > tally[b] end)
    local parts = {}
    for _, st in ipairs(order) do table.insert(parts, st:gsub("^%l", string.upper) .. " " .. tally[st]) end
    local T = Game.gearTotals(s)
    for key, n in pairs(T.sets) do table.insert(parts, "Set of " .. Gear.SETS[key].name .. " " .. n .. "/4") end
    local styles_line = #parts > 0 and ("Worn styles: " .. table.concat(parts, "   ")) or "Worn styles: none yet. Pieces of one style work together."
    return VerticalGroup:new{
        align = "left",
        text(string.format("GEAR   ·   %d in pack", #g.bag), 20, true),
        text(styles_line, 16),
        gap(PAD / 2),
        self:buttons(rows),
    }
end

-- INVENTORY (inside STATUS) ---------------------------------------------------------------
-- Tabs: GEAR (whole pack, paged, best first, slot filter), INGREDIENTS, BAKED (tap to use).
-- WORN opens the slot view above (gearBody); its BACK returns here.
local INV_PER_PAGE = 6

function RelicScreen:invBody()
    local s = self.state
    local v = self.inv_view
    local function go(nv) return function() self.inv_view = nv; self:render("flashui") end end
    local function tabBtn(id, label)
        return { text = v.tab == id and ("[" .. label .. "]") or label, callback = go({ tab = id, page = 1 }) }
    end
    local tabs = self:buttons({ { tabBtn("gear", "GEAR"), tabBtn("ing", "INGREDIENTS"), tabBtn("baked", "BAKED") } })

    local body
    if v.tab == "gear" and v.item then
        -- one item: full description, what it replaces, EQUIP
        local item
        for _, it in ipairs(s.gear.bag) do if it.id == v.item then item = it end end
        if not item then self.inv_view = { tab = "gear", page = v.page, slot = v.slot }; return self:invBody() end
        local slots = Gear.slotsFor(item)
        local lines = Gear.describe(item)
        for _, sl in ipairs(slots) do
            local cur = s.gear.equipped[sl]
            table.insert(lines, (#slots > 1 and ("Wearing (" .. sl:gsub("ring", "ring ") .. "): ") or "Wearing: ")
                .. (cur and (cur.name .. "   " .. Gear.summary(cur)) or "nothing"))
        end
        local row = {}
        for _, sl in ipairs(slots) do
            table.insert(row, { text = #slots > 1 and ("EQUIP " .. sl:gsub("ring", "RING ")) or "EQUIP", callback = function()
                local msg = Game.equip(s, item.id, sl) and ("Equipped " .. item.name .. ".") or "That item is no longer in your pack."
                self.inv_view = { tab = "gear", page = v.page, slot = v.slot }
                self:save(); self:render("flashui"); self:notify(msg)
            end })
        end
        local salvage_btn = { text = "SALVAGE TO DUST", callback = function()
            UIManager:show(ConfirmBox:new{
                text = string.format("Salvage %s into %d dust?\nThis can't be undone.", item.name, Gear.salvageDust(item)),
                ok_text = "Salvage",
                ok_callback = function()
                    local d = Game.salvageGear(s, item.id)
                    self.inv_view = { tab = "gear", page = v.page, slot = v.slot }
                    self:save(); self:render("flashui")
                    if d then self:notify("+" .. d .. " dust.") end
                end,
            })
        end }
        table.insert(row, { text = "BACK", callback = go({ tab = "gear", page = v.page, slot = v.slot }) })
        -- the item's engraving, beside its description; VIEW ART shows it full size
        local art = Gear.artFor(item)
        local desc
        if art then
            local tw = Screen:scaleBySize(160)
            desc = HorizontalGroup:new{
                align = "top",
                TextBoxWidget:new{ text = table.concat(lines, "\n"), face = (bface(false, 16)),
                    width = W() - 2 * PAD - tw - PAD },
                HorizontalSpan:new{ width = PAD },
                ImageWidget:new{ file = plugin_dir .. "gear_art/" .. art, width = tw, height = tw },
            }
        else
            desc = text(table.concat(lines, "\n"), 18)
        end
        local last = { salvage_btn }
        if art then
            table.insert(last, { text = "VIEW ART", callback = function()
                self.inv_view = { tab = "gear", page = v.page, slot = v.slot, item = item.id, art = true }
                self:render("flashui")
            end })
        end
        if v.art and art then
            local big = math.min(W() - 2 * PAD, Screen:scaleBySize(320))
            body = VerticalGroup:new{
                align = "center",
                ImageWidget:new{ file = plugin_dir .. "gear_art/" .. art, width = big, height = big },
                gap(PAD / 2),
                text(item.name .. "\n" .. Gear.RARITY[item.rarity].name .. "  ·  " .. (Gear.SLOT_NAMES[item.slot] or item.slot), 18),
                gap(PAD / 2),
                self:buttons({ { { text = "BACK", callback = function()
                    self.inv_view = { tab = "gear", page = v.page, slot = v.slot, item = item.id }
                    self:render("flashui")
                end } } }),
            }
        else
            body = VerticalGroup:new{ align = "left", desc, gap(),
                self:buttons({ row }), gap(), self:buttons({ last }) }
        end
    elseif v.tab == "gear" then
        local list = {}
        for _, it in ipairs(s.gear.bag) do
            local fits = not v.slot
            for _, sl in ipairs(Gear.slotsFor(it)) do if sl == v.slot then fits = true end end
            if fits then table.insert(list, it) end
        end
        table.sort(list, function(a, b) return Gear.score(a) > Gear.score(b) end)
        local pages = math.max(1, math.ceil(#list / INV_PER_PAGE))
        local page = math.min(v.page or 1, pages)
        local rows = {}
        for i = (page - 1) * INV_PER_PAGE + 1, math.min(#list, page * INV_PER_PAGE) do
            local it = list[i]
            -- compare against the piece it would replace (for rings, the weaker or empty ring slot)
            local cur
            for n, sl in ipairs(Gear.slotsFor(it)) do
                local w = s.gear.equipped[sl]
                if n == 1 or Gear.score(w) < Gear.score(cur) then cur = w end
            end
            local d = Gear.score(it) - Gear.score(cur)
            local mark = d > 0.5 and "▲ " or (d < -0.5 and "▼ " or "= ")
            table.insert(rows, { { text = mark .. it.name .. "   " .. Gear.summary(it), align = "left",
                callback = go({ tab = "gear", page = page, slot = v.slot, item = it.id }) } })
        end
        if #list == 0 then table.insert(rows, { { text = v.slot and "Nothing for this slot." or "Your pack is empty.", enabled = false } }) end
        for _ = #rows + 1, INV_PER_PAGE do table.insert(rows, { { text = " ", enabled = false } }) end
        table.insert(rows, {
            { text = "<", enabled = page > 1, callback = go({ tab = "gear", page = page - 1, slot = v.slot }) },
            { text = v.slot and ("SLOT: " .. (Gear.SLOT_NAMES[v.slot] or v.slot)) or "SLOT: ALL", callback = function() self:invSlotFilter() end },
            { text = "WORN", callback = function() self.gear_view = { slot = nil }; self:render("flashui") end },
            { text = ">", enabled = page < pages, callback = go({ tab = "gear", page = page + 1, slot = v.slot }) },
        })
        body = VerticalGroup:new{
            align = "left",
            text(string.format("%d in pack (holds %d; past that the weakest is salvaged to dust)   page %d/%d",
                #s.gear.bag, Game.BAG_MAX, page, pages), 16),
            text("▲ better, ▼ worse than what you wear in that slot.", 16),
            gap(PAD / 2),
            self:buttons(rows),
        }
    elseif v.tab == "ing" then
        local lines = {}
        for _, ing in ipairs(Game.shownIngredients(s)) do
            table.insert(lines, string.format("%-10s %d", ing.label, s.inv[ing.key] or 0))
        end
        body = VerticalGroup:new{
            align = "left",
            TextBoxWidget:new{ text = table.concat(lines, "\n"), face = Font:getFace("infont", 20), width = W() - 2 * PAD },
            gap(),
            text("Bake any two on the BAKE tab.", 16),
        }
    else
        local items = pantryItems(s)
        local pages = math.max(1, math.ceil(#items / INV_PER_PAGE))
        local page = math.min(v.page or 1, pages)
        local rows = {}
        for i = (page - 1) * INV_PER_PAGE + 1, math.min(#items, page * INV_PER_PAGE) do
            local key = items[i]
            local r = Game.itemRecipe(key)
            local label = pantryLabel(key)
            table.insert(rows, { { text = string.format("%s:  %s x%d   %s", groupName(key), label, s.inv[key], effectText(itemEffect(key))),
                align = "left",
                callback = function()
                    UIManager:show(ConfirmBox:new{
                        text = "Use " .. label .. "?\n" .. effectText(itemEffect(key)),
                        ok_text = "Use",
                        ok_callback = function()
                            local msg = Game.useBaked(s, key, os.time())
                            self:save(); self:render("flashui")
                            if msg then self:notify(msg) end
                        end,
                    })
                end } })
        end
        if #rows == 0 then table.insert(rows, { { text = "Nothing baked yet.", enabled = false } }) end
        if pages > 1 then
            table.insert(rows, {
                { text = "<", enabled = page > 1, callback = go({ tab = "baked", page = page - 1 }) },
                { text = "page " .. page .. "/" .. pages, enabled = false },
                { text = ">", enabled = page < pages, callback = go({ tab = "baked", page = page + 1 }) },
            })
        end
        body = VerticalGroup:new{
            align = "left",
            text("Tap to use. Fine versions are 1.5x.", 16),
            gap(PAD / 2),
            self:buttons(rows),
        }
    end
    return VerticalGroup:new{
        align = "left",
        text("INVENTORY", 20, true),
        gap(PAD / 2),
        tabs,
        gap(PAD / 2),
        body,
    }, self:buttons({ { { text = "BACK TO STATUS", callback = function() self.inv_view = nil; self:render("flashui") end } } })
end

function RelicScreen:invSlotFilter()
    local dialog
    local rows = { { { text = "All slots", callback = function()
        UIManager:close(dialog); self.inv_view = { tab = "gear", page = 1 }; self:render("flashui")
    end } } }
    local row
    for _, sl in ipairs(Gear.SLOTS) do
        if sl ~= "ring2" then
            local b = { text = Gear.SLOT_NAMES[sl] or sl, callback = function()
                UIManager:close(dialog); self.inv_view = { tab = "gear", page = 1, slot = sl }; self:render("flashui")
            end }
            if not row or #row == 2 then row = { b }; table.insert(rows, row) else table.insert(row, b) end
        end
    end
    table.insert(rows, { { text = "Cancel", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = "Show gear for", buttons = rows }
    UIManager:show(dialog)
end

-- Story scenes -----------------------------------------------------------------------------

local SCENE_HEAD = { sys = "", cantor = "CANTOR", log = "RECOVERED LOG", notice = "" }

function RelicScreen:pageWidget(p)
    local w = W() - 2 * PAD
    if p.kind == "sys" then
        return TextBoxWidget:new{ text = p.text, face = Font:getFace("infont", 18), width = w }
    elseif p.kind == "log" then
        return VerticalGroup:new{
            align = "left",
            text(p.title, 20, true),
            gap(PAD),
            TextBoxWidget:new{ text = p.text, face = (bface(false, 19)), width = w },
        }
    elseif p.kind == "notice" or p.kind == "hold" then
        local first, rest = p.text:match("^([^\n]*)\n?(.*)$")
        return VerticalGroup:new{
            align = "left",
            text(first, 24, true),
            gap(PAD),
            text(rest, 20),
        }
    elseif p.kind == "narration" then
        return text(p.text, 22)
    else
        return text(table.concat(p.lines or {}, "\n\n"), 22)
    end
end

-- pages: list of pages; on_done: called after the last page
function RelicScreen:sceneBody()
    local v = self.viewer
    local p = v.pages[v.i]
    local last = v.i >= #v.pages
    local head = SCENE_HEAD[p.kind] or ""
    local top = head ~= "" and VerticalGroup:new{ align = "left", text(head, 18, true), gap(PAD / 2), rule() }
        or gap(0)
    return VerticalGroup:new{
        align = "left",
        top,
        gap(PAD * 2),
        self:pageWidget(p),
    }, self:buttons({ { {
        text = p.kind == "hold" and p.button or (last and "CLOSE" or "NEXT"),
        hold_callback = p.kind == "hold" and function()
            v.i = v.i + 1
            self:render("flashui")
        end or nil,
        callback = p.kind == "hold" and function() self:notify("Press and hold.") end or function()
            if last then
                self.viewer = nil
                if v.on_done then v.on_done() end
                self:render("flashui")
            else
                v.i = v.i + 1
                self:render("flashui")
            end
        end,
    } } })
end

function RelicScreen:showPendingScene()
    if self.viewer then return true end
    local s = self.state
    local sc = Story.pending(s)
    if not sc then return false end
    self.viewer = {
        i = 1,
        pages = Story.pages(s, sc),
        on_done = function()
            local now = os.time()
            local done = Story.seen(s, now, Game.dayIndex(s, now), Game.dayKey(now))
            self:save()
            if done and done.after == "daily_prompt" and not s.daily_id and not s.daily_done then
                UIManager:nextTick(function() self:addQuestDialog(true) end)
            end
        end,
    }
    return true
end

function RelicScreen:logsDialog()
    local dialog
    local rows = {}
    for _, entry in ipairs(self.state.story.logs) do
        table.insert(rows, { { text = entry.title, callback = function()
            UIManager:close(dialog)
            local p = Story.logPage(entry)
            if p then
                self.viewer = { i = 1, pages = { p } }
                self:render("flashui")
            end
        end } })
    end
    table.insert(rows, { { text = "Close", callback = function() UIManager:close(dialog) end } })
    dialog = PinnedDialog:new{ title = "Recovered logs", buttons = rows }
    UIManager:show(dialog)
end

-- Render ------------------------------------------------------------------------------------

-- Scrolling page bodies (Mike, 2026-10-22). A body that fits is returned as is. A taller one
-- is rebuilt narrower (room for the scroll bar) and wrapped in KOReader's ScrollableContainer:
-- swipe up/down to page through it, or drag the bar. The scroll position is kept while the
-- same page re-renders (after a tap) and starts at the top on a new page.
function RelicScreen:pageKey()
    return table.concat({ currentTheme(), self.tab, tostring(self.detail_id or ""), self.quest_all and "all" or "",
        self.gear_view and "gear" or "", self.inv_view and "inv" or "", self.records_view and "rec" or "" }, "|")
end

function RelicScreen:fitBody(body, build, w, h)
    local key = self:pageKey()
    local keep_y = 0
    if self._scroller then
        if self._scroll_key == key then keep_y = self._scroller:getScrolledOffset().y end
        self._scroller:onCloseWidget()  -- frees its screen-sized scratch buffer
        self._scroller = nil
    end
    self.cropping_widget = nil
    if h <= 0 or body:getSize().h <= h then return body end
    -- untested on the Kindle when written: if anything here fails, show the page unscrolled
    local ok, sc = pcall(function()
        local narrow = build(ScrollableContainer:getScrollbarWidth())
        local c = ScrollableContainer:new{
            dimen = Geom:new{ w = w, h = h },
            show_parent = self,
            narrow,
        }
        c:setScrolledOffset(Geom:new{ x = 0, y = math.max(0, math.min(keep_y, narrow:getSize().h - h)) })
        return c
    end)
    if not ok then
        logger_warn("Relic: page scroll failed, showing it unscrolled:", tostring(sc))
        return body
    end
    self._scroller, self._scroll_key, self.cropping_widget = sc, key, sc
    return sc
end

-- The page body for the current tab, and its pinned button row (nil when it has none).
function RelicScreen:pageBody()
    if self.tab == "quests" and self.detail_id then return self:detailBody()
    elseif self.tab == "quests" and self.quest_all then return self:allQuestsBody()
    elseif self.tab == "quests" then return self:questsBody()
    elseif self.tab == "bake" then return self:bakeBody()
    elseif self.tab == "practice" then return self:practiceBody()
    elseif self.tab == "explore" then return self:exploreBody()
    elseif self.tab == "status" and self.gear_view then return self:gearBody()
    elseif self.tab == "status" and self.inv_view then return self:invBody()
    elseif self.tab == "status" and self.records_view then return self:recordsBody()
    else return self:statusBody() end
end

function RelicScreen:render(refresh)
    local now = os.time()
    self.cropping_widget = nil  -- set again by fitBody when this page scrolls
    if self.state.paused then return self:renderPaused(refresh) end
    Game.tick(self.state, now)
    Story.process(self.state, now, Game.dayIndex(self.state, now))
    local promo = not self.state.fight and Game.pendingPromotion(self.state)
    if promo then return self:renderPromotion(promo, refresh) end
    local body
    local scene_nav
    if self:showPendingScene() then body, scene_nav = self:sceneBody()
    elseif currentTheme() == "lcars" and not (self.tab == "explore" and self.state.fight) then return self:renderLcars(refresh)
    end
    local function build(shrink)
        W_OVERRIDE = shrink and (Screen:getWidth() - shrink) or nil
        local ok, res, res2 = pcall(self.pageBody, self)
        W_OVERRIDE = nil
        if not ok then error(res) end
        return res, res2
    end
    local foot
    if not body then body, foot = build() end

    local nav = scene_nav or self:nav()
    local in_battle = scene_nav or (self.tab == "explore" and self.state.fight)
    local head = not in_battle and self:header()
    -- the page's buttons sit pinned just above the tabs on every page; the page above them
    -- scrolls when it's too tall (Mike, 2026-10-22)
    local fh = foot and (foot:getSize().h + math.floor(PAD / 2)) or 0
    if head then
        body = self:fitBody(body, build, W() - 2 * PAD,
            Screen:getHeight() - head:getSize().h - nav:getSize().h - 2 * PAD - fh)
    end
    local top = in_battle and VerticalGroup:new{ align = "left", body }
        or VerticalGroup:new{ align = "left", head, body }
    local free = Screen:getHeight() - top:getSize().h - nav:getSize().h - 2 * PAD - fh
    self[1] = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        padding = PAD,
        width = Screen:getWidth(),
        height = Screen:getHeight(),
        VerticalGroup:new{
            align = "left",
            top,
            VerticalSpan:new{ width = math.max(0, free) },
            foot or VerticalSpan:new{ width = 0 },
            VerticalSpan:new{ width = foot and math.floor(PAD / 2) or 0 },
            nav,
        },
    }
    self:save()
    UIManager:setDirty(self, refresh or "ui")
end

function RelicScreen:onClose()
    self:save()
    if Relic_ref and Relic_ref.screen == self then Relic_ref.screen = nil end
    pcall(writeLockScreen)
    UIManager:close(self, "flashui")
    return true
end

-- Lock screen ------------------------------------------------------------------------------

function writeLockScreen()
    local store = LuaSettings:open(SAVE_PATH)
    local s = store:readSetting("state")
    if not s then return end
    s = Game.migrate(s)
    local now = os.time()
    Game.tick(s, now)
    local daily
    if s.paused then daily = "Paused since " .. os.date("%d %B", s.paused.since) .. ". Tap RESUME in Relic to restart."
    elseif s.daily_done then daily = "Done. Rest easy."
    elseif s.daily_id then
        local q = Game.findQuest(s, s.daily_id)
        daily = q and q.title or "Not set"
    else daily = "Not set. Pick one." end
    local quests = {}
    for _, q in ipairs(Game.orderedQuests(s, now)) do
        if q.id ~= s.daily_id and #quests < 5 then
            local due = Game.dueText(q, now)
            table.insert(quests, (due and ("[" .. due .. "] ") or "") .. (q.out and "OUT: " or "") .. q.title)
        end
    end
    Lock.render{
        stats = string.format("LV %d   STREAK %d   INTEGRITY %d%%\nCHARGE %d/%d   FOOTING %d\nSTR %d  RES %d  FOC %d  ACU %d  KIN %d\nTRAIN %d of %d left   GRIT %d/%d",
            s.level, s.streak, s.integrity, s.charge, Game.maxCharge(s.level, s), s.footing.rank,
            s.stats.str, s.stats.res, s.stats.foc, s.stats.acu, s.stats.kin or 0,
            (Game.trainLeft(s, now)), Game.trainSlots(s),
            s.grit or 0, Game.gritCap(s)),
        daily = daily,
        quests = quests,
        line = s.paused and "Relic is paused." or Game.companionLine(s, now),
    }
end

-- Plugin wrapper ---------------------------------------------------------------------------

local Relic = WidgetContainer:extend{
    name = "relic",
    is_doc_only = false,
}

-- Open Relic once when KOReader starts, so the device boots into it.
local opened_at_startup = false

function Relic:init()
    Dispatcher:registerAction("relic_open", { category = "none", event = "OpenRelic", title = _("Open Relic"), general = true })
    if self.ui and self.ui.menu then self.ui.menu:registerToMainMenu(self) end
    if not opened_at_startup then
        opened_at_startup = true
        pcall(Meditate.releaseStale)
        -- Lock screen: take over KOReader's screensaver and redraw it before each sleep.
        pcall(Lock.overrideAds)
        pcall(Lock.configure)
        local Screensaver = require("ui/screensaver")
        local orig_setup = Screensaver.setup
        Screensaver.setup = function(ss, ...)
            local ok, err = pcall(writeLockScreen)
            if not ok then logger_warn("Relic: lock screen failed", err) end
            return orig_setup(ss, ...)
        end
        pcall(writeLockScreen)
        UIManager:nextTick(function() self:onOpenRelic() end)
        -- Quiet daily update check, after boot settles.
        UIManager:scheduleIn(15, function() self:checkForUpdate(false) end)
        self:startJobTimer()
    end
end

-- Daily jobs while KOReader stays up (v40). Mike leaves Relic open and the Kindle only sleeps
-- and wakes, so startup / open / NetworkConnected alone almost never fired: the status report,
-- backups and phone pull only ran on restart days. Now they also run 90 s after every wake and
-- every 30 min while awake, when Wi-Fi is up. Each job keeps its own throttle (status, backup,
-- chronicle once a day; phone pull every 10 min). Review fixes: the phone pull goes first and a
-- network failure there stops the batch (each request can wait 10-15 s on the UI thread on a
-- half-connected Wi-Fi); no update check here (an install mid-play swaps files under the running
-- code; updates stay at startup, on Wi-Fi connect and in the menu); guards use time since boot,
-- not the wall clock, so a clock correction can't stall them.
local JOBS_EVERY = 30 * 60
local jobs_fn, jobs_last, resume_at = nil, nil, nil
local function since_boot()
    local okt, t = pcall(function() return require("ui/time").to_s(UIManager:getElapsedTimeSinceBoot()) end)
    return okt and t or os.time()
end
function Relic:dueJobs(fresh)
    if Relic.restoring then return end
    local now = since_boot()
    if not fresh and jobs_last and now - jobs_last < 60 and now >= jobs_last then return end  -- several plugin instances
    local okc, online = pcall(Inbox.online)
    if not okc or not online then return end
    jobs_last = now
    local okp, n, why = pcall(self.pullInbox, self, false)
    if not okp then logger_warn("Relic: background pull failed", tostring(n)); return end
    if why == "failed" or why == "offline" then return end  -- network not really up: don't stack timeouts
    for _, job in ipairs({ "runBackup", "sendStatus" }) do
        local ok, err = pcall(self[job], self, false)
        if not ok then logger_warn("Relic: background " .. job .. " failed", tostring(err)) end
    end
end

function Relic:startJobTimer()
    if jobs_fn then return end
    jobs_fn = function()
        self:dueJobs()
        UIManager:scheduleIn(JOBS_EVERY, jobs_fn)
    end
    UIManager:scheduleIn(JOBS_EVERY, jobs_fn)
end

function Relic:onResume()
    local now = since_boot()
    if resume_at and now - resume_at < 30 and now >= resume_at then return end  -- one wake, one schedule
    resume_at = now
    UIManager:scheduleIn(90, function() self:dueJobs(true) end)  -- Wi-Fi takes a while to come back
end

function Relic:onNetworkConnected()
    UIManager:scheduleIn(5, function() self:checkForUpdate(false) end)
    UIManager:scheduleIn(8, function() self:pullInbox(false); self:runBackup(false); self:sendStatus(false) end)
end

local function inboxStore()
    return LuaSettings:open(DataStorage:getSettingsDir() .. "/relic_inbox.lua")
end

-- Daily save backup to Todoist. force = user asked, so report the result.
function Relic:runBackup(force)
    if Relic.restoring then return end
    if Relic.screen then Relic.screen:save() end
    local day = 0
    local fs = LuaSettings:open(SAVE_PATH):readSetting("state")
    if fs then day = Game.dayIndex(Game.migrate(fs), os.time()) end
    local store = inboxStore()
    local ok, res, why = pcall(Backup.run, Inbox, store, SAVE_PATH, day, force)
    if not ok then logger_warn("Relic backup error", res); res, why = nil, "failed" end
    -- the chronicle has its own once-a-day check; a skipped save backup doesn't skip it
    local cok, cres, cwhy = pcall(Chronicle.backup, Inbox, store, force)
    if not cok then logger_warn("Relic chronicle error", cres)
    elseif not cres and cwhy ~= "skipped" and cwhy ~= "no_config" then logger_warn("Relic chronicle backup:", cwhy) end
    if force then
        UIManager:show(InfoMessage:new{ text = res and "Save backed up to Todoist." or ({
            no_config = "No Todoist token in relic_config.lua.",
            no_project = "No Todoist project named Relic.",
            too_large = "Save is too large to back up. Tell Claude.",
            no_save = "No save yet.",
        })[why] or "Backup failed. Try again later." })
    end
end

-- Daily status report to Todoist (see status.lua). force = user asked, so report the result.
local function crashTail(store)
    local lfs = require("libs/libkoreader-lfs")
    for _, dir in ipairs({ DataStorage:getDataDir(), "." }) do
        local path = dir .. "/crash.log"
        local attr = lfs.attributes(path)
        if attr and attr.mode == "file" then
            local stamp = tostring(attr.size) .. ":" .. tostring(attr.modification)
            if store:readSetting("crash_stamp") == stamp then return nil, stamp end
            local f = io.open(path, "r")
            if not f then return nil, stamp end
            if attr.size > 8192 then f:seek("set", attr.size - 8192) end
            local lines = {}
            for l in f:lines() do table.insert(lines, l) end
            f:close()
            -- KOReader writes crash.log every run; keep only lines that point at a problem.
            local tail = {}
            for _, l in ipairs(lines) do
                if l:find("Relic") or l:find("relic") or l:find("ERROR") or l:find("traceback") or l:find("%.lua:%d+") then
                    table.insert(tail, l:sub(1, 200))
                    if #tail > 24 then table.remove(tail, 1) end
                end
            end
            if #tail == 0 then return nil, stamp end
            return tail, stamp
        end
    end
end

function Relic:statusText(s, store, now)
    local stage = Game.currentStage(s)
    local ri, r = Game.currentRegion(s)
    local tail, stamp = crashTail(store)
    local info = {
        running = RUNNING_VERSION, installed = Updater.installedVersion(), update = Updater.lastResult(),
        errors = errorStore():readSetting("status_errors") or {}, crash = tail,
        stage = stage, stage_name = Game.STAGE_NAMES and Game.STAGE_NAMES[stage],
        region = ri and (tostring(ri) .. (r and r.name and (" " .. r.name) or "")) or nil,
        total_km = Game.ROUTE and Game.ROUTE.total_km, day = Game.dayIndex(s, now),
        xp_next = Game.xpToNext(s.level or 1), now = now,
        late = function(q) local d = Game.daysLeft(q, now); return d and d < 0 end,
    }
    local hist = store:readSetting("status_history") or {}
    local line = Status.historyLine(s, info)
    if hist[#hist] and hist[#hist]:sub(1, 10) == line:sub(1, 10) then hist[#hist] = line else table.insert(hist, line) end
    while #hist > Status.HISTORY do table.remove(hist, 1) end
    info.history = hist
    return Status.build(s, info), hist, stamp
end

function Relic:sendStatus(force)
    if Relic.restoring then return end
    local store = inboxStore()
    local s
    if Relic.screen then Relic.screen:save(); s = Relic.screen.state
    else
        s = LuaSettings:open(SAVE_PATH):readSetting("state")
        if s then s = Game.migrate(s) end
    end
    local res, why
    if not s then res, why = nil, "no_save"
    else
        local hist, stamp, sent_errors
        local ok, r1, r2 = pcall(Status.run, Inbox, store, function()
            local text
            sent_errors = #(errorStore():readSetting("status_errors") or {})
            text, hist, stamp = self:statusText(s, store, os.time())
            return text
        end, force)
        if not ok then logger_warn("Relic status error", r1); res, why = nil, "failed"
        else res, why = r1, r2 end
        if res then
            -- drop only what was reported; warnings logged during the upload stay for next time
            local es = errorStore()
            local list = es:readSetting("status_errors") or {}
            for _ = 1, math.min(sent_errors or 0, #list) do table.remove(list, 1) end
            es:saveSetting("status_errors", list)
            es:flush()
            store:saveSetting("status_history", hist)
            if stamp then store:saveSetting("crash_stamp", stamp) end
            store:flush()
        end
    end
    if force then
        UIManager:show(InfoMessage:new{ text = res and "Status report sent to Todoist." or ({
            no_config = "No Todoist token in relic_config.lua.",
            no_project = "No Todoist project named Relic.",
            no_save = "No save yet.",
        })[why] or "Status report failed. Try again later." })
    end
end

function Relic:restoreBackup()
    local ok, data, when = pcall(Backup.newest, Inbox, inboxStore())
    if not ok or not data then
        UIManager:show(InfoMessage:new{ text = (when == "none") and "No backup found in Todoist." or "Couldn't read backups from Todoist." })
        return
    end
    UIManager:show(ConfirmBox:new{
        text = "Restore the backup from " .. os.date("%b %d, %H:%M", when) .. "?\nThe current save is kept as relic_state.lua.before_restore.",
        ok_text = "Restore",
        ok_callback = function()
            Relic.restoring = true
            if Backup.restore(data, SAVE_PATH) then
                UIManager:askForRestart("Backup restored. Restarting.")
            else
                Relic.restoring = false
                UIManager:show(InfoMessage:new{ text = "Restore failed." })
            end
        end,
    })
end

-- Phone inbox: pull new quests from Todoist. force = user asked, so report the result.
local INBOX_MIN_GAP = 10 * 60
function Relic:pullInbox(force)
    if Relic.restoring then return end  -- saves are frozen until restart; don't consume Todoist tasks
    local store = LuaSettings:open(DataStorage:getSettingsDir() .. "/relic_inbox.lua")
    if not force and os.time() - (store:readSetting("last_pull") or 0) < INBOX_MIN_GAP then return end
    local screen = Relic.screen
    local fstore, s
    if screen then s = screen.state
    else
        fstore = LuaSettings:open(SAVE_PATH)
        s = fstore:readSetting("state")
        if not s then return end
        s = Game.migrate(s)
    end
    local loot_added = {}
    local function add(q)
        if q.loot then
            local name, usd = Game.parseLoot(q.title)
            if not name then return false end  -- no price: leave the task in Todoist
            Game.addLoot(s, name, usd)
            table.insert(loot_added, name)
            if screen then screen:save() else fstore:saveSetting("state", s); fstore:flush() end
            return "loot"
        end
        local quest = Game.addQuest(s, q.title, q.tier, q.main)
        quest.dread = q.dread or nil
        quest.out = q.out or nil
        quest.due = q.due or nil
        if q.rep then Game.setRepeat(s, quest.id, q.rep) end
        for _, t in ipairs(q.steps) do Game.addStep(s, quest.id, t) end
        if q.daily and not s.daily_id and not s.daily_done then Game.setDaily(s, quest.id) end
        if screen then screen:save() else fstore:saveSetting("state", s); fstore:flush() end
    end
    local gained, synced = 0, false
    local function steps(days)
        local future
        gained, future = Game.syncSteps(s, days)
        synced = true
        if screen then screen:save() else fstore:saveSetting("state", s); fstore:flush() end
        return future == 0  -- keep the tasks if the Kindle clock looks behind the phone
    end
    local ok, n, why = pcall(Inbox.pull, store, add, force, steps)
    if not ok then logger_warn("Relic inbox error", n); n, why = nil, "failed" end
    local result_n, result_why = n, why
    local parts = {}
    if n then n = n - #loot_added end
    if n and n > 0 then table.insert(parts, string.format("%d quest%s from your phone.", n, n == 1 and "" or "s")) end
    if #loot_added > 0 then table.insert(parts, "New loot: " .. table.concat(loot_added, ", ") .. ".") end
    if gained > 0 then table.insert(parts, string.format("+%d Range from steps.", gained)) end
    if screen and synced then screen:render() end
    if screen and #parts > 0 then
        if not synced then screen:render() end
        screen:notify(table.concat(parts, " "))
    elseif force then
        local msg = n and (n == 0 and (synced and "Steps synced. No new quests." or "No new quests or steps from your phone.")
            or string.format("%d quests pulled.", n)) or ({
            no_config = "No Todoist token in relic_config.lua.",
            offline = "Not connected to Wi-Fi.",
            no_project = "No Todoist project named Relic.",
            failed = "Couldn't reach Todoist. Try again later.",
        })[why] or "Inbox failed."
        UIManager:show(InfoMessage:new{ text = msg })
    end
    return result_n, result_why
end

-- force = true: user asked from the menu, so always report the result.
function Relic:checkForUpdate(force)
    local ok, result, version = pcall(Updater.check, force)
    if not ok then
        if force then UIManager:show(InfoMessage:new{ text = _("Update check failed.") }) end
        return
    end
    if result == "installed" then
        UIManager:show(ConfirmBox:new{
            text = string.format(_("Relic update %d installed.\nRestart now to apply it?"), version),
            ok_text = _("Restart"),
            ok_callback = function() UIManager:askForRestart() end,
        })
    elseif force then
        local msg = ({
            no_config = _("No update source. Set public_repo in koreader/settings/relic_config.lua."),
            offline = _("Not connected to Wi-Fi."),
            failed = _("Update check failed. Try again later."),
            current = _("Relic is up to date."),
        })[result] or result
        UIManager:show(InfoMessage:new{ text = msg })
    end
end

function Relic:rollbackUpdate()
    if not Updater.canRollback() then
        UIManager:show(InfoMessage:new{ text = _("No previous version to roll back to.") })
        return
    end
    UIManager:show(ConfirmBox:new{
        text = _("Roll back to the previous Relic version? Your save is not affected."),
        ok_text = _("Roll back"),
        ok_callback = function()
            if Updater.rollback() then
                UIManager:askForRestart(_("Rolled back. Restarting to apply."))
            else
                UIManager:show(InfoMessage:new{ text = _("Rollback failed.") })
            end
        end,
    })
end

function Relic:addToMainMenu(menu_items)
    menu_items.relic = {
        text = _("Relic"),
        sorting_hint = "tools",
        sub_item_table = {
            { text = _("Open Relic"), callback = function() self:onOpenRelic() end },
            { text = _("Pull quests and steps from phone"), keep_menu_open = true, callback = function() self:pullInbox(true) end },
            { text = _("Back up save now"), keep_menu_open = true, callback = function() self:runBackup(true) end },
            { text = _("Send status report now"), keep_menu_open = true, callback = function() self:sendStatus(true) end },
            { text = _("Restore save from backup"), keep_menu_open = true, callback = function() self:restoreBackup() end },
            { text = _("Check for updates"), keep_menu_open = true, callback = function() self:checkForUpdate(true) end },
            { text = _("Roll back last update"), keep_menu_open = true, callback = function() self:rollbackUpdate() end },
            { text_func = function() return string.format(_("Version %d"), Updater.installedVersion()) end, enabled = false },
        },
    }
end

function Relic:onOpenRelic()
    if Relic.restoring then
        UIManager:show(InfoMessage:new{ text = "Backup restored. Restart KOReader to finish before playing." })
        return true
    end
    -- already open: don't stack a second screen (its stale copy of the save would overwrite
    -- the live one on exit)
    if Relic.screen then Relic.screen:render("flashui"); return true end
    local screen = RelicScreen:new{}
    Relic.screen = screen
    UIManager:show(screen, "flashui")
    UIManager:scheduleIn(3, function() self:pullInbox(false); self:runBackup(false); self:sendStatus(false) end)
    return true
end

Relic_ref = Relic
-- exposed for testing
Relic.RelicScreen = RelicScreen
Relic.Updater = Updater

return Relic
