--[[
Relic lock screen.

Before the Kindle sleeps, Relic draws today's Daily Quest, the next quests,
stats and one Cantor line into a PNG, and KOReader's screensaver shows it
(screensaver type "random image" pointed at a folder holding only that PNG).

On Kindles with Amazon ads ("Special Offers"), KOReader turns its own
screensaver off and lets the ads show. Mike chose to override that on his
device: supportsScreensaver() is forced on, and the ad screensaver module is
unloaded while KOReader runs and reloaded when it exits.
]]

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local Screen = Device.screen

local Lock = {}

Lock.dir = DataStorage:getDataDir() .. "/relic_lockscreen"
Lock.file = Lock.dir .. "/relic.png"

local function blanket(action)
    pcall(function()
        local lipc = require("liblipclua")
        local h = lipc.init("com.github.koreader.relic")
        if h then
            h:set_string_property("com.lab126.blanket", action, "ad_screensaver")
            h:close()
        end
    end)
end

-- Let KOReader draw the lock screen on an ad-supported Kindle.
function Lock.overrideAds()
    if not (Device.isKindle and Device:isKindle() and Device.isSpecialOffers) then return end
    if Device._relic_ads_overridden then return end
    Device._relic_ads_overridden = true
    Device.supportsScreensaver = function() return true end
    blanket("unload")
    local orig_exit = Device.exit
    Device.exit = function(self, ...)
        blanket("load")
        return orig_exit(self, ...)
    end
    logger.info("Relic: ad lock screen overridden")
end

-- Point KOReader's screensaver at our image folder.
function Lock.configure()
    if lfs.attributes(Lock.dir, "mode") ~= "directory" then lfs.mkdir(Lock.dir) end
    G_reader_settings:saveSetting("screensaver_type", "random_image")
    G_reader_settings:saveSetting("screensaver_dir", Lock.dir)
    G_reader_settings:makeFalse("screensaver_show_message")
end

-- lines: { title=, daily=, quests={...}, stats=, line= }
function Lock.render(info)
    local w, h = Screen:getWidth(), Screen:getHeight()
    local pad = Screen:scaleBySize(28)
    local inner = w - 2 * pad
    local function tb(str, size, bold, face)
        return TextBoxWidget:new{
            text = str, width = inner, bold = bold,
            face = Font:getFace(face or (bold and "tfont" or "cfont"), size),
        }
    end
    local function rule()
        return LineWidget:new{ background = Blitbuffer.COLOR_BLACK, dimen = Geom:new{ w = inner, h = Size.line.thick } }
    end
    local function gap(n) return VerticalSpan:new{ width = n or pad / 2 } end

    local group = VerticalGroup:new{
        align = "left",
        tb("RELIC", 34, true),
        tb(info.stats, 20, false, "infont"),
        gap(), rule(), gap(),
        tb("TODAY'S DAILY DIRECTIVE", 18, true),
        tb(info.daily, 26, true),
        gap(pad), tb("QUESTS", 18, true),
    }
    if #info.quests == 0 then
        table.insert(group, tb("None open.", 22))
    else
        for _, q in ipairs(info.quests) do table.insert(group, tb("• " .. q, 22)) end
    end
    table.insert(group, gap(pad))
    table.insert(group, rule())
    table.insert(group, gap())
    table.insert(group, tb("> " .. info.line, 22))

    local frame = FrameContainer:new{
        background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = pad,
        width = w, height = h,
        group,
    }
    local bb = Blitbuffer.new(w, h, Blitbuffer.TYPE_BB8)
    bb:fill(Blitbuffer.COLOR_WHITE)
    frame:paintTo(bb, 0, 0)
    if lfs.attributes(Lock.dir, "mode") ~= "directory" then lfs.mkdir(Lock.dir) end
    local ok, err = pcall(function() bb:writePNG(Lock.file) end)
    bb:free()
    frame:free()
    if not ok then logger.warn("Relic: lock screen write failed", err) end
    return ok
end

return Lock
