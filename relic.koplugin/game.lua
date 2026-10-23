--[[
Relic prototype: game rules. Pure Lua, no KOReader dependencies,
so it can be tested on its own with luajit.
All numbers are placeholders to tune during the 30-day test.
]]

local Game = {}

Game.TIERS = {
    { key = "minor",    label = "Minor",    xp = 10 },
    { key = "standard", label = "Standard", xp = 25 },
    { key = "major",    label = "Major",    xp = 60 },
    { key = "epic",     label = "Epic",     xp = 150 },
}
local TIER_BY_KEY = {}
for _, t in ipairs(Game.TIERS) do TIER_BY_KEY[t.key] = t end

Game.BOOK = { ingredients = {}, recipes = {}, skill_drops = {} }  -- set by main.lua from recipes.lua

local DAY = 24 * 60 * 60
local GRACE_DAYS = 7
local MINOR_SOFTCAP = 8

function Game.dayKey(t) return os.date("%Y-%m-%d", t) end
local function dayKey(t) return os.date("%Y-%m-%d", t) end

local function dayStart(t)
    local d = os.date("*t", t)
    d.hour, d.min, d.sec = 0, 0, 0
    return os.time(d)
end

function Game.xpToNext(level)
    return math.floor(60 * level ^ 1.3 + 0.5)
end

-- s is optional; with it, stats add their bonus.
-- Equipped gear adds to the stats (and HP/Charge directly).
function Game.gearTotals(s)
    local T = { aff = {}, uniq = {}, sets = {} }
    local eq = s and s.gear and s.gear.equipped
    if not eq then return T end
    for slot, item in pairs(eq) do
        if type(item) == "table" then
            for k, v in pairs(item.stats or {}) do T[k] = (T[k] or 0) + v end
            for _, a in ipairs(item.affixes or {}) do T.aff[a.k] = (T.aff[a.k] or 0) + a.v end
            if item.unique then T.uniq[item.unique] = true end
            if item.set then
                -- both ring slots count as one set slot
                local key = item.set .. ((slot == "ring1" or slot == "ring2") and ":ring" or (":" .. slot))
                if not T._setslot then T._setslot = {} end
                if not T._setslot[key] then
                    T._setslot[key] = true
                    T.sets[item.set] = (T.sets[item.set] or 0) + 1
                end
            end
            if slot == "main" then T.kind = item.kind end
        end
    end
    -- set bonuses that are plain numbers
    if (T.sets.retribution or 0) >= 2 then T.aff.thorns = (T.aff.thorns or 0) + 10 end
    if (T.sets.retribution or 0) >= 4 then T.aff.lifesteal = (T.aff.lifesteal or 0) + 10; T.uniq.sublime = true end
    if (T.sets.serpent or 0) >= 2 then T.uniq.venom = true end
    if (T.aff.stack2 or 0) > 1 then T.aff.stack2 = 1 end
    return T
end

function Game.maxCharge(level, s)
    local T = Game.gearTotals(s)
    return 10 + 2 * level + (s and s.stats and math.floor((s.stats.foc + (T.foc or 0)) / 2) or 0) + (T.charge or 0)
end
function Game.maxHp(level, s)
    local T = Game.gearTotals(s)
    return 20 + 4 * level + (s and s.stats and math.floor((s.stats.res + (T.res or 0)) / 2) or 0) + (T.hp or 0)
end

-- Gear bag and equipping. Items keep a stable id.
-- The pack holds BAG_MAX items; past that the weakest one is salvaged into dust
-- (keeps the save small enough for the daily backup). Returns item, salvaged-or-nil.
Game.BAG_MAX = 60
function Game.addItem(s, item)
    s.gear = s.gear or { equipped = {}, bag = {}, next_id = 1 }
    item.id = s.gear.next_id
    s.gear.next_id = s.gear.next_id + 1
    table.insert(s.gear.bag, item)
    local salvaged
    if #s.gear.bag > Game.BAG_MAX and Game.GEAR then
        local wi, ws
        for i, it in ipairs(s.gear.bag) do
            local sc = Game.GEAR.score(it)
            if not ws or sc < ws then wi, ws = i, sc end
        end
        salvaged = table.remove(s.gear.bag, wi)
        s.inv.dust = (s.inv.dust or 0) + (salvaged.rarity or 1)
    end
    return item, salvaged
end

function Game.equip(s, id, slot)
    local g = s.gear
    for i, item in ipairs(g.bag) do
        if item.id == id then
            local ok = (item.slot == slot) or ((item.slot == "ring1" or item.slot == "ring2") and (slot == "ring1" or slot == "ring2"))
            if not ok then return false end
            table.remove(g.bag, i)
            if g.equipped[slot] then table.insert(g.bag, g.equipped[slot]) end
            g.equipped[slot] = item
            local maxhp = Game.maxHp(s.level, s)
            if s.hp > maxhp then s.hp = maxhp end
            s.charge = math.min(s.charge, Game.maxCharge(s.level, s))
            return true
        end
    end
    return false
end

function Game.unequip(s, slot)
    local g = s.gear
    if not g.equipped[slot] then return false end
    table.insert(g.bag, g.equipped[slot])
    g.equipped[slot] = nil
    s.hp = math.min(s.hp, Game.maxHp(s.level, s))
    s.charge = math.min(s.charge, Game.maxCharge(s.level, s))
    return true
end

-- Class seed from the three starting Sacrifices (Kindle 4, goat 3, drake 5 Growth).
Game.GROWTH = { str = 2, res = 5, foc = 2, acu = 3 }
Game.STAT_NAMES = { { "str", "Strength" }, { "res", "Resistance" }, { "foc", "Focus" }, { "acu", "Acuity" }, { "kin", "Kinesthetics" } }

-- Features open by day (placeholder for level + Restoration Quest unlocks).
Game.UNLOCK_DAY = { bake = 0, map = 0, combat = 0 }  -- map open from day 0 at Mike's call (2026-09-29)
function Game.unlocked(s, feature, now)
    return Game.dayIndex(s, now or os.time()) >= (Game.UNLOCK_DAY[feature] or 0)
end
function Game.daysUntil(s, feature, now)
    return math.max(0, (Game.UNLOCK_DAY[feature] or 0) - Game.dayIndex(s, now or os.time()))
end

Game.SKILLS = {}  -- set by main.lua from skills.lua
local SKILL_DAILY_FULL = 3

-- Save format version. Bump when the state shape changes, and add a step to migrate().
Game.SAVE_VERSION = 14

local function newStory()
    return {
        fired = {},          -- scene id -> true once shown or queued
        queue = {},          -- scene ids waiting to be shown
        logs = {},           -- recovered logs: { id=, title= } in order found
        scheduled = {},      -- { id=, day= } scenes due on a later day
        silent_day = nil,    -- Cantor says nothing on this day key
        misses_in_row = 0,
        kept_days = {},      -- day index -> true for kept Daily Quests
    }
end

-- Rank ladder (Mike, 2026-10-19; respaced 2026-10-22). 12 ranks, Fleet Admiral at about a
-- year of play (level 40). Spaced by time, not by level: levels come fast early, so the early
-- ranks sit further apart in levels. At Mike's day-17 pace (level 10) he is an Ensign working
-- toward Lieutenant JG. pips = solid pips, hollow = hollow pips after them, bar = admiral's bar.
Game.RANKS = {
    { name = "Cadet",               abbr = "CDT",    level = 1,  pips = 0, hollow = 1 },
    { name = "Ensign",              abbr = "ENS",    level = 7,  pips = 1 },
    { name = "Lieutenant JG",       abbr = "LTJG",   level = 12, pips = 1, hollow = 1 },
    { name = "Lieutenant",          abbr = "LT",     level = 16, pips = 2 },
    { name = "Lieutenant Commander", abbr = "LTCMDR", level = 19, pips = 2, hollow = 1 },
    { name = "Commander",           abbr = "CMDR",   level = 22, pips = 3 },
    { name = "Captain",             abbr = "CAPT",   level = 25, pips = 4 },
    { name = "Commodore",           abbr = "CDRE",   level = 28, pips = 1, bar = true },
    { name = "Rear Admiral",        abbr = "RADM",   level = 31, pips = 2, bar = true },
    { name = "Vice Admiral",        abbr = "VADM",   level = 34, pips = 3, bar = true },
    { name = "Admiral",             abbr = "ADM",    level = 37, pips = 4, bar = true },
    { name = "Fleet Admiral",       abbr = "FADM",   level = 40, pips = 5, bar = true },
}

function Game.rankIndex(level)
    local idx = 1
    for i, r in ipairs(Game.RANKS) do if level >= r.level then idx = i end end
    return idx
end

-- total XP needed to reach a level from level 1
function Game.xpToLevel(level)
    local t = 0
    for l = 1, level - 1 do t = t + Game.xpToNext(l) end
    return t
end

