-- TRAIN, Grit/Breaker, Might perks, Kinesthetics. Run from relic.koplugin/:  luajit ../tools/tests/test_train.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local Gear = dofile("gear.lua"); local Combat = dofile("combat.lua")
Combat.bind(Game, Gear); Game.COMBAT = Combat; Game.GEAR = Gear
math.randomseed(11)
local rng = math.random
local DAY = 86400
local t0 = os.time({ year = 2026, month = 10, day = 1, hour = 9 })

local function player(level)
  local s = Game.newState(t0 - 10 * DAY)
  s.level = level
  for k, g in pairs(Game.GROWTH) do s.stats[k] = s.stats[k] + g * (level - 1) end
  s.hp = Game.maxHp(level, s); s.charge = Game.maxCharge(level, s)
  return s
end

-- 1. one slot on day one; a second set the same day is refused
local s = player(1)
assert(Game.trainLeft(s, t0) == 1)
local msg = Game.train(s, "pushups", t0); assert(msg and msg:find("10 pushups"), msg)
assert(s.xp == Game.TRAIN_XP and s.grit == 1 and s.skills.might.xp == Game.MIGHT_XP)
local ok, why = Game.train(s, "squats", t0); assert(not ok and why:find("No training"))
assert(Game.train(s, "burpees", t0 + DAY) == nil, "unknown kinds refused")
-- 2. next day resets; slots grow at 7, 21, 45, 80 total sets and never shrink
local day = t0
local function trainDay()
  day = day + DAY
  local n = 0
  while Game.trainLeft(s, day) > 0 do
    assert(Game.train(s, n % 2 == 0 and "pushups" or "squats", day)); n = n + 1
  end
  return n
end
local seen = {}
for _ = 1, 40 do seen[trainDay()] = true end
assert(seen[1] and seen[2] and seen[3] and seen[4] and seen[5], "slots reach 5")
assert(Game.trainSlots(s) == 5 and Game.nextTrainSlot(s) == nil)
assert(s.training.pushups + s.training.squats + (s.training.dumbbells or 0) == s.training.total)
-- slot opens the same day the threshold is hit
local u = player(1); u.training.total = 6
local d = t0
assert(Game.trainLeft(u, d) == 1)
local m7 = Game.train(u, "squats", d); assert(m7:find("new daily set"), m7)
assert(Game.trainLeft(u, d) == 1, "the new slot is usable today")
-- 3. Grit caps at 10 (15 at Might 10); Kinesthetics +1 per 5 sets
assert(s.grit == 10, "grit cap")
assert(s.stats.kin == 2 + math.floor(s.training.total / Game.KIN_EVERY), "kin growth")
assert(Game.mightRank(s) >= 8, "might rank after " .. s.training.total .. " sets: " .. Game.mightRank(s))
local r10 = player(1); r10.skills.might = { xp = 0, rank = 10, day = "x", today = 0 }; r10.grit = 14
Game.train(r10, "pushups", t0); assert(r10.grit == 15); Game.train(r10, "pushups", t0 + DAY); assert(r10.grit == 15)
-- levels don't grow kin
local lv = player(1); lv.xp = 5000; Game.levelUps(lv); assert(lv.stats.kin == 2)
-- 4. migration to v7
local old = Game.newState(t0); old.save_version = 6; old.stats.kin = nil; old.training = nil; old.grit = nil
local m = Game.migrate(old)
assert(m.save_version == Game.SAVE_VERSION and m.stats.kin == 2 and m.training.total == 0 and m.grit == 0)
-- 5. Breaker: needs 3 Grit, once per fight, spends all, pierces, breaks a wind-up
local p = player(5); p.stats.kin = 0; p.fight = Combat.newGuardian(p, 2); p.fight.rescued = true
p.grit = 2; assert(Combat.act(p, "breaker", rng):find("Not enough Grit"))
p.grit = 10; p.fight.telegraph = true
local hp0 = p.fight.hp
local r = Combat.act(p, "breaker", rng)
assert(p.grit == 0 and p.fight.broke and r:find("wind%-up is broken"), r)
assert(r:find("loses its turn"), "a broken wind-up staggers: " .. r)
assert(hp0 - p.fight.hp >= 20, "breaker hits hard: " .. (hp0 - p.fight.hp))
p.grit = 10; assert(Combat.act(p, "breaker", rng):find("spent"))
-- rank 8: 2 Grit is enough
local p8 = player(5); p8.skills.might = { xp = 0, rank = 8, day = "x", today = 0 }; p8.grit = 2
p8.fight = Combat.newMonster(p8, rng); assert(Combat.canBreak(p8, p8.fight))
-- a full pool (10 Grit, Might 3 after 10 sets) is roughly half the Cliffwarden
local tot, n = 0, 400
for _ = 1, n do
  local b = player(5); b.skills.might = { xp = 0, rank = 3, day = "x", today = 0 }; b.grit = 10
  b.fight = Combat.newGuardian(b, 2); b.fight.rescued = true
  local h = b.fight.hp; Combat.act(b, "breaker", rng)
  tot = tot + (h - (b.fight and b.fight.hp or 0))
