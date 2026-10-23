-- Recurring quests and move mode (v39). Run from relic.koplugin/:  luajit ../tools/tests/test_recurring.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
Game.GEAR = dofile("gear.lua")

local function at(y, m, d, h) return os.time{ year = y, month = m, day = d, hour = h or 9 } end
local thu = at(2026, 10, 22)            -- a Thursday
assert(os.date("%w", thu) == "4")

-- migration adds the sleeping list
local old = Game.newState(thu); old.save_version = 13; old.sleeping = nil
assert(Game.migrate(old).save_version == 14 and type(old.sleeping) == "table")

-- next scheduled day
assert(Game.nextRepDay({ kind = "daily" }, thu) == "2026-10-23")
assert(Game.nextRepDay({ kind = "weekdays" }, at(2026, 10, 23)) == "2026-10-26")  -- Fri -> Mon
assert(Game.nextRepDay({ kind = "days", days = { [2] = true } }, thu) == "2026-10-26")  -- next Monday
assert(Game.nextRepDay({ kind = "every", n = 3 }, thu) == "2026-10-25")
assert(Game.repText({ kind = "days", days = { [2] = true, [6] = true, [1] = true } }) == "Mon, Fri, Sun")

-- daily walk: done today -> gone, back tomorrow, unchecked, at the same spot; only ever one copy
local s = Game.newState(thu)
Game.addQuest(s, "first", "minor")
local walk = Game.addQuest(s, "Morning walk", "standard")
Game.addQuest(s, "third", "minor")
assert(Game.setRepeat(s, walk.id, { kind = "daily" }))
Game.addStep(s, walk.id, "shoes")
Game.toggleStep(s, walk.id, 1, thu)
Game.completeQuest(s, walk.id, thu)
assert(not Game.findQuest(s, walk.id) and #s.sleeping == 1)
local g1 = Game.goldBalance(s)
assert(g1 == 5)  -- standard pays like any quest
Game.tick(s, thu + 3600)
assert(not Game.findQuest(s, walk.id))          -- not back the same day
s.last_day = "2026-10-22"
Game.tick(s, at(2026, 10, 23, 8))
local w, pos = Game.findQuest(s, walk.id)
assert(w and pos == 2 and #s.sleeping == 0, pos)
assert(not w.steps[1].done and not w.steps[1].paid and not w.paid)
-- missed Friday: Saturday still one copy
Game.tick(s, at(2026, 10, 24, 8))
local count = 0
for _, q in ipairs(s.quests) do if q.title == "Morning walk" then count = count + 1 end end
assert(count == 1)

-- skip: off the list without reward, back on the next day; Daily Directive cleared
s.daily_id = walk.id
local xp, gold = s.xp, Game.goldBalance(s)
assert(Game.skipRecurring(s, walk.id, at(2026, 10, 24, 9)))
assert(not Game.findQuest(s, walk.id) and s.xp == xp and Game.goldBalance(s) == gold and s.daily_id == nil)
assert(s.sleeping[1].wake == "2026-10-25")
-- stop repeating while asleep drops it
assert(Game.stopRecurring(s, walk.id) and #s.sleeping == 0)

-- a repeating quest has no due date (it rolls over, never late)
local q2 = Game.addQuest(s, "Gym", "major"); q2.due = "2026-10-01"
assert(Game.setRepeat(s, q2.id, { kind = "days", days = { [2] = true } }) and q2.due == nil)
assert(not Game.setRepeat(s, q2.id, { kind = "days", days = {} }))
assert(not Game.setRepeat(s, q2.id, { kind = "every", n = 0 }))

-- Todoist recurrence text
local function k(str, due) local r = Game.parseRecurrence(str, due); return r.kind, r.n, r.days end
assert(k("every day") == "daily")
assert(k("every morning") == "daily")
assert(k("every weekday") == "weekdays")
assert(select(2, k("every 3 days")) == 3)
assert(select(2, k("every other day")) == 2)
assert(select(2, k("every 2 weeks")) == 14)
assert(select(2, k("every month")) == 30)
local _, _, d = k("every mon, fri")
assert(d[2] and d[6] and not d[4])
_, _, d = k("Every Tuesday and Thursday starting oct 1")
assert(d[3] and d[5] and not d[2])
_, _, d = k("every monday")
assert(d[2])
_, _, d = k("every week", "2026-10-22")
assert(d[5])

-- move mode: up / down / top, inside the quest's group
local m = Game.newState(thu)
local a = Game.addQuest(m, "A", "minor"); local b = Game.addQuest(m, "B", "minor")
local c = Game.addQuest(m, "C", "minor"); local wq = Game.addQuest(m, "W", "minor"); wq.waiting = true
local function order() local t = {} for _, q in ipairs(Game.orderedQuests(m, thu)) do table.insert(t, q.title) end return table.concat(t) end
assert(order() == "ABCW")
assert(Game.nudgeQuest(m, c.id, "up", thu) and order() == "ACBW")
assert(Game.nudgeQuest(m, a.id, "down", thu) and order() == "CABW")
assert(Game.nudgeQuest(m, a.id, "down", thu) and order() == "CBAW", order())
local ok, why = Game.nudgeQuest(m, a.id, "down", thu)
assert(not ok and why and order() == "CBAW")              -- waiting stays last
assert(Game.nudgeQuest(m, a.id, "top", thu) and order() == "ACBW")
ok = Game.nudgeQuest(m, a.id, "up", thu); assert(not ok)
local late = Game.addQuest(m, "L", "minor"); late.due = "2026-10-01"
assert(order() == "LACBW")
ok, why = Game.nudgeQuest(m, late.id, "down", thu); assert(not ok and why:match("Late"))
ok = Game.nudgeQuest(m, a.id, "up", thu); assert(not ok)  -- can't climb above a late quest
print("recurring + move ok")

-- RECORDS: stats from chronicle lines
do
  local now = os.time{ year = 2026, month = 10, day = 22, hour = 20 }
  local L = {
    "2026-10-01\t08:10\tdone\tside\tminor\t10\t-\told one",
    "2026-10-20\t08:10\tdone\tdaily\tstandard\t25\tfitness\twalk",
    "2026-10-20\t13:00\tdone\tside\tmajor\t60\tfitness,admin\tproposal",
    "2026-10-21\t21:30\tdone\tside\tepic\t150\tadmin\tbig",
    "2026-10-22\t23:30\tdeleted\tside\tminor\t0\t-\tnope",
    "2026-10-22\t07:00\tskipped\tside\tstandard\t0\t-\twalk",
    "garbage line",
  }
  local st = Game.chronicleStats(L, now)
  assert(#st.days == 14 and st.days[14].key == "2026-10-22" and st.days[12].done == 2)
  assert(st.week.done == 3 and st.week.deleted == 1 and st.week.skipped == 1 and st.week.dailies == 1)
  assert(st.week.xp == 235 and math.abs(st.week.usd - 12.5) < 1e-9, st.week.usd)
  assert(st.all.done == 4 and st.all.first == "2026-10-01" and st.all.days == 22 and st.all.best_n == 2)
  assert(st.hours[1] == 2 and st.hours[2] == 1 and st.hours[3] == 1)
  assert(st.skills[1].key == "admin" or st.skills[1].key == "fitness")
  assert(Game.chronicleStats({}, now).all.done == 0)
  print("records stats ok")
end

-- review fixes: DST-safe 14-day chart; chronicle XP keeps step XP for repeating quests
do
  local now = os.time{ year = 2026, month = 11, day = 1, hour = 23, min = 30 }  -- US clocks change that morning
  local st = Game.chronicleStats({}, now, 14)
  local seen = {}
  for _, d in ipairs(st.days) do assert(not seen[d.key], d.key); seen[d.key] = true end
  assert(st.days[1].key == "2026-10-19" and st.days[14].key == "2026-11-01")
  local s = Game.newState(thu)
  local q = Game.addQuest(s, "walk", "standard"); Game.setRepeat(s, q.id, { kind = "daily" })
  Game.addStep(s, q.id, "a"); Game.addStep(s, q.id, "b")
  Game.toggleStep(s, q.id, 1, thu)
  local paid = q.paid
  assert(paid and paid > 0)
  local _, rec = Game.completeQuest(s, q.id, thu)
  assert(rec.xp == 25, rec.xp)
  print("review fixes ok")
end