-- where the player stands on the ladder
function Game.rankInfo(s)
    local i = Game.rankIndex(s.level)
    local r, nxt = Game.RANKS[i], Game.RANKS[i + 1]
    local top = Game.RANKS[#Game.RANKS]
    local have = Game.xpToLevel(s.level) + (s.xp or 0)
    local info = { index = i, rank = r, next = nxt, count = #Game.RANKS,
        pct_top = math.min(1, have / math.max(1, Game.xpToLevel(top.level))) }
    if nxt then
        local a, b = Game.xpToLevel(r.level), Game.xpToLevel(nxt.level)
        info.pct_next = math.max(0, math.min(1, (have - a) / math.max(1, b - a)))
    else
        info.pct_next = 1
    end
    return info
end

-- a promotion not shown yet: returns the rank index, or nil
function Game.pendingPromotion(s)
    local i = Game.rankIndex(s.level)
    if i > (s.rank_seen or 1) then return i end
end

function Game.migrate(s)
    s.save_version = s.save_version or 1
    if s.save_version < 2 then
        s.story = s.story or newStory()
        s.route = s.route or { km = 0, guardians = {} }
        s.events = s.events or {}
        s.save_version = 2
    end
    if s.save_version < 3 then
        -- v3 restarts the run with the new opening; the quest list is kept.
        local fresh = Game.newState(os.time())
        fresh.quests, fresh.next_id = s.quests or {}, s.next_id or 1
        s = fresh
    end
    if s.save_version < 4 then
        local old = s.barrel
        if old and old.recipe then
            local bread = old.recipe == "bread"
            old = { combo = bread and "grain+grain" or "herb+herb", key = old.recipe,
                label = bread and "Bread" or "Minor potion", done_at = old.done_at, fine = false }
        end
        s.barrels = { old or false }
        s.barrel = nil
        s.journal = s.journal or {}
        s.buffs = {}
        if (s.bread_until or 0) > os.time() then
            table.insert(s.buffs, { kind = "xp_pct", amt = 10, ["until"] = s.bread_until })
        end
        s.save_version = 4
    end
    if s.save_version < 5 then
        s.steps_synced = s.steps_synced or {}
        s.step_carry = s.step_carry or 0
        s.save_version = 5
    end
    if s.save_version < 6 then
        s.gear = s.gear or { equipped = {}, bag = {}, next_id = 1 }
        s.fight = nil          -- pre-v6 fights used the prototype rules
        s.save_version = 6
    end
    if s.save_version < 7 then
        s.stats.kin = s.stats.kin or 2
        s.training = s.training or { total = 0, pushups = 0, squats = 0, dumbbells = 0, day = nil, today = 0 }
        s.grit = s.grit or 0
        s.save_version = 7
    end
    if s.save_version < 8 then
        s.tried = s.tried or {}   -- combos baked at least once (failures included)
        s.ing_seen = s.ing_seen or {}
        s.merge_log = s.merge_log or {}
        s.practice = s.practice or { day = nil, med_min = 0, pomos = 0 }
        s.timelog = s.timelog or {}
        s.starters = s.starters or {}
        s.save_version = 8
    end
    if s.save_version < 9 then
        s.dry_flips = s.dry_flips or 0   -- card flips since the last fight (streak breaker)
        s.save_version = 9
    end
    if s.save_version < 10 then
        s.tally = s.tally or {}   -- counts for the status report
        s.save_version = 10
    end
    if s.save_version < 11 then
        -- rank ladder (2026-10-19): one rank below the current one, so the first open shows one promotion
        s.rank_seen = math.max(1, Game.rankIndex(s.level or 1) - 1)
        s.save_version = 11
    end
    if s.save_version < 12 then
        -- gold and real-world loot (Mike, 2026-10-20)
        s.loot = s.loot or Game.newLoot()
        s.save_version = 12
    end
    if s.save_version < 13 then
        -- ranks respaced (2026-10-22): settle on the new rank quietly, no promotion screen
        s.rank_seen = Game.rankIndex(s.level or 1)
        s.save_version = 13
    end
    if s.save_version < 14 then
        -- recurring quests (2026-10-22): done ones wait here until their next day
        s.sleeping = s.sleeping or {}
        s.save_version = 14
    end
    for _, ing in ipairs(Game.BOOK.ingredients) do s.inv[ing.key] = s.inv[ing.key] or 0 end
    return s
end

-- Story events: the rules push plain strings here; story.lua turns them into scenes.
function Game.emit(s, ev)
    s.events = s.events or {}
    table.insert(s.events, ev)
end

function Game.dayIndex(s, now)
    return math.floor((dayStart(now) - dayStart(s.created)) / DAY + 0.5)
end

function Game.newState(now)
    return {
        save_version = Game.SAVE_VERSION,
        created = now,
        last_day = dayKey(now),
        level = 1, xp = 0,
        charge = 11,
        charge_ts = now,
        hp = 26,
        stats = { str = 2, res = 5, foc = 2, acu = 3, kin = 2 },  -- kin grows from TRAIN, not levels
        skills = {},            -- key -> { xp=, rank=, day=, today= }
        footing = { kept = 0, rank = 1, borrow_week = nil },
        borrow = nil,           -- Borrowed Morning in progress: { deadline=, day= }
        streak = 0, best_streak = 0, shields = 0,
        integrity = 100,
        quests = {}, next_id = 1,
        daily_id = nil, daily_done = false,
        minor_today = 0,
        inv = { grain = 2, herb = 2, dust = 0, bread = 0, potion = 0 },
        barrels = { false },    -- each: false or { combo=, key=, label=, done_at=, fine= }
        journal = {},           -- combo -> true once a recipe is discovered
        tried = {},             -- combo -> true once baked, found or not
        ing_seen = {},          -- regional ingredient -> true once found (shows its journal hints)
        merge_log = {},         -- recent gear merges, newest first: { a=, b=, out=, before=, after= }
        practice = { day = nil, med_min = 0, pomos = 0 },  -- today's Meditate minutes and Pomodoros; .session while one runs
        timelog = {},           -- tier -> { n=, min= }: Pomodoro minutes on finished quests
        dry_flips = 0,          -- card flips since the last fight; at Game.DRY_MAX the next flip is a fight
        tally = {},             -- counts for the daily status report (fights, bakes, merges...)
        rank_seen = 1,          -- highest rank whose promotion screen was shown
        loot = Game.newLoot(),  -- gold balance, real-world rewards and claims
        sleeping = {},          -- recurring quests done for now: { q=, wake="YYYY-MM-DD", pos= }
        starters = {},          -- recipe key -> starters kept back from used items (Regrow)
        buffs = {},             -- { kind=, amt=, until= }
        luck_flips = 0, whet = 0, seal = 0,
        range = 0,
        gear = { equipped = {}, bag = {}, next_id = 1 },
        abilities = nil,        -- two keys from Combat.ABILITIES, picked at the combat unlock
        thralls = 0,
        training = { total = 0, pushups = 0, squats = 0, dumbbells = 0, day = nil, today = 0 },
        grit = 0,               -- banked from TRAIN sets, spent by Breaker
        steps_synced = {},      -- "YYYY-MM-DD" -> step total already turned into Range
        step_carry = 0,         -- steps not yet worth a whole Range
        fight = nil,
        log = {},
        story = newStory(),
        route = { km = 0, guardians = {} },
        events = { "boot" },
    }
end

local function say(s, msg)
    table.insert(s.log, 1, msg)
    while #s.log > 6 do table.remove(s.log) end
end
Game.say = say

-- Charge regenerates from empty to full in about 24 hours.
function Game.regen(s, now)
    local maxc = Game.maxCharge(s.level, s)
    local per_sec = maxc / DAY * math.max(1, Game.buffTotal(s, "regen_x", now))
    local gained = math.floor((now - (s.charge_ts or now)) * per_sec)
    if gained > 0 then
        s.charge = math.min(maxc, s.charge + gained)
        s.charge_ts = now
    end
    if s.charge >= maxc then s.charge_ts = now end
end

-- Handle days that ended since the device was last opened.
function Game.rollover(s, now)
    local today = dayKey(now)
    if s.last_day == today then return end
    local last = os.time({ year = tonumber(s.last_day:sub(1, 4)),
        month = tonumber(s.last_day:sub(6, 7)), day = tonumber(s.last_day:sub(9, 10)), hour = 12 })
    local days_passed = math.floor((dayStart(now) - dayStart(last)) / DAY + 0.5)
    for i = 1, days_passed do
        local was_done = (i == 1) and s.daily_done
        if not was_done then
            local day_index = math.floor((dayStart(last) + i * DAY - dayStart(s.created)) / DAY)
            local week = math.floor(Game.dayIndex(s, now) / 7)
            if i == days_passed and s.footing and s.footing.rank >= 3 and s.footing.borrow_week ~= week then
                -- Borrowed Morning: yesterday's miss waits until noon today.
                s.footing.borrow_week = week
                s.borrow = { deadline = dayStart(now) + 12 * 60 * 60, grace = day_index <= GRACE_DAYS }
                Game.emit(s, "borrowed_morning")
            elseif s.shields > 0 then
                s.shields = s.shields - 1
                say(s, "A shield absorbed a missed Daily Directive.")
            else
                s.story.misses_in_row = s.story.misses_in_row + 1
                Game.emit(s, day_index > GRACE_DAYS and "daily_missed" or "daily_missed_grace")
                if s.story.misses_in_row == 2 then Game.emit(s, "reboot_offer") end
                if s.streak > 0 then s.best_streak = math.max(s.best_streak, s.streak) end
                s.streak = 0
                if day_index > GRACE_DAYS then
                    s.integrity = math.max(0, s.integrity - 15)
                    say(s, "Missed Daily Directive. Integrity -15%.")
                else
                    say(s, "Missed Daily Directive. (Grace period: no damage.)")
                end
            end
        end
    end
    -- the old daily is gone; the quest itself stays in the list
    s.daily_id, s.daily_done = nil, false
    s.minor_today = 0
    s.last_day = today
end

-- The borrowed morning ran out: apply yesterday's miss now.
local function settleBorrow(s, now)
    local b = s.borrow
    if not b or now < b.deadline then return end
    s.borrow = nil
    if s.shields > 0 then s.shields = s.shields - 1; say(s, "A shield absorbed a missed Daily Directive."); return end
    if s.streak > 0 then s.best_streak = math.max(s.best_streak, s.streak) end
    s.streak = 0
    s.story.misses_in_row = s.story.misses_in_row + 1
    if b.grace then
        say(s, "Missed Daily Directive. (Grace period: no damage.)")
        Game.emit(s, "daily_missed_grace")
    else
        s.integrity = math.max(0, s.integrity - 15)
        say(s, "Missed Daily Directive. Integrity -15%.")
        Game.emit(s, "daily_missed")
    end
end

-- Pause (Mike, 2026-10-07, for a cruise): everything stops until RESUME. Nothing ticks
-- while paused; on resume every clock is pushed forward by the time away, so the days
-- missed never happened (no misses, no streak change, no story days, no regen, no steps).
function Game.pause(s, now)
    if s.paused then return false end
    s.paused = { since = now, day = dayKey(now) }
    say(s, "Relic paused.")
    return true
end

-- Days strictly between the pause day and the resume day: steps on them don't count.
function Game.isPausedDay(s, key)
    if (s.paused_days or {})[key] then return true end
    return s.paused ~= nil and key > s.paused.day
end

function Game.resume(s, now)
    local p = s.paused
    if not p then return false end
    local away = math.max(0, now - p.since)
    local days = math.floor((dayStart(now) - dayStart(p.since)) / DAY + 0.5)
    s.paused = nil
    -- day count, grace and story days stand still: the resume day is the day after the pause day
    if days > 0 then s.created = s.created + (days - 1) * DAY end
    s.charge_ts = (s.charge_ts or now) + away     -- no Charge regen while away
    if s.borrow then s.borrow.deadline = s.borrow.deadline + away end
    for _, b in ipairs(s.buffs or {}) do b["until"] = b["until"] + away end
    for _, b in ipairs(s.barrels or {}) do if b then b.done_at = b.done_at + away end end
    if s.practice and s.practice.session then s.practice.session.start = s.practice.session.start + away end
    if days > 0 then
        -- the paused-from day and the days away are skipped: no misses, a fresh Daily today
        s.paused_days = s.paused_days or {}
        for i = 1, days - 1 do s.paused_days[dayKey(dayStart(p.since) + i * DAY + 12 * 3600)] = true end
        s.daily_id, s.daily_done = nil, false
        s.minor_today = 0
        s.last_day = dayKey(now)
        if s.practice then s.practice.day = nil end
    end
    -- forget paused days older than the step window
    for k in pairs(s.paused_days or {}) do
        local y, m, d = k:match("^(%d+)-(%d+)-(%d+)$")
        if not y or now - os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 } > 21 * DAY then s.paused_days[k] = nil end
    end
    say(s, days > 0 and ("Relic resumed after " .. days .. (days == 1 and " day." or " days.")) or "Relic resumed.")
    return true, days
end

function Game.tick(s, now)
    if s.paused then return end
    settleBorrow(s, now)
    Game.rollover(s, now)
    Game.wakeRecurring(s, now)
    Game.regen(s, now)
end

function Game.addQuest(s, title, tier_key, main)
    local q = { id = s.next_id, title = title, tier = tier_key or "standard", main = main or nil }
    s.next_id = s.next_id + 1
    table.insert(s.quests, q)
    return q
end

-- Count something for the status report.
function Game.tally(s, key, by)
    s.tally = s.tally or {}
    s.tally[key] = (s.tally[key] or 0) + (by or 1)
end

-- Order, due dates, OUT ----------------------------------------------------
-- s.quests is the player's own order. Shown order: overdue first (oldest due first),
-- then the player's order, waiting quests last.
local function dueTime(due)
    local y, m, d = tostring(due or ""):match("^(%d%d%d%d)-(%d%d)-(%d%d)")
    if not y then return nil end
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
end

-- Days until due (0 = today, negative = overdue), or nil without a date.
function Game.daysLeft(q, now)
    local t = dueTime(q.due)
    if not t then return nil end
    local today = os.date("*t", now or os.time())
    local noon = os.time{ year = today.year, month = today.month, day = today.day, hour = 12 }
    return math.floor((t - noon) / 86400 + 0.5)
end

function Game.dueText(q, now)
    local d = Game.daysLeft(q, now)
    if not d then return nil end
    if d < 0 then return "LATE " .. (-d) .. "d" end
    if d == 0 then return "due TODAY" end
    if d == 1 then return "due tomorrow" end
    return "due " .. d .. "d"
end

-- due: "YYYY-MM-DD" or nil to clear. Returns ok.
function Game.setDue(s, id, due)
    local q = Game.findQuest(s, id)
    if not q then return false end
    if due ~= nil and not dueTime(due) then return false end
    q.due = due
    return true
end

function Game.dueIn(days, now)
    local t = os.date("*t", now or os.time())
    local noon = os.time{ year = t.year, month = t.month, day = t.day, hour = 12 }
    return os.date("%Y-%m-%d", noon + days * 86400)   -- from noon, so a DST night can't skip a day