end
print(string.format("Breaker, 10 Grit, Might 3, L5: %.0f of %d guardian HP", tot / n, Combat.GUARDIANS[2].hp))
assert(tot / n >= 28 and tot / n <= 55)
-- 6. Might perks: rank 2 +1 attack, rank 4 Second Wind once, rank 6 heavier Ram
local a = player(5); local T = Game.gearTotals(a)
local base = Combat.attackValue(a, T)
a.skills.might = { xp = 0, rank = 2, day = "x", today = 0 }; assert(Combat.attackValue(a, T) == base + 1)
local w = player(3); w.skills.might = { xp = 0, rank = 4, day = "x", today = 0 }
w.fight = Combat.newGuardian(w, 2); w.fight.rescued = true; w.fight.hp, w.fight.max = 9999, 9999
local winds = 0
for _ = 1, 40 do
  if not w.fight then break end
  local out = Combat.act(w, "attack", rng); if out:find("Second Wind") then winds = winds + 1 end
end
assert(winds == 1, "second wind once per fight, got " .. winds)
-- 7. Kinesthetics: dodge, tempo, run chance scale and cap
local k = player(5); T = Game.gearTotals(k)
assert(Combat.kinDodge(k, T) == 1 and Combat.tempoChance(k, T) == 1 and Combat.runChance(k, T) == 77)
k.stats.kin = 100; assert(Combat.kinDodge(k, T) == 20 and Combat.tempoChance(k, T) == 15 and Combat.runChance(k, T) == 95)
k.gear.equipped.feet = { slot = "feet", name = "Treads", rarity = 1, tier = 1, stats = { kin = 6 }, affixes = {} }
k.stats.kin = 2; T = Game.gearTotals(k); assert(Combat.kinDodge(k, T) == 4, "gear kin counts")
-- tempo skips the enemy turn
local q = player(5); q.stats.kin = 30; q.fight = Combat.newMonster(q, rng); q.fight.hp, q.fight.max = 9999, 9999
local skips = 0
for _ = 1, 300 do local o = Combat.act(q, "attack", rng); if o:find("Quick feet") then skips = skips + 1 end; q.hp = Game.maxHp(q.level, q) end
assert(skips > 20 and skips < 80, "tempo ~15%: " .. skips)
-- gear can roll kin
local kin_seen = false
for _ = 1, 500 do local it = Gear.roll(rng, 1); if it.stats.kin then kin_seen = true; break end end
assert(kin_seen and Gear.summary({ stats = { kin = 2 }, affixes = {} }):find("KIN"))
-- tempo never follows a stagger (Ram / Breaker) with a second free turn
local z = player(5); z.stats.kin = 1000; z.abilities = { "ram", "blink" }
for _ = 1, 50 do
  z.charge = 99; z.hp = Game.maxHp(z.level, z)
  z.fight = Combat.newMonster(z, rng); z.fight.hp, z.fight.max = 9999, 9999
  local o = Combat.act(z, "ability:ram", rng)
  assert(not o:find("Quick feet"), o)
end
-- Might can't be earned from quests
local mq = player(1); local qq = Game.addQuest(mq, "anything", "standard"); qq.tags = { "might" }
Game.completeQuest(mq, qq.id, t0); assert(not mq.skills.might, "might is train-only")
print("train ok")

-- dumbbells (2026-10-08): same slot, same rewards; old saves without the field
do
  local d0 = player(1)
  d0.training.dumbbells = nil
  local m = Game.train(d0, "dumbbells", t0); assert(m and m:find("10 dumbbell reps"), m)
  assert(d0.training.dumbbells == 1 and d0.training.total == 1)
  print("dumbbells ok")
end
