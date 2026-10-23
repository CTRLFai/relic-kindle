-- Pause / resume (cruise, 2026-10-07). Run from relic.koplugin/:  luajit ../tools/tests/test_pause.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local DAY = 86400
local function noon(y, m, d, h) return os.time{ year = y, month = m, day = d, hour = h or 12 } end

-- a player 12 days in, streak 6, daily done today, a bake and a buff running
local t0 = noon(2026, 10, 10, 20)
local s = Game.newState(t0 - 12 * DAY)
Game.tick(s, t0)
s.streak, s.integrity, s.shields = 6, 90, 1
local q = Game.addQuest(s, "x", "standard"); Game.setDaily(s, q.id); s.daily_done = true
s.barrels[1] = { combo = "grain+grain", key = "bread", label = "Bread", done_at = t0 + 3600 }
s.buffs = { { kind = "xp_pct", amt = 10, ["until"] = t0 + 7200 } }
s.charge = 0; s.charge_ts = t0
local day0 = Game.dayIndex(s, t0)

assert(Game.pause(s, t0)); assert(not Game.pause(s, t0), "can't pause twice")
-- five days away: ticking does nothing
local t1 = noon(2026, 10, 16, 9)
Game.tick(s, t1)
assert(s.streak == 6 and s.integrity == 90 and s.shields == 1 and s.charge == 0, "nothing moves while paused")
-- steps on paused days don't count, the day before the pause does
local g = Game.syncSteps(s, { ["2026-10-12"] = 9000, ["2026-10-14"] = 9000, ["2026-10-09"] = 5000 }, t1)
assert(g == 5, "only the pre-pause day pays: " .. g)

local ok, days = Game.resume(s, t1); assert(ok and days == 6, tostring(days))
Game.tick(s, t1 + 60)
assert(s.streak == 6 and s.integrity == 90 and s.shields == 1, "no misses for paused days")
assert(Game.dayIndex(s, t1) == day0 + 1, "resume day is the day after the pause day")
assert(not s.daily_done and not s.daily_id, "fresh Daily on the day you resume")
assert(s.barrels[1].done_at - t1 == 3600, "bake time left is kept")
assert(s.buffs[1]["until"] - t1 == 7200, "buff time left is kept")
assert(s.charge == 0, "no regen while away")
-- paused days still don't pay steps after resuming
g = Game.syncSteps(s, { ["2026-10-13"] = 4000 }, t1 + 120); assert(g == 0)
-- the next day without a Daily is a normal miss again
Game.tick(s, noon(2026, 10, 17))
assert(s.shields == 0, "after resume, misses count again (shield used)")

-- same-day pause and resume changes nothing
s = Game.newState(t0 - 3 * DAY); Game.tick(s, t0); s.daily_done = true; s.streak = 2
Game.pause(s, t0); Game.resume(s, t0 + 600); Game.tick(s, t0 + 700)
assert(s.daily_done and s.streak == 2)
print("pause ok")