end

function Game.orderedQuests(s, now)
    local late, rest, waiting = {}, {}, {}
    for _, q in ipairs(s.quests) do
        local d = Game.daysLeft(q, now)
        if q.waiting then table.insert(waiting, q)
        elseif d and d < 0 then table.insert(late, q)
        else table.insert(rest, q) end
    end
    local pos = {}
    for i, q in ipairs(s.quests) do pos[q.id] = i end
    table.sort(late, function(a, b)
        if a.due ~= b.due then return a.due < b.due end
        return pos[a.id] < pos[b.id]
    end)
    local out = {}
    for _, l in ipairs({ late, rest, waiting }) do for _, q in ipairs(l) do table.insert(out, q) end end
    return out
end

-- Move a quest to just above another (before_id), or to the end (before_id nil).
-- Late quests sort by due date, so they can't be moved; a waiting quest as the target
-- means "end of the active list" (waiting quests always show last).
function Game.moveQuest(s, id, before_id, now)
    if id == before_id then return false end
    local q, i = Game.findQuest(s, id)
    if not q then return false end
    local d = Game.daysLeft(q, now)
    if d and d < 0 and not q.waiting then return false, "Late quests sit on top by due date. Change its due date to move it." end
    local target = before_id and Game.findQuest(s, before_id)
    table.remove(s.quests, i)
    if target and target.waiting and not q.waiting then
        local last = 0
        for k, x in ipairs(s.quests) do if not x.waiting then last = k end end
        table.insert(s.quests, last + 1, q)
        return true
    end
    if target then
        local _, j = Game.findQuest(s, before_id)
        table.insert(s.quests, j, q)
        return true
    end
    table.insert(s.quests, q)
    return true
end

function Game.tierByKey(key) return TIER_BY_KEY[key] end

-- Move mode (Mike, 2026-10-22): pick a quest, then TOP / UP / DOWN. Moves stay inside the
-- quest's own group (late ones sort by due date and can't move; waiting ones stay last).
-- dir: "up", "down" or "top". Returns true, or false + reason.
function Game.nudgeQuest(s, id, dir, now)
    local q = Game.findQuest(s, id)
    if not q then return false end
    local function group(x)
        if x.waiting then return "waiting" end
        local d = Game.daysLeft(x, now)
        if d and d < 0 then return "late" end
        return "rest"
    end
    local g = group(q)
    if g == "late" then return false, "Late quests sit on top by due date. Change its due date to move it." end
    local list = {}
    for _, x in ipairs(Game.orderedQuests(s, now)) do if group(x) == g then table.insert(list, x) end end
    local k
    for i, x in ipairs(list) do if x.id == id then k = i end end
    if dir == "top" or dir == "up" then
        if k == 1 then return false, "Already at the top." end
        local target = dir == "top" and list[1] or list[k - 1]
        return Game.moveQuest(s, id, target.id, now)
    end
    if k == #list then return false, "Already at the bottom." end
    -- just after the next one: above the one after that, or the end of the group
    local after = list[k + 2]
    if after then return Game.moveQuest(s, id, after.id, now) end
    if g == "rest" then
        -- end of the active list: above the first waiting quest, if any
        local _, i = Game.findQuest(s, id)
        table.remove(s.quests, i)
        local last = 0
        for j, x in ipairs(s.quests) do if not x.waiting then last = j end end
        table.insert(s.quests, last + 1, q)
        return true
    end
    return Game.moveQuest(s, id, nil, now)
end

-- Recurring quests (Mike, 2026-10-22) ---------------------------------------------------
-- q.rep = { kind = "daily" } | { kind = "weekdays" } | { kind = "days", days = { [wday]=true } }
--       | { kind = "every", n = N }      (wday as os.date: 1 = Sunday .. 7 = Saturday)
-- One copy only: a missed one stays on the list (rolls over). Done or skipped, it leaves the
-- list and waits in s.sleeping until its next scheduled day, then comes back where it was,
-- with its steps unchecked.
local WDAY_NAMES = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }
Game.WDAY_NAMES = WDAY_NAMES

local function addDays(t, n)
    local d = os.date("*t", t)
    d.day, d.hour, d.min, d.sec = d.day + n, 12, 0, 0
    return os.time(d)
end

function Game.repText(rep)
    if not rep then return nil end
    if rep.kind == "daily" then return "every day" end
    if rep.kind == "weekdays" then return "weekdays" end
    if rep.kind == "every" then return (rep.n or 1) == 1 and "every day" or ("every " .. rep.n .. " days") end
    if rep.kind == "days" then
        local out = {}
        for w = 2, 8 do local i = (w - 1) % 7 + 1; if rep.days and rep.days[i] then table.insert(out, WDAY_NAMES[i]) end end
        return #out > 0 and table.concat(out, ", ") or "never"
    end
    return "?"
end

-- is day t one of the rule's days? ("every" is counted from the day it was last done)
local function onDay(rep, t)
    local w = tonumber(os.date("%w", t)) + 1
    if rep.kind == "weekdays" then return w >= 2 and w <= 6 end
    if rep.kind == "days" then return rep.days and rep.days[w] or false end
    return true
end

-- first scheduled day after the day of 'now', as YYYY-MM-DD
function Game.nextRepDay(rep, now)
    if rep.kind == "every" then return dayKey(addDays(now, math.max(1, rep.n or 1))) end
    for k = 1, 14 do
        local t = addDays(now, k)
        if onDay(rep, t) then return dayKey(t) end
    end
    return dayKey(addDays(now, 7))
end

function Game.validRep(rep)
    if type(rep) ~= "table" then return false end
    if rep.kind == "daily" or rep.kind == "weekdays" then return true end
    if rep.kind == "every" then return type(rep.n) == "number" and rep.n >= 1 and rep.n <= 365 end
    if rep.kind == "days" and type(rep.days) == "table" then
        for i = 1, 7 do if rep.days[i] then return true end end
    end
    return false
end

function Game.setRepeat(s, id, rep)
    local q = Game.findQuest(s, id)
    if not q then return false end
    if rep ~= nil and not Game.validRep(rep) then return false end
    q.rep = rep
    if rep then q.due = nil end  -- a repeating quest rolls over instead of going late
    return true
end

