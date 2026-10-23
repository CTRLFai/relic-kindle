-- Practice: Meditate, Pomodoro, timed-quest bonus and time log. Run from relic.koplugin/:  luajit ../tools/tests/test_practice.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local now = (function() local t = os.date("*t"); return os.time{ year = t.year, month = t.month, day = t.day, hour = 8 } end)()  -- fixed morning: the daily caps must not cross midnight
local function fresh() local s = Game.newState(now - 86400); s.level = 5; return s end

-- 1. meditate: can't finish early; pays XP, Charge, Focus; daily cap; one session at a time
local s = fresh(); s.charge = 0
assert(not Game.startMeditate(s, 7, now))
assert(Game.startMeditate(s, 10, now))
assert(not Game.startMeditate(s, 5, now), "one session at a time")
local m, why = Game.finishSession(s, now + 300); assert(not m and why:find("min to go"))
local xp0 = s.xp
m = Game.finishSession(s, now + 600); assert(m and s.xp == xp0 + 10 and s.charge == 4 and s.skills.focus, m)
for i = 1, 3 do Game.startMeditate(s, 20, now + 1000 * i); Game.finishSession(s, now + 1000 * i + 1200) end
assert(s.practice.med_min == 70)
local xp1 = s.xp
Game.startMeditate(s, 5, now + 9000); m = Game.finishSession(s, now + 9300); assert(s.xp == xp1 and m:find("used up"), m)
-- focus ranks raise the Focus stat
local foc0 = s.stats.foc
s.skills.focus.xp = 0; s.skills.focus.rank = 1
for d = 1, 6 do
  local t = now + d * 86400
  Game.startMeditate(s, 20, t); Game.finishSession(s, t + 1200)
  Game.startMeditate(s, 20, t + 2000); Game.finishSession(s, t + 3200)
end
assert(s.skills.focus.rank >= 4 and s.stats.foc >= foc0 + 2, s.skills.focus.rank)

-- 2. pomodoro on a quest: logged on the quest; finishing the quest pays +20% and fills the time log
s = fresh()
local q = Game.addQuest and Game.addQuest(s, "Write the blog post", "standard")
if not q then for _, x in ipairs(s.quests) do q = x end end
assert(q, "need a quest")
local qid = q.id or q
assert(not Game.startPomodoro(s, 999, now))
assert(Game.startPomodoro(s, qid, now))
assert(Game.finishSession(s, now + 1500))
local qq = Game.findQuest(s, qid); assert(qq.pomos == 1 and qq.minutes == 25)
local xpB = s.xp
Game.completeQuest(s, qid, now + 2000)
local gained = s.xp - xpB
assert(gained >= 30 and gained <= 31, gained)   -- 25 * 1.2
assert(s.timelog.standard and s.timelog.standard.n == 1 and s.timelog.standard.min == 25)
-- completing the quest a pomodoro runs on ends the session
s = fresh(); local q2 = Game.addQuest(s, "Fix the gate", "minor"); local id2 = q2.id or q2
Game.startPomodoro(s, id2, now); Game.completeQuest(s, id2, now + 60); assert(not s.practice.session)

-- 3. migration
local old = Game.newState(now); old.save_version = 7; old.practice = nil; old.timelog = nil
local mm = Game.migrate(old); assert(mm.practice and mm.timelog)
print("practice ok")
-- review fixes: a finished Pomodoro not yet tapped still counts when the quest completes; buffs cap
s = fresh(); local q3 = Game.addQuest(s, "Clean the garage", "standard")
Game.startPomodoro(s, q3.id, now); local x0 = s.xp
Game.completeQuest(s, q3.id, now + 1600)
assert(s.timelog.standard and s.timelog.standard.min == 25 and s.xp - x0 >= 35, s.xp - x0)  -- 5 + 30
s = fresh(); for i = 1, 5 do table.insert(s.buffs, { kind = "xp_pct", amt = 25, ["until"] = now + 3600 }) end
assert(Game.buffTotal(s, "xp_pct", now) == 50)
print("practice review fixes ok")
-- streak breaker: never more than DRY_MAX fight-less flips in a row
local Gear = dofile("gear.lua"); local Combat = dofile("combat.lua"); Combat.bind(Game, Gear); Game.COMBAT = Combat; Game.GEAR = Gear
s = fresh(); s.route.km = 5; s.route.guardians = { [2] = true }; s.range = 5000
local dry, worst = 0, 0
for _ = 1, 3000 do
  local kind = Game.flipCard(s, math.random)
  if s.fight then s.fight = nil; dry = 0 else dry = dry + 1; worst = math.max(worst, dry) end
  s.route.km = 5
end
assert(worst <= Game.DRY_MAX, worst)
local m9 = Game.migrate((function() local o = Game.newState(now); o.save_version = 8; o.dry_flips = nil; return o end)())
assert(m9.save_version == Game.SAVE_VERSION and m9.dry_flips == 0)
print("streak breaker ok (longest dry run " .. worst .. ")")