function Game.sleepRecurring(s, q, pos, now)
    s.sleeping = s.sleeping or {}
    for _, st in ipairs(q.steps or {}) do st.done, st.paid = nil, nil end
    q.paid, q.pomos, q.minutes = nil, nil, nil
    table.insert(s.sleeping, { q = q, wake = Game.nextRepDay(q.rep, now), pos = pos or (#s.quests + 1) })
end

-- not today: off the list without rewards until its next day
function Game.skipRecurring(s, id, now)
    local q, pos = Game.findQuest(s, id)
    if not q or not q.rep then return false end
    if s.daily_id == id then s.daily_id = nil end
    table.remove(s.quests, pos)
    Game.sleepRecurring(s, q, pos, now)
    return true
end

function Game.wakeRecurring(s, now)
    if not s.sleeping or #s.sleeping == 0 then return 0 end
    local today, n = dayKey(now), 0
    for i = #s.sleeping, 1, -1 do
        local z = s.sleeping[i]
        if z.wake <= today then
            table.remove(s.sleeping, i)
            table.insert(s.quests, math.max(1, math.min(z.pos or 1, #s.quests + 1)), z.q)
            n = n + 1
        end
    end
    return n
end

-- every repeating quest, on the list or waiting for its day: { q=, wake= or nil }
function Game.recurringList(s)
    local out = {}
    for _, q in ipairs(s.quests) do if q.rep then table.insert(out, { q = q }) end end
    for _, z in ipairs(s.sleeping or {}) do table.insert(out, { q = z.q, wake = z.wake }) end
    return out
end

-- stop repeating; a quest waiting for its day is dropped, one on the list stays as a normal quest
function Game.stopRecurring(s, id)
    for i, z in ipairs(s.sleeping or {}) do
        if z.q.id == id then table.remove(s.sleeping, i); return true end
    end
    local q = Game.findQuest(s, id)
    if q then q.rep = nil; return true end
    return false
end

-- Todoist recurrence text ("every day", "every weekday", "every mon, fri", "every 3 days",
-- "every other day", "every week") -> rep. due_date (YYYY-MM-DD) picks the day for "every week".
-- Second result: false when the text wasn't understood (the rule is then a guess).
function Game.parseRecurrence(str, due_date)
    local rep, known = Game._parseRecurrence(str, due_date)
    if rep.kind == "every" then rep.n = math.max(1, math.min(365, rep.n or 1)) end
    return rep, known ~= false
end

function Game._parseRecurrence(str, due_date)
    local t = tostring(str or ""):lower():gsub("!", "")
    t = t:gsub("%s+starting.*$", ""):gsub("%s+from%s.*$", ""):gsub("%s+until.*$", "")
    if t:match("weekday") or t:match("workday") then return { kind = "weekdays" } end
    if t:match("weekend") then return { kind = "days", days = { [1] = true, [7] = true } } end
    if t:match("every%s+other%s+%a+day") and not t:match("every%s+other%s+day") then return { kind = "every", n = 14 } end
    local n = tonumber(t:match("every%s+(%d+)%s+days?"))
    if n then return { kind = "every", n = math.max(1, n) } end
    n = tonumber(t:match("every%s+(%d+)%s+weeks?"))
    if n then return { kind = "every", n = 7 * math.max(1, n) } end
    if t:match("every%s+other%s+week") then return { kind = "every", n = 14 } end
    n = tonumber(t:match("every%s+(%d+)%s+months?"))
    if n or t:match("month") then return { kind = "every", n = 30 * math.max(1, n or 1) } end
    if t:match("year") or t:match("annual") then return { kind = "every", n = 365 } end
    if t:match("every%s+other%s+day") then return { kind = "every", n = 2 } end
    local names = { sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 }
    local days, any = {}, false
    for word in t:gmatch("%a+") do
        local w = names[word:sub(1, 3)]
        if w and (#word == 3 or word:match("days?$") or word:match("^tues") or word:match("^thur") or word:match("^wednes")) then
            days[w] = true; any = true
        end
    end
    if any then return { kind = "days", days = days } end
    if t:match("every%s+week") or t:match("weekly") then
        local y, m, d = tostring(due_date or ""):match("^(%d+)-(%d+)-(%d+)")
        local w = y and (tonumber(os.date("%w", os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })) + 1)
            or (tonumber(os.date("%w")) + 1)
        return { kind = "days", days = { [w] = true } }
    end
    if t:match("^%s*every%s+day%s*$") or t:match("daily") or t:match("every%s+morning") or t:match("every%s+evening")
        or t:match("every%s+night") or t:match("every%s+afternoon") then
        return { kind = "daily" }
    end
    return { kind = "daily" }, false
end

-- Change a quest's size (Mike, 2026-10-22: edit quests). Unknown sizes are refused.
function Game.setTier(s, id, key)
    local q = Game.findQuest(s, id)
    if not q or not TIER_BY_KEY[key] then return false end
    q.tier = key
    return true
end

function Game.findQuest(s, id)
    for i, q in ipairs(s.quests) do
        if q.id == id then return q, i end
    end
end

-- by_user: true when the player deleted it (not when it was completed)
function Game.deleteQuest(s, id, by_user)
    local _, i = Game.findQuest(s, id)
    if i then table.remove(s.quests, i) end
    if by_user and i then Game.emit(s, "quest_deleted") end
    if s.daily_id == id then s.daily_id = nil end
end

function Game.setDaily(s, id)
    if s.daily_done then return false, "Today's Daily Directive is already done." end
    s.daily_id = id
    return true
end

local function levelUps(s)
    local ups = 0
    while s.xp >= Game.xpToNext(s.level) do
        s.xp = s.xp - Game.xpToNext(s.level)
        s.level = s.level + 1
        ups = ups + 1
        for k, g in pairs(Game.GROWTH) do s.stats[k] = s.stats[k] + g end
        s.hp = Game.maxHp(s.level, s)
    end
    if ups > 0 then say(s, "LEVEL UP. You are level " .. s.level .. ".") end
    return ups
end
Game.levelUps = levelUps

-- Returns a short result string for the UI.
function Game.completeQuest(s, id, now)
    local q, qpos = Game.findQuest(s, id)
    if not q then return "Quest not found." end
    local was_daily = s.daily_id == id
    local tier = TIER_BY_KEY[q.tier] or TIER_BY_KEY.standard
    local xp = tier.xp
    if q.dread then xp = xp * 2 end
    -- steps already paid part of it up front
    xp = math.max(0, xp - (q.paid or 0))
    -- gold: a flat amount by tier (no dread, timer or buffs); the Minor soft cap halves it too
    local gold = Game.GOLD_BY_TIER[tier.key] or 0
    if q.tier == "minor" then
        s.minor_today = s.minor_today + 1
        if s.minor_today > MINOR_SOFTCAP then xp = math.floor(xp / 2); gold = gold / 2 end
    end
    -- a Pomodoro on this quest whose time is up counts even if DONE wasn't tapped
    local se = s.practice and s.practice.session
    if se and se.kind == "pomodoro" and se.quest == id and now >= se.start + se.min * 60 then
        Game.finishSession(s, now)
    end
    -- timed work: a quest with Pomodoros on it pays +20%, and its time goes in the log
    local timed = (q.pomos or 0) > 0
    if timed then
        xp = math.floor(xp * 1.2 + 0.5)
        local tl = s.timelog[q.tier or "standard"] or { n = 0, min = 0 }
        tl.n, tl.min = tl.n + 1, tl.min + (q.minutes or 0)
        s.timelog[q.tier or "standard"] = tl
    end
    if s.practice and s.practice.session and s.practice.session.quest == id then s.practice.session = nil end
    local pct = Game.buffTotal(s, "xp_pct", now)
    if pct > 0 then xp = math.floor(xp * (1 + pct / 100) + 0.5) end
    s.xp = s.xp + xp
    s.charge = math.min(Game.maxCharge(s.level, s), s.charge + math.ceil(xp / 10))
    -- materials: alternate grain and herb so both recipes stay reachable
    local mat = (s.next_id + id) % 2 == 0 and "grain" or "herb"
    local amount = (q.tier == "minor") and 1 or 2
    s.inv[mat] = s.inv[mat] + amount
    local msg = string.format("+%d XP, +%d %s", xp, amount, mat)
    local before = math.floor(Game.goldBalance(s))
    Game.addGold(s, gold)
    local got = math.floor(Game.goldBalance(s)) - before
    if got > 0 then msg = msg .. string.format(", +%d gold", got) end
    if s.daily_id == id then
        s.daily_done = true
        s.streak = s.streak + 1
        s.best_streak = math.max(s.best_streak, s.streak)
        if s.streak % 7 == 0 and s.shields < 2 then
            s.shields = s.shields + 1
            say(s, "7-day streak. Shield earned.")
        end
        s.integrity = math.min(100, s.integrity + 10)
        msg = msg .. ", Daily Directive done"
        Game.emit(s, "daily_kept")
        if s.story.misses_in_row > 0 then Game.emit(s, "daily_return") end
        s.story.misses_in_row = 0
        s.story.kept_days[Game.dayIndex(s, now)] = true
        if s.borrow and now < s.borrow.deadline then
            -- Borrowed Morning kept: yesterday counts too.
            s.borrow = nil
            s.story.kept_days[Game.dayIndex(s, now) - 1] = true
            s.streak = s.streak + 1
            s.best_streak = math.max(s.best_streak, s.streak)
            msg = msg .. ", yesterday recovered"
        end
        -- Footing: +Charge per kept day; rank from kept days.
        local f = s.footing
        f.kept = f.kept + 1
        local bonus = f.rank >= 2 and 2 or 1
        s.charge = math.min(Game.maxCharge(s.level, s), s.charge + bonus)
        local new_rank = (f.kept >= 7 and 3) or (f.kept >= 3 and 2) or 1
        if new_rank > f.rank then
            f.rank = new_rank
            Game.emit(s, "footing_rank:" .. new_rank)
        end
    end
    msg = msg .. Game.trainSkills(s, q, xp, now)
    if q.main then Game.emit(s, "main_done") end
    Game.deleteQuest(s, id)
    local paid = q.paid or 0  -- before sleepRecurring clears it (review, 2026-10-22)
    if q.rep then Game.sleepRecurring(s, q, qpos, now) end
    if s.daily_done and s.daily_id == nil then s.daily_id = -1 end -- keep "done" marker
    levelUps(s)
    say(s, "Completed: " .. q.title .. " (" .. msg .. ")")
    return msg, Game.chronicleEntry(q, "done", xp + paid, was_daily)
end

-- One chronicle record (see chronicle.lua). xp: character XP the quest paid in total.
function Game.chronicleEntry(q, event, xp, was_daily)
    local skills = {}
    for _, key in ipairs(q.tags or Game.tagQuest(q.title or "")) do table.insert(skills, key) end
    return {
        event = event, title = q.title, tier = q.tier or "standard", xp = xp or 0, skills = skills,
        kind = was_daily and "daily" or (q.main and "main" or "side"),
    }
end

-- Subtasks (checklist steps) ------------------------------------------------
-- Steps pay up to half the quest's XP as they're checked; the quest pays the rest
-- on completion, so splitting a quest into steps never adds XP.

local function questXp(q)
    local t = TIER_BY_KEY[q.tier] or TIER_BY_KEY.standard
    return t.xp * (q.dread and 2 or 1)
end
Game.questXp = questXp

function Game.addStep(s, id, text)
    local q = Game.findQuest(s, id)
    if not q or not text or not text:match("%S") then return end
    q.steps = q.steps or {}
    table.insert(q.steps, { text = text })
end

function Game.editStep(s, id, i, text)
    local q = Game.findQuest(s, id)
    if q and q.steps and q.steps[i] and text and text:match("%S") then q.steps[i].text = text end
end

function Game.removeStep(s, id, i)
    local q = Game.findQuest(s, id)
    if q and q.steps and q.steps[i] then table.remove(q.steps, i) end
end

function Game.moveStep(s, id, i, dir)
    local q = Game.findQuest(s, id)
    if not q or not q.steps then return end
    local j = i + dir
    if j < 1 or j > #q.steps then return end
    q.steps[i], q.steps[j] = q.steps[j], q.steps[i]
end

function Game.stepProgress(q)
    local done, n = 0, q.steps and #q.steps or 0
    for i = 1, n do if q.steps[i].done then done = done + 1 end end
    return done, n
end

function Game.nextStep(q)
    for _, st in ipairs(q.steps or {}) do if not st.done then return st.text end end
end

-- Returns a short result message.
function Game.toggleStep(s, id, i, now)
    local q = Game.findQuest(s, id)
    if not q or not q.steps or not q.steps[i] then return "" end
    local st = q.steps[i]
    st.done = not st.done
    if not st.done or st.paid then return st.done and "Step done." or "Step reopened." end
    st.paid = true
    local cap = math.floor(questXp(q) / 2)
    local share = math.max(1, math.floor(cap / #q.steps))
    local pay = math.min(share, cap - (q.paid or 0))
    if pay <= 0 then return "Step done." end
    q.paid = (q.paid or 0) + pay
    s.xp = s.xp + pay
    levelUps(s)
    return "Step done. +" .. pay .. " XP"
end

-- Skills ----------------------------------------------------------------

function Game.skillXpToNext(rank) return 40 * rank end

local function skillByKey(key)
    for _, sk in ipairs(Game.SKILLS) do if sk.key == key then return sk end end
end
Game.skillByKey = skillByKey

-- 1 or 2 skill keys whose keywords appear in the title.
function Game.tagQuest(title)
    local t = " " .. title:lower() .. " "
    local tags = {}
    for _, sk in ipairs(Game.SKILLS) do
        for _, w in ipairs(sk.words) do
            if t:find(w, 1, true) then table.insert(tags, sk.key); break end
        end
        if #tags == 2 then break end
    end
    return tags
end

-- Returns text for the result message.
function Game.trainSkills(s, q, xp, now)
    local tags = q.tags or Game.tagQuest(q.title)
    local today = dayKey(now)
    local out = {}
    for _, key in ipairs(tags) do
        local sk = skillByKey(key)
        if sk and not sk.train_only then
            local st = s.skills[key]
            if not st then
                st = { xp = 0, rank = 1, day = today, today = 0 }
                s.skills[key] = st
                s.story.last_skill = sk.name
                Game.emit(s, "skill_discovered")
                say(s, "New skill: " .. sk.name .. ".")
            end
            if st.day ~= today then st.day, st.today = today, 0 end
            st.today = st.today + 1
            local gain = st.today > SKILL_DAILY_FULL and math.floor(xp / 2) or xp
            local spct = Game.buffTotal(s, "skill_pct", now)
            if spct > 0 then gain = math.floor(gain * (1 + spct / 100) + 0.5) end
            if (s.seal or 0) > 0 then gain = gain * 2 end
            st.xp = st.xp + gain
            while st.rank < 10 and st.xp >= Game.skillXpToNext(st.rank) do
                st.xp = st.xp - Game.skillXpToNext(st.rank)
                st.rank = st.rank + 1
                say(s, sk.name .. " rank " .. st.rank .. ".")
            end
            table.insert(out, sk.name .. " +" .. gain)
        end
    end
    if (s.seal or 0) > 0 and #out > 0 then s.seal = s.seal - 1 end
    -- ingredient drops by skill
    local chance = q.tier == "minor" and 30 or 50
    for _, key in ipairs(tags) do
        local ing = Game.BOOK.skill_drops[key]
        if ing and math.random(100) <= chance then
            s.inv[ing] = (s.inv[ing] or 0) + 1
            table.insert(out, "+1 " .. ing)
        end
    end
    if #out == 0 then return "" end
    return ", " .. table.concat(out, ", ")
end

-- Training -------------------------------------------------------------
-- TRAIN: 10 pushups, squats or dumbbell reps (any exercise; Mike 2026-10-08), honor system. Slots per day grow with total sets and are
-- never lost. Each set: character XP, Might skill XP, +1 Grit (banked for Breaker), and
-- Kinesthetics every few sets.

Game.TRAIN_REPS = 10
Game.TRAIN_SLOT_AT = { 7, 21, 45, 80 }   -- total sets that open daily slots 2..5
Game.TRAIN_XP = 5
Game.MIGHT_XP = 10
Game.KIN_EVERY = 5
Game.TRAIN_KINDS = { pushups = "pushups", squats = "squats", dumbbells = "dumbbell reps" }

-- Might perks by rank (combat reads these).
Game.MIGHT_PERKS = {
    [2] = "+1 attack",
    [4] = "Second Wind: once per fight, heal a quarter of your HP when you drop below a third",
    [6] = "Ram hits for 175%",
    [8] = "Breaker needs only 2 Grit",
    [10] = "Grit holds up to 15",
}

function Game.mightRank(s)
    local st = s.skills and s.skills.might
    return st and st.rank or 0
end

function Game.gritCap(s) return Game.mightRank(s) >= 10 and 15 or 10 end

function Game.trainSlots(s)
    local n = 1
    for _, at in ipairs(Game.TRAIN_SLOT_AT) do if (s.training.total or 0) >= at then n = n + 1 end end
    return n
end

-- Sets left today, and today's slot count.
function Game.trainLeft(s, now)
    local t = s.training
    local used = (t.day == dayKey(now)) and (t.today or 0) or 0
    local slots = Game.trainSlots(s)
    return math.max(0, slots - used), slots
end

-- Sets until the next slot opens (nil at the last one).
function Game.nextTrainSlot(s)
    for _, at in ipairs(Game.TRAIN_SLOT_AT) do
        if (s.training.total or 0) < at then return at - s.training.total end
    end
end

-- Practice: Meditate and Pomodoro ------------------------------------------
-- One session at a time. The Kindle may sleep: sessions are timestamps, checked on DONE.
Game.MED_OPTIONS = { 5, 10, 20 }
Game.MED_DAILY_CAP = 40      -- minutes a day that pay
Game.POMO_MIN = 25
Game.POMO_DAILY_CAP = 8
Game.POMO_XP = 5
Game.FOCUS_PERKS = { [2] = "+1 Focus", [4] = "+1 Focus", [6] = "+1 Focus", [8] = "+1 Focus", [10] = "+1 Focus" }

local function practiceDay(s, now)
    s.practice = s.practice or { med_min = 0, pomos = 0 }
    local p = s.practice
    local today = dayKey(now)
    if p.day ~= today then p.day, p.med_min, p.pomos = today, 0, 0 end
    return p
end
Game.practiceDay = practiceDay

function Game.sessionLeft(s, now)
    local se = s.practice and s.practice.session
    if not se then return nil end
    return math.max(0, se.start + se.min * 60 - now), se
end

function Game.startMeditate(s, min, now)
    local p = practiceDay(s, now)
    if p.session then return false, "Finish the session you started first." end
    local ok = false
    for _, m in ipairs(Game.MED_OPTIONS) do if m == min then ok = true end end
    if not ok then return false, "Pick 5, 10 or 20 minutes." end
    p.session = { kind = "meditate", start = now, min = min }
    return true
end

function Game.startPomodoro(s, qid, now)
    local p = practiceDay(s, now)
    if p.session then return false, "Finish the session you started first." end
    local q = Game.findQuest(s, qid)
    if not q then return false, "Pick a quest that's still open." end
    p.session = { kind = "pomodoro", start = now, min = Game.POMO_MIN, quest = qid }
    return true
end

function Game.stopSession(s)
    if s.practice then s.practice.session = nil end
end

local function gainFocus(s, amount, today, out)
    local st = s.skills.focus
    if not st then
        st = { xp = 0, rank = 1, day = today, today = 0 }
        s.skills.focus = st
        s.story.last_skill = "Focus"
        Game.emit(s, "skill_discovered")
        say(s, "New skill: Focus.")
    end
    st.xp = st.xp + amount
    table.insert(out, "Focus +" .. amount)
    while st.rank < 10 and st.xp >= Game.skillXpToNext(st.rank) do
        st.xp = st.xp - Game.skillXpToNext(st.rank)
        st.rank = st.rank + 1
        if Game.FOCUS_PERKS[st.rank] then s.stats.foc = (s.stats.foc or 0) + 1 end
        say(s, "Focus rank " .. st.rank .. "." .. (Game.FOCUS_PERKS[st.rank] and (" " .. Game.FOCUS_PERKS[st.rank] .. ".") or ""))
    end
end

-- DONE. Returns a message, or nil + reason (too early, nothing running).
function Game.finishSession(s, now)
    local p = practiceDay(s, now)
    local left, se = Game.sessionLeft(s, now)
    if not se then return nil, "Nothing running." end
    if left > 0 then return nil, math.ceil(left / 60) .. " min to go." end
    p.session = nil
    local out = {}
    if se.kind == "meditate" then
        local paid = math.max(0, math.min(se.min, Game.MED_DAILY_CAP - p.med_min))
        p.med_min = p.med_min + se.min
        if paid == 0 then
            local msg = "Meditated " .. se.min .. " min. (Today's rewards are used up; the practice still counts.)"
            say(s, msg); return msg
        end
        s.xp = s.xp + paid
        table.insert(out, "+" .. paid .. " XP")
        local ch = math.floor(paid / 5) * 2
        s.charge = math.min(Game.maxCharge(s.level, s), s.charge + ch)
        table.insert(out, "+" .. ch .. " Charge")
        gainFocus(s, paid * 2, dayKey(now), out)
        levelUps(s)
        local msg = "Meditated " .. se.min .. " min (" .. table.concat(out, ", ") .. ")"
        say(s, msg); return msg
    end
    -- pomodoro
    local q = Game.findQuest(s, se.quest)
    p.pomos = p.pomos + 1
    if q then
        q.pomos = (q.pomos or 0) + 1
        q.minutes = (q.minutes or 0) + se.min
    end
    if p.pomos <= Game.POMO_DAILY_CAP then
        s.xp = s.xp + Game.POMO_XP
        table.insert(out, "+" .. Game.POMO_XP .. " XP")
        levelUps(s)
    end
    local msg = "Pomodoro done" .. (q and (" on " .. q.title) or "") .. (#out > 0 and (" (" .. table.concat(out, ", ") .. ")") or "") ..
        ". Finish the quest for +20% XP."
    say(s, msg)
    return msg
end

-- kind: "pushups" | "squats" | "dumbbells". Returns a result message, or nil + reason.
function Game.train(s, kind, now)
    if not Game.TRAIN_KINDS[kind] then return nil, "Unknown training." end
    local left = Game.trainLeft(s, now)
    if left <= 0 then return nil, "No training left today." end
    local t = s.training
    local today = dayKey(now)
    if t.day ~= today then t.day, t.today = today, 0 end
    local slots_before = Game.trainSlots(s)
    t.today = t.today + 1
    t.total = t.total + 1
    t[kind] = (t[kind] or 0) + 1
    local out = { "+" .. Game.TRAIN_XP .. " XP" }
    -- Might (exempt from the daily halving: the slot limit already caps it)
    local st = s.skills.might
    if not st then
        st = { xp = 0, rank = 1, day = today, today = 0 }
        s.skills.might = st
        s.story.last_skill = "Might"
        Game.emit(s, "skill_discovered")
        say(s, "New skill: Might.")
    end
    if st.day ~= today then st.day, st.today = today, 0 end
    st.today = st.today + 1
    st.xp = st.xp + Game.MIGHT_XP
    table.insert(out, "Might +" .. Game.MIGHT_XP)
    while st.rank < 10 and st.xp >= Game.skillXpToNext(st.rank) do
        st.xp = st.xp - Game.skillXpToNext(st.rank)
        st.rank = st.rank + 1
        local perk = Game.MIGHT_PERKS[st.rank]
        say(s, "Might rank " .. st.rank .. "." .. (perk and (" " .. perk .. ".") or ""))
    end
    -- Grit
    local cap = Game.gritCap(s)
    if (s.grit or 0) < cap then
        s.grit = (s.grit or 0) + 1
        table.insert(out, "Grit " .. s.grit .. "/" .. cap)
    else
        table.insert(out, "Grit full")
    end
    -- Kinesthetics
    if t.total % Game.KIN_EVERY == 0 then
        s.stats.kin = (s.stats.kin or 0) + 1
        table.insert(out, "+1 KIN")
    end
    local msg = "Trained: " .. Game.TRAIN_REPS .. " " .. Game.TRAIN_KINDS[kind] .. " (" .. table.concat(out, ", ") .. ")"
    say(s, msg)
    if Game.trainSlots(s) > slots_before then
        say(s, "Training grounded: " .. Game.trainSlots(s) .. " sets a day now.")
        msg = msg .. ". A new daily set opens."
    end
    s.xp = s.xp + Game.TRAIN_XP
    levelUps(s)
    return msg
end

-- Baking ----------------------------------------------------------------
-- Free-form: any two ingredients. Known pairs make a recipe from the book;
-- anything else makes a stale loaf or a murky tonic. Discoveries go in the journal.

-- Stacked buffs of one kind add up to a ceiling.
Game.BUFF_CAP = { xp_pct = 50, skill_pct = 100 }

function Game.buffTotal(s, kind, now)
    local total = 0
    now = now or os.time()
    for i = #(s.buffs or {}), 1, -1 do
        local b = s.buffs[i]
        if b["until"] <= now then table.remove(s.buffs, i)
        elseif b.kind == kind then total = total + b.amt end
    end
    if Game.BUFF_CAP[kind] then total = math.min(total, Game.BUFF_CAP[kind]) end
    return total
end

function Game.barrelCount(s)
    return 1 + (s.level >= 3 and 1 or 0)
end

-- Inventory keys can be fine baked items ("bread_fine"); recipes use the base key.
local function baseKey(item) return (item:gsub("_fine$", "")) end
Game.baseKey = baseKey

local function comboKey(a, b)
    a, b = baseKey(a), baseKey(b)
    if a > b then a, b = b, a end
    return a .. "+" .. b
end
Game.comboKey = comboKey

-- Baked items that can go back into a barrel (anything from the book, not failures).
function Game.isBakedInput(item)
    local base = baseKey(item)
    for _, r in pairs(Game.BOOK.recipes) do if r.key == base then return true end end
    return false
end

-- recipe table for a pair (a failure recipe if unknown), plus the combo key
function Game.bakeResult(a, b)
    local combo = comboKey(a, b)
    local r = Game.BOOK.recipes[combo]
    if r then return r, combo, true end
    if baseKey(a) == "grain" or baseKey(b) == "grain" or baseKey(a) == "bread" or baseKey(b) == "bread" then
        return Game.BOOK.fail_grain, combo, false
    end
    return Game.BOOK.fail_other, combo, false
end

function Game.bakeMinutes(a, b)
    local r, _, known = Game.bakeResult(a, b)
    return known and r.minutes or 20
end

function Game.freeBarrel(s)
    for i = 1, Game.barrelCount(s) do
        if not s.barrels[i] then return i end
    end
end

function Game.canBake(s, a, b)
    local need = {}
    need[a] = (need[a] or 0) + 1
    need[b] = (need[b] or 0) + 1
    for ing, n in pairs(need) do
        if (s.inv[ing] or 0) < n then
            local lbl = (ing:match("_fine$") and "Fine " or "") .. Game.ingLabel(baseKey(ing))
            return false, "Need " .. n .. " " .. lbl .. "."
        end
    end
    if not Game.freeBarrel(s) then return false, "No free barrel." end
    return true
end

function Game.startBake(s, a, b, now, rng)
    rng = rng or math.random
    local ok, why = Game.canBake(s, a, b)
    if not ok then return false, why end
    s.inv[a] = s.inv[a] - 1
    s.inv[b] = s.inv[b] - 1
    local r, combo = Game.bakeResult(a, b)
    local i = Game.freeBarrel(s)
    -- a Fine input makes a Fine result likelier
    local fine_in = (a:match("_fine$") and 1 or 0) + (b:match("_fine$") and 1 or 0)
    local fine = rng(100) <= 10 + (s.stats and s.stats.acu or 0) + 25 * fine_in
    s.barrels[i] = { combo = combo, key = r.key, label = r.label, done_at = now + Game.bakeMinutes(a, b) * 60, fine = fine, ins = { a, b } }
    s.story.baked = true
    Game.emit(s, "bake_started")
    Game.tally(s, "bakes")
    return true, i
end

-- Gear baking ---------------------------------------------------------------
local function bagIndex(s, id)
    for i, it in ipairs(s.gear.bag) do if it.id == id then return i, it end end
end

-- Instant: break a pack item into Dust.
function Game.salvageGear(s, id)
    local i, it = bagIndex(s, id)
    if not i or not Game.GEAR then return nil end
    table.remove(s.gear.bag, i)
    local d = Game.GEAR.salvageDust(it)
    s.inv.dust = (s.inv.dust or 0) + d
    say(s, "Salvaged " .. it.name .. ": +" .. d .. " dust.")
    return d
end

function Game.canMerge(s, ida, idb)
    if ida == idb then return false, "Pick two different pieces." end
    local _, a = bagIndex(s, ida)
    local _, b = bagIndex(s, idb)
    if not a or not b then return false, "Both pieces must be in your pack." end
    local d = Game.GEAR.mergeDust(a, b)
    if (s.inv.dust or 0) < d then return false, "Need " .. d .. " dust." end
    if not Game.freeBarrel(s) then return false, "No free barrel." end
    return true, nil, a, b
end

function Game.startMerge(s, ida, idb, now)
    local ok, why, a, b = Game.canMerge(s, ida, idb)
    if not ok then return false, why end
    local dust = Game.GEAR.mergeDust(a, b)
    s.inv.dust = s.inv.dust - dust
    table.remove(s.gear.bag, (bagIndex(s, ida)))
    table.remove(s.gear.bag, (bagIndex(s, idb)))
    local i = Game.freeBarrel(s)
    s.barrels[i] = { merge = { a, b }, dust = dust, label = "Merge", done_at = now + Game.GEAR.mergeMinutes(a, b) * 60 }
    Game.emit(s, "bake_started")
    Game.tally(s, "merges")
    return true, i
end

-- Regrow: a starter kept back from a used item, buried in Dust, regrows into the item.
Game.REGROW_PCT = 20
Game.REGROW_DUST = 2
function Game.regrowDust(key)
    local r = Game.itemRecipe(key)
    return (r and r.tier == 2) and Game.REGROW_DUST * 2 or Game.REGROW_DUST
end

function Game.canRegrow(s, key)
    if (s.starters[key] or 0) < 1 then return false, "No starter." end
    local d = Game.regrowDust(key)
    if (s.inv.dust or 0) < d then return false, "Need " .. d .. " dust." end
    if not Game.freeBarrel(s) then return false, "No free barrel." end
    return true
end

function Game.startRegrow(s, key, now)
    local ok, why = Game.canRegrow(s, key)
    if not ok then return false, why end
    local r = Game.itemRecipe(key)
    s.starters[key] = s.starters[key] - 1
    s.inv.dust = s.inv.dust - Game.regrowDust(key)
    local i = Game.freeBarrel(s)
    s.barrels[i] = { regrow = key, key = key, dust = Game.regrowDust(key), label = r.label, done_at = now + (r.minutes or 30) * 60 }
    Game.emit(s, "bake_started")
    Game.tally(s, "regrows")
    return true, i
end

-- Regional ingredients ------------------------------------------------------
function Game.regionIngredients(region)
    local out = {}
    for _, ing in ipairs(Game.BOOK.ingredients) do
        if ing.region == region then table.insert(out, ing.key) end
    end
    return out
end

-- Base ingredients always; regional ones once you hold any.
function Game.shownIngredients(s)
    local out = {}
    for _, ing in ipairs(Game.BOOK.ingredients) do
        if not ing.region or (s.inv[ing.key] or 0) > 0 then table.insert(out, ing) end
    end
    return out
end

function Game.gainIngredient(s, key, n)
    s.inv[key] = (s.inv[key] or 0) + (n or 1)
    for _, ing in ipairs(Game.BOOK.ingredients) do
        if ing.key == key and ing.region then s.ing_seen = s.ing_seen or {}; s.ing_seen[key] = true end
    end
end

-- Salvage: a batch of one ingredient bakes into one rarer ingredient.
function Game.canSalvage(s, ing)
    local sv = Game.BOOK.salvage
    if not sv then return false, "No salvage." end
    if (s.inv[ing] or 0) < sv.count then return false, "Need " .. sv.count .. " " .. ing .. "." end
    if not Game.freeBarrel(s) then return false, "No free barrel." end
    return true
end

function Game.startSalvage(s, ing, now)
    local ok, why = Game.canSalvage(s, ing)
    if not ok then return false, why end
    local sv = Game.BOOK.salvage
    s.inv[ing] = s.inv[ing] - sv.count
    local i = Game.freeBarrel(s)
    s.barrels[i] = { salvage = ing, label = "Salvage", done_at = now + sv.minutes * 60 }
    Game.emit(s, "bake_started")
    Game.tally(s, "salvages")
    return true, i
end

-- What a salvage of `from` yields: the rarer ingredient you hold fewest of (ties at random).
function Game.salvageOutput(s, from, rng)
    rng = rng or math.random
    local best, low = {}, nil
    for _, k in ipairs(Game.BOOK.salvage.into) do
        if k ~= from then
            local n = s.inv[k] or 0
            if not low or n < low then best, low = { k }, n
            elseif n == low then table.insert(best, k) end
        end
    end
    return best[rng(#best)]
end

local function ingLabel(key)
    for _, ing in ipairs(Game.BOOK.ingredients) do if ing.key == key then return ing.label end end
    local r = Game.itemRecipe and Game.itemRecipe(key)
    return r and r.label or key
end
Game.ingLabel = ingLabel

function Game.barrelStatus(s, i, now)
    local b = s.barrels[i]
    if not b then return "empty" end
    if now >= b.done_at then return "ready" end
    return "baking", b.done_at - now
end

function Game.anyReady(s, now)
    for i = 1, Game.barrelCount(s) do
        if Game.barrelStatus(s, i, now) == "ready" then return true end
    end
    return false
end

-- Returns label, fine, new_discovery, extra line (a nudge after a miss, Cantor on a find)
function Game.collect(s, i, now, rng)
    rng = rng or math.random
    if Game.barrelStatus(s, i, now) ~= "ready" then return nil end
    local b = s.barrels[i]
    s.barrels[i] = false
    if b.salvage then
        local out = Game.salvageOutput(s, b.salvage, rng)
        s.inv[out] = (s.inv[out] or 0) + 1
        local label = ingLabel(out)
        local msg = "Salvaged " .. Game.BOOK.salvage.count .. " " .. ingLabel(b.salvage) .. " into 1 " .. label
        say(s, msg)
        return label, false, false, msg .. "."
    end
    if b.merge then
        local x, y = b.merge[1], b.merge[2]
        local out = Game.GEAR.merge(x, y)
        local _, gone = Game.addItem(s, out)
        table.insert(s.merge_log, 1, { a = x.name, b = y.name, out = out.name,
            before = math.floor(Game.GEAR.score(x) + Game.GEAR.score(y)), after = math.floor(Game.GEAR.score(out)),
            gen = out.gen })
        while #s.merge_log > 20 do table.remove(s.merge_log) end
        say(s, "Merged into " .. out.name .. ".")
        return out.name, false, false, "Merged into " .. out.name .. "." ..
            (gone and ("\nPack full: " .. gone.name .. " salvaged to dust.") or "")
    end
    if b.regrow then
        s.inv[b.key] = (s.inv[b.key] or 0) + 1
        say(s, "Regrew " .. b.label .. ".")
        return b.label, false, false, b.label .. " regrew from its starter."
    end
    local item = b.key .. (b.fine and "_fine" or "")
    s.inv[item] = (s.inv[item] or 0) + 1
    s.tried = s.tried or {}
    s.tried[b.combo] = true
    local new, extra = false, nil
    if Game.BOOK.recipes[b.combo] then
        if not s.journal[b.combo] then
            s.journal[b.combo] = true
            new = true
            local lines = Game.BOOK.found_lines or {}
            if #lines > 0 then extra = lines[rng(#lines)] end
            Game.emit(s, "recipe_found")
        end
    else
        extra = Game.nudge(s, b.combo, rng)
    end
    local label = (b.fine and "Fine " or "") .. b.label
    say(s, "Collected: " .. label .. (new and " (new recipe)" or ""))
    return label, b.fine, new, extra
end

-- After a miss: if either input belongs to a recipe not yet found, say so (without saying which).
function Game.nudge(s, combo, rng)
    rng = rng or math.random
    local a, b = combo:match("^(.-)%+(.+)$")
    if not a then return nil end
    local hits = {}
    for c in pairs(Game.BOOK.recipes) do
        if not s.journal[c] then
            local x, y = c:match("^(.-)%+(.+)$")
            for _, k in ipairs({ a, b }) do
                if (x == k or y == k) then hits[k] = true end
            end
        end
    end
    local keys = {}
    for k in pairs(hits) do table.insert(keys, k) end
    table.sort(keys)
    local lines = Game.BOOK.nudges or {}
    if #keys == 0 or #lines == 0 then return nil end
    local k = keys[rng(#keys)]
    return string.format(lines[rng(#lines)], ingLabel(k):lower())
end

-- Look up a baked item's recipe by item key (with or without _fine)
function Game.itemRecipe(item)
    local base = item:gsub("_fine$", "")
    for _, r in pairs(Game.BOOK.recipes) do if r.key == base then return r end end
    if Game.BOOK.fail_grain and Game.BOOK.fail_grain.key == base then return Game.BOOK.fail_grain end
    if Game.BOOK.fail_other and Game.BOOK.fail_other.key == base then return Game.BOOK.fail_other end
end

-- Use (eat or drink) a baked item. Returns a message or nil.
function Game.useBaked(s, item, now)
    if (s.inv[item] or 0) < 1 then return nil end
    local r = Game.itemRecipe(item)
    if not r then return nil end
    s.inv[item] = s.inv[item] - 1
    local m = item:match("_fine$") and 1.5 or 1
    local e = r.effect
    local out = {}
    local function buff(kind, amt)
        table.insert(s.buffs, { kind = kind, amt = amt, ["until"] = now + math.floor(e.hours * m * 3600) })
    end
    if e.xp_pct then buff("xp_pct", math.floor(e.xp_pct * m)); table.insert(out, "+" .. math.floor(e.xp_pct * m) .. "% XP for " .. math.floor(e.hours * m) .. "h") end
    if e.skill_pct then buff("skill_pct", math.floor(e.skill_pct * m)); table.insert(out, "+" .. math.floor(e.skill_pct * m) .. "% skill XP for " .. math.floor(e.hours * m) .. "h") end
    if e.regen_x then buff("regen_x", e.regen_x); table.insert(out, "Charge regen x" .. e.regen_x .. " for " .. math.floor(e.hours * m) .. "h") end
    if e.hp then
        local maxh = Game.maxHp(s.level, s)
        s.hp = math.min(maxh, s.hp + math.floor(e.hp * m))
        table.insert(out, e.hp >= 999 and "HP full" or ("+" .. math.floor(e.hp * m) .. " HP"))
    end
    if e.integrity then s.integrity = math.min(100, s.integrity + math.floor(e.integrity * m)); table.insert(out, "+" .. math.floor(e.integrity * m) .. "% integrity") end
    if e.charge then s.charge = math.min(Game.maxCharge(s.level, s), s.charge + math.floor(e.charge * m)); table.insert(out, "+" .. math.floor(e.charge * m) .. " Charge") end
    if e.luck_flips then s.luck_flips = (s.luck_flips or 0) + math.floor(e.luck_flips * m); table.insert(out, "next " .. math.floor(e.luck_flips * m) .. " card flips find double") end
    if e.whet then s.whet = math.floor(e.whet * m); table.insert(out, "+" .. s.whet .. " attack next fight") end
    if e.shield then
        if s.shields < 2 then s.shields = s.shields + 1; table.insert(out, "+1 shield")
        else table.insert(out, "shields already full") end
    end
    if e.seal then s.seal = (s.seal or 0) + (m > 1 and 2 or 1); table.insert(out, "next quest: double skill XP") end
    if e.xp then s.xp = s.xp + e.xp; levelUps(s); table.insert(out, "+" .. e.xp .. " XP") end
    local msg = r.label .. ": " .. table.concat(out, ", ")
    -- Regrow: sometimes a starter is kept back (book recipes only, not failures)
    local base = item:gsub("_fine$", "")
    local is_book = false
    for _, rr in pairs(Game.BOOK.recipes) do if rr.key == base then is_book = true end end
    if is_book and math.random(100) <= Game.REGROW_PCT then
        s.starters = s.starters or {}
        s.starters[base] = (s.starters[base] or 0) + 1
        msg = msg .. ". A starter is kept back"
    end
    say(s, msg)
    return msg
end

-- Battle items: every recipe marked battle, weakest heal first (Fine after plain).
function Game.battleItems()
    local list = {}
    for _, r in pairs(Game.BOOK.recipes) do
        if r.battle then
            table.insert(list, { key = r.key, hp = r.effect.hp or 0 })
            table.insert(list, { key = r.key .. "_fine", hp = (r.effect.hp or 0) * 1.5 })
        end
    end
    table.sort(list, function(x, y) if x.hp ~= y.hp then return x.hp < y.hp end return x.key < y.key end)
    local keys = {}
    for _, e in ipairs(list) do table.insert(keys, e.key) end
    return keys
end

-- Battle items you hold, weakest first: { key, label, n }
function Game.heldBattleItems(s)
    local out = {}
    for _, key in ipairs(Game.battleItems()) do
        local n = s.inv[key] or 0
        if n > 0 then
            local r = Game.itemRecipe(key)
            table.insert(out, { key = key, label = (key:match("_fine$") and "Fine " or "") .. r.label, n = n })
        end
    end
    return out
end

function Game.useBattleItem(s, key)
    for _, k in ipairs(Game.battleItems()) do
        if k == key and (s.inv[key] or 0) > 0 then return Game.useBaked(s, key, os.time()) end
    end
end

-- Kept for battle: drink the weakest healing item first.
function Game.drinkPotion(s)
    for _, item in ipairs(Game.battleItems()) do
        if (s.inv[item] or 0) > 0 then return Game.useBaked(s, item, os.time()) end
    end
end

function Game.potionCount(s)
    local n = 0
    for _, item in ipairs(Game.battleItems()) do n = n + (s.inv[item] or 0) end
    return n
end

-- Exploration -------------------------------------------------------------

function Game.logSteps(s, steps)
    s.range = s.range + math.floor(steps / 1000)
end

-- Daily step totals from the phone: { ["YYYY-MM-DD"] = total }. The phone resends
-- the whole day's total each time, so only the growth since the last sync pays.
-- Days before the map unlock never pay (no retroactive Range); days older than
-- two weeks are ignored. Returns Range gained, and how many days looked like the
-- future (Kindle clock behind), which the caller should keep for a later sync.
local function dateTime(key)
    local y, m, d = tostring(key):match("^(%d%d%d%d)-(%d%d)-(%d%d)$")
    if not y then return nil end
    return os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }
end

local STEP_WINDOW = 14 * DAY   -- days older than this are neither paid nor remembered

function Game.syncSteps(s, days, now)
    now = now or os.time()
    s.steps_synced = s.steps_synced or {}
    s.step_carry = s.step_carry or 0
    local new_steps, future = 0, 0
    for key, total in pairs(days) do
        local t = dateTime(key)
        total = math.floor(tonumber(total) or 0)
        if t and t > now + DAY then
            future = future + 1
        elseif t and now - t <= STEP_WINDOW and total > 0 and Game.dayIndex(s, t) >= (Game.UNLOCK_DAY.map or 0)
            and not Game.isPausedDay(s, key) then
            local before = s.steps_synced[key] or 0
            if total > before then
                new_steps = new_steps + (total - before)
                s.steps_synced[key] = total
            end
        end
    end
    -- 1 Range per 1,000 steps, with leftover steps carried across days.
    s.step_carry = s.step_carry + new_steps
    local gained = math.floor(s.step_carry / 1000)
    s.step_carry = s.step_carry - gained * 1000
    s.range = s.range + gained
    for key in pairs(s.steps_synced) do
        local t = dateTime(key)
        if not t or now - t > STEP_WINDOW then s.steps_synced[key] = nil end
    end
    return gained, future
end

function Game.stepsToday(s, now)
    return (s.steps_synced or {})[dayKey(now or os.time())] or 0
end

-- The route (real stage lengths, km). Stage n ends at STAGE_END[n].
Game.STAGE_KM = { 19, 14, 18, 20, 24, 22, 20, 21, 30, 26, 25 }
local KM_PER_CARD = 0.75
local STAGE_END = {}
do local c = 0; for i, k in ipairs(Game.STAGE_KM) do c = c + k; STAGE_END[i] = c end end
Game.STAGE_END = STAGE_END
Game.STAGE_NAMES = { "Shepherdswell", "Dover", "Guînes", "Licques", "Wisques", "Thérouanne",
    "Amettes", "Bruay-la-Buissière", "Arras", "Bapaume", "Péronne" }

-- Guardians block the route at the end of their stage until beaten.
Game.GUARDIANS = {
    [2] = { name = "Cliffwarden", hp = 22, atk = 3, lv = 3, sprite = "cliffwarden", rescue_turn = 2 },
    -- Region guardians (stats live in combat.lua; these fallbacks only run without Combat).
    [14] = { name = "Drillbit", hp = 40, atk = 5, lv = 9, sprite = "drillbit" },
    [23] = { name = "Talus", hp = 55, atk = 7, lv = 13, sprite = "talus" },
}

-- Full route (all 83 stages, regions, map geometry) from route.lua. main.lua calls this at load;
-- without it the first 11 stages above still work (tests, old installs).
function Game.setRoute(r)
    Game.ROUTE = r
    Game.STAGE_KM, Game.STAGE_NAMES = {}, {}
    for k in pairs(STAGE_END) do STAGE_END[k] = nil end
    local c = 0
    for i, st in ipairs(r.stages) do
        Game.STAGE_KM[i], Game.STAGE_NAMES[i] = st.km, st.name
        c = c + st.km
        STAGE_END[i] = c
    end
end

-- Region you're in: the first whose end you haven't passed (you stay in it while at its gate).
function Game.currentRegion(s)
    local regions = Game.ROUTE and Game.ROUTE.regions
    if not regions then return nil end
    for i, r in ipairs(regions) do
        if s.route.km <= r.km1 + 1e-9 then return i, r end
    end
    return #regions, regions[#regions]
end

-- Point on a map polyline { {x, y, km}, ... } for a route km (clamped to the ends).
function Game.mapPoint(path, km)
    if km <= path[1][3] then return path[1][1], path[1][2] end
    for i = 2, #path do
        local a, b = path[i - 1], path[i]
        if km <= b[3] then
            local t = (b[3] > a[3]) and (km - a[3]) / (b[3] - a[3]) or 0
            return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t
        end
    end
    local last = path[#path]
    return last[1], last[2]
end

-- "My road" map: the smallest Canterbury-to-somewhere map that still shows some road ahead.
function Game.journeyFor(km)
    local js = Game.ROUTE and Game.ROUTE.journeys
    if not js or #js == 0 then return nil end
    for _, j in ipairs(js) do
        if j.km1 >= km * 1.1 + 5 then return j end
    end
    return js[#js]
end

function Game.routeDone(s)
    return s.route.km >= STAGE_END[#STAGE_END] - 1e-9
end

function Game.currentStage(s)
    for i, e in ipairs(STAGE_END) do
        if s.route.km < e then return i end
    end
    return #STAGE_END
end

-- km left to the end of the current stage (the next town)
function Game.kmToNextStage(s)
    local st = Game.currentStage(s)
    return math.max(0, (STAGE_END[st] or 0) - s.route.km), st
end

-- Front pressure: about 1 point per 40 km from 1013.
function Game.frontPressure(s)
    return 1013 - math.floor(s.route.km / 40)
end

local MONSTERS = {
    { name = "Rust Crawler",  hp = 14, atk = 3, lv = 2, sprite = "rust_crawler" },
    { name = "Static Wisp",   hp = 10, atk = 4, lv = 3, sprite = "static_wisp" },
    { name = "Scrap Hound",   hp = 18, atk = 3, lv = 3, sprite = "scrap_hound" },
}

Game.DRY_MAX = 5
-- rng: optional function(n) -> 1..n, for testing
function Game.flipCard(s, rng)
    rng = rng or math.random
    if s.fight then return "fight", "Finish the current fight first." end
    local combat = Game.unlocked(s, "combat")
    -- A guardian at the end of this stage blocks the way.
    local order = {}
    for n in pairs(Game.GUARDIANS) do order[#order + 1] = n end
    table.sort(order)  -- nearest first, so a save past several meets them in road order
    for _, n in ipairs(order) do
        local g = Game.GUARDIANS[n]
        if not s.route.guardians[n] and STAGE_END[n] and s.route.km >= STAGE_END[n] - 1e-9 then
            if not combat then
                return "none", "Something waits at " .. Game.STAGE_NAMES[n] .. ". You wait in town until you can fight (" .. Game.daysUntil(s, "combat") .. " days)."
            end
            if Game.COMBAT and Game.COMBAT.GUARDIANS[n] then
                s.fight = Game.COMBAT.newGuardian(s, n)
                Game.tally(s, "guardian_tries")
                s.dry_flips = 0
            else
                s.fight = { name = g.name, hp = g.hp, max = g.hp, atk = g.atk, lv = g.lv, sprite = g.sprite,
                    boss = n, rescue_turn = g.rescue_turn, turn = 0 }
            end
            Game.emit(s, "guardian:" .. n)
            return "monster", "The " .. g.name .. " stands at the end of the road."
        end
    end
    if Game.routeDone(s) then return "none", "You've reached Rome. The road ends here." end
    if s.range < 1 then return "none", "Not enough Range. Walk more." end
    s.range = s.range - 1
    local before = s.route.km
    if before == 0 then Game.emit(s, "route_start") end
    local after = math.min(before + KM_PER_CARD, STAGE_END[#STAGE_END])
    for n, g in pairs(Game.GUARDIANS) do  -- never walk past an unbeaten guardian
        if not s.route.guardians[n] and STAGE_END[n] and before < STAGE_END[n] then after = math.min(after, STAGE_END[n]) end
    end
    s.route.km = after
    for n, e in ipairs(STAGE_END) do
        if before < e and after >= e - 1e-9 then
            Game.emit(s, "stage_end:" .. n)
            say(s, "Reached " .. Game.STAGE_NAMES[n] .. ".")
        end
    end
    for _, mark in ipairs({ 100 }) do
        if before < mark and after >= mark then Game.emit(s, "km:" .. mark) end
    end
    local roll = rng(100)
    -- streak breaker: after DRY_MAX flips with no fight, the next one is a fight
    if combat then
        if (s.dry_flips or 0) >= Game.DRY_MAX then roll = 61 end
        if roll > 60 and roll <= 90 then s.dry_flips = 0 else s.dry_flips = (s.dry_flips or 0) + 1 end
    end
    if roll <= 30 then
        local n = rng(3)
        if (s.luck_flips or 0) > 0 then n = n * 2 end
        s.inv.dust = s.inv.dust + n
        if (s.luck_flips or 0) > 0 then s.luck_flips = s.luck_flips - 1 end
        return "salvage", "Salvage: +" .. n .. " dust."
    elseif roll <= 60 then
        local mat = rng(2) == 1 and "grain" or "herb"
        local local_ings = Game.regionIngredients(Game.currentRegion(s) or 1)
        if #local_ings > 0 and rng(100) <= 40 then mat = local_ings[rng(#local_ings)] end
        local n = 1
        if (s.luck_flips or 0) > 0 then n = 2; s.luck_flips = s.luck_flips - 1 end
        Game.gainIngredient(s, mat, n)
        return "forage", "Forage: +" .. n .. " " .. Game.ingLabel(mat):lower() .. "."
    elseif roll <= 90 and not combat then
        return "nothing", "Tracks of something big. You steer around it."
    elseif roll <= 90 then
        if Game.COMBAT then
            s.fight = Game.COMBAT.newMonster(s, rng)
        else
            local m = MONSTERS[rng(#MONSTERS)]
            s.fight = { name = m.name, hp = m.hp, max = m.hp, atk = m.atk, lv = m.lv, sprite = m.sprite }
        end
        local m = s.fight
        return "monster", "A " .. m.name .. " blocks the path."
    end
    return "nothing", "Nothing here but the view."
end

-- Combat ------------------------------------------------------------------

local function enemyTurn(s, rng)
    local f = s.fight
    if f.boss then
        f.turn = (f.turn or 0) + 1
        if f.turn == f.rescue_turn and not f.rescued then
            f.rescued = true
            Game.emit(s, "rescue:" .. f.boss)
            return "✦ UNSCHEDULED INTERVENTION. " .. f.name .. "'s braced arm gives way. It loses its turn."
        end
    end
    local dmg = math.max(1, f.atk + rng(3) - 2)
    s.hp = s.hp - dmg
    local line = f.name .. " hits you for " .. dmg .. "."
    if s.hp <= 0 then
        s.hp = 1
        s.fight = nil
        return line .. " You retreat. Nothing lost."
    end
    return line
end

local function win(s, rng)
    local f = s.fight
    s.fight = nil
    s.whet = 0
    if f.boss then
        s.route.guardians[f.boss] = true
        Game.emit(s, "guardian_beaten:" .. f.boss)
    end
    local dust = 1 + rng(2)
    s.inv.dust = s.inv.dust + dust
    s.xp = s.xp + 5
    levelUps(s)
    return "Defeated " .. f.name .. ". +" .. dust .. " dust, +5 XP."
end

-- action: "attack" | "spark" | "potion" | "retreat"
function Game.fightAction(s, action, rng)
    rng = rng or math.random
    if Game.COMBAT then
        local map = { potion = "item", retreat = "run" }
        return Game.COMBAT.act(s, map[action] or action, rng)
    end
    local f = s.fight
    if not f then return "No fight." end
    local lines = {}
    if action == "retreat" then
        s.fight = nil
        return "You retreat. The enemy heals. Nothing lost."
    elseif action == "attack" then
        local dmg = 2 + rng(4) + math.floor(s.level / 2) + math.floor((s.stats and s.stats.str or 0) / 2) + (s.whet or 0)
        f.hp = f.hp - dmg
        table.insert(lines, "You strike for " .. dmg .. ".")
    elseif action == "spark" then
        if s.charge < 3 then return "Not enough Charge (need 3)." end
        s.charge = s.charge - 3
        local dmg = 7 + rng(5)
        f.hp = f.hp - dmg
        table.insert(lines, "Spark hits for " .. dmg .. ". (-3 Charge)")
    elseif action == "potion" then
        local m = Game.drinkPotion(s)
        if not m then return "No potions." end
        table.insert(lines, m .. ".")
    end
    if f.hp <= 0 then
        table.insert(lines, win(s, rng))
    else
        table.insert(lines, enemyTurn(s, rng))
    end
    return table.concat(lines, " ")
end

-- Companion idle line (story scenes come from story.lua) ---------------------

function Game.companionLine(s, now)
    if s.story and s.story.silent_day == dayKey(now) then return "..." end
    if s.integrity < 60 then return "Systems failing. One Daily Directive, that's all I ask." end
    if not s.daily_done and not s.daily_id then return "No Daily Directive set. Pick one. Today." end
    if Game.anyReady(s, now) then return "Something's ready in the barrel." end
    if s.daily_done then return "Daily Directive done. Look at you, functioning." end
    return "Clock is running. Pick something and finish it."
end

-- RECORDS page (Mike, 2026-10-22): numbers from the chronicle's lines -----------------
-- lines: chronicle TSV lines (date time event kind tier xp skills title). Pure, for tests.
function Game.chronicleStats(lines, now, ndays)
    ndays = ndays or 14
    local st = {
        days = {},                      -- last ndays, oldest first: { key=, wday=, done=, xp= }
        week = { done = 0, deleted = 0, skipped = 0, dailies = 0, xp = 0, usd = 0, tiers = {} },
        all = { done = 0, deleted = 0, skipped = 0, xp = 0, tiers = {}, first = nil, best_day = nil, best_n = 0 },
        hours = { 0, 0, 0, 0 },         -- done in the morning (5-12), afternoon (12-17), evening (17-22), night
        skills = {},                    -- { key=, n= } most first (all time)
    }
    local idx = {}
    for k = ndays - 1, 0, -1 do
        local t = addDays(now, -k)  -- noon steps: DST never skips or repeats a date
        local d = { key = dayKey(t), wday = tonumber(os.date("%w", t)) + 1, done = 0, xp = 0 }
        table.insert(st.days, d); idx[d.key] = d
    end
    local week_from = dayKey(addDays(now, -6))
    local per_day, skill_n = {}, {}
    for _, line in ipairs(lines or {}) do
        local date, time, ev, kind, tier, xp, skills = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)")
        if date and date:match("^%d%d%d%d%-%d%d%-%d%d$") then
            xp = tonumber(xp) or 0
            local A = st.all
            A.first = A.first or date
            if ev == "done" then
                A.done, A.xp = A.done + 1, A.xp + xp
                A.tiers[tier] = (A.tiers[tier] or 0) + 1
                per_day[date] = (per_day[date] or 0) + 1
                if per_day[date] > A.best_n then A.best_n, A.best_day = per_day[date], date end
                local h = tonumber((time or ""):match("^(%d+)")) or 0
                local slot = (h >= 5 and h < 12 and 1) or (h >= 12 and h < 17 and 2) or (h >= 17 and h < 22 and 3) or 4
                st.hours[slot] = st.hours[slot] + 1
                for k in (skills or ""):gmatch("[^,]+") do if k ~= "-" then skill_n[k] = (skill_n[k] or 0) + 1 end end
                if idx[date] then idx[date].done = idx[date].done + 1; idx[date].xp = idx[date].xp + xp end
            elseif ev == "deleted" then A.deleted = A.deleted + 1
            elseif ev == "skipped" then A.skipped = A.skipped + 1 end
            if date >= week_from and date <= dayKey(now) then
                local W = st.week
                if ev == "done" then
                    W.done, W.xp = W.done + 1, W.xp + xp
                    W.tiers[tier] = (W.tiers[tier] or 0) + 1
                    W.usd = W.usd + (Game.GOLD_BY_TIER[tier] or 0) / Game.GOLD_PER_DOLLAR
                    if kind == "daily" then W.dailies = W.dailies + 1 end
                elseif ev == "deleted" then W.deleted = W.deleted + 1
                elseif ev == "skipped" then W.skipped = W.skipped + 1 end
            end
        end
    end
    for k, n in pairs(skill_n) do table.insert(st.skills, { key = k, n = n }) end
    table.sort(st.skills, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.key < b.key end)
    if st.all.first then
        local y, m, d = st.all.first:match("^(%d+)-(%d+)-(%d+)")
        local span = math.floor((dayStart(now) - dayStart(os.time{ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })) / DAY + 0.5) + 1
        st.all.days = math.max(1, span)
    end
    return st
end

-- Gold and loot (Mike, 2026-10-20) -------------------------------------------
-- Quests earn gold from their tier's base XP. Gold buys nothing in the game: it
-- claims real-world loot that Mike then buys himself with his own money.
-- Target pace: $10-20 of loot a week with steady effort ($15). The rate is an
-- estimate from 16 days of status reports; retune from the chronicle.
Game.GOLD_PER_DOLLAR = 10
-- Flat gold by tier (Mike, 2026-10-22): $0.25, $0.50, $2, $10.
Game.GOLD_BY_TIER = { minor = 2.5, standard = 5, major = 20, epic = 100 }

-- New players start with an empty LOOT list and add their own rewards (shared build,
-- 2026-10-23). Existing saves keep their list: this only seeds a save with no loot yet.
Game.STARTING_LOOT = {}

function Game.newLoot()
    local l = { gold = 0, items = {}, claims = {}, next_id = 1 }
    for _, it in ipairs(Game.STARTING_LOOT) do
        table.insert(l.items, { id = l.next_id, name = it.name, usd = it.usd })
        l.next_id = l.next_id + 1
    end
    return l
end

local function loot(s)
    s.loot = s.loot or Game.newLoot()
    return s.loot
end

function Game.goldBalance(s) return loot(s).gold or 0 end
function Game.addGold(s, n)
    local l = loot(s)
    l.gold = (l.gold or 0) + (n or 0)
    l.earned = (l.earned or 0) + (n or 0)
end
function Game.lootPrice(item) return math.floor((item.usd or 0) * Game.GOLD_PER_DOLLAR + 0.5) end

-- "Bandsaw $200", "Bandsaw 200", "$12.50 socks" -> name, dollars (nil if no price)
function Game.parseLoot(text)
    text = tostring(text or "")
    local num = text:match("%$%s*([%d,]+%.?%d*)") or text:match("([%d,]+%.?%d*)%s*$")
    local usd = num and tonumber((num:gsub(",", "")))
    local name = text
    if num then
        name = name:gsub("%$%s*" .. num:gsub("%p", "%%%0"), "", 1)
        if name == text then name = name:gsub(num:gsub("%p", "%%%0") .. "%s*$", "", 1) end
    end
    name = name:gsub("%s*[-:]%s*$", ""):gsub("^%s*[-:]%s*", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or not usd or usd <= 0 then return nil end
    return name, usd
end

function Game.addLoot(s, name, usd)
    local l = loot(s)
    local it = { id = l.next_id, name = name, usd = usd }
    l.next_id = l.next_id + 1
    table.insert(l.items, it)
    return it
end

function Game.removeLoot(s, id)
    local l = loot(s)
    for i, it in ipairs(l.items) do
        if it.id == id then table.remove(l.items, i); return it end
    end
end

-- Spend the gold and log the claim. Mike buys the item himself.
function Game.claimLoot(s, id, now)
    local l = loot(s)
    for i, it in ipairs(l.items) do
        if it.id == id then
            local price = Game.lootPrice(it)
            if l.gold < price then return false, string.format("Need %d more gold.", math.ceil(price - l.gold)) end
            l.gold = l.gold - price
            table.remove(l.items, i)
            table.insert(l.claims, 1, { name = it.name, usd = it.usd, gold = price, date = os.date("%Y-%m-%d", now or os.time()) })
            while #l.claims > 50 do table.remove(l.claims) end
            say(s, "Loot claimed: " .. it.name .. ".")
            return true, it
        end
    end
    return false, "Not on the list."
end

-- Cancel a barrel (Mike, 2026-10-20). Rule 1: everything that went in comes back.
-- Returns a line saying what came back, or nil if the barrel isn't baking.
function Game.cancelBarrel(s, i, now)
    local b = s.barrels[i]
    if not b or Game.barrelStatus(s, i, now) ~= "baking" then return nil end
    local back
    if b.salvage then
        local n = Game.BOOK.salvage.count
        s.inv[b.salvage] = (s.inv[b.salvage] or 0) + n
        back = n .. " " .. ingLabel(b.salvage)
    elseif b.merge then
        s.gear.bag = s.gear.bag or {}
        -- straight back into the pack, past the pack limit if need be: nothing is auto-salvaged
        for _, it in ipairs(b.merge) do table.insert(s.gear.bag, it) end
        local d = b.dust or Game.GEAR.mergeDust(b.merge[1], b.merge[2])
        s.inv.dust = (s.inv.dust or 0) + d
        back = b.merge[1].name .. ", " .. b.merge[2].name .. " and " .. d .. " dust"
    elseif b.regrow then
        s.starters[b.regrow] = (s.starters[b.regrow] or 0) + 1
        local d = b.dust or Game.regrowDust(b.regrow)
        s.inv.dust = (s.inv.dust or 0) + d
        back = "the " .. b.label .. " starter and " .. d .. " dust"
    else
        -- bakes from before v37 don't record Fine inputs; they come back plain
        local ins = b.ins
        if not ins then ins = { b.combo:match("^(.-)%+(.+)$") } end
        local names = {}
        for _, k in ipairs(ins) do
            s.inv[k] = (s.inv[k] or 0) + 1
            table.insert(names, (k:match("_fine$") and "Fine " or "") .. ingLabel(baseKey(k)))
        end
        back = table.concat(names, " and ")
    end
    s.barrels[i] = false
    local key = b.salvage and "salvages" or (b.merge and "merges") or (b.regrow and "regrows") or "bakes"
    if s.tally and (s.tally[key] or 0) > 0 then s.tally[key] = s.tally[key] - 1 end
    say(s, "Barrel " .. i .. " emptied: " .. back .. " back.")
    return back
end

return Game
