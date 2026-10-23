-- 2026-10-08 difficulty pass: wind-ups on normal enemies, Elites, Integrity on a loss; MY ROAD map pick.
-- Run from relic.koplugin/:  luajit ../tools/tests/test_difficulty.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local Gear = dofile("gear.lua"); local Combat = dofile("combat.lua")
Combat.bind(Game, Gear); Game.COMBAT = Combat; Game.GEAR = Gear
math.randomseed(3)
local rng = math.random
local function player(level, km)
  local s = Game.newState(os.time() - 86400)
  s.level = level
  for k, g in pairs(Game.GROWTH) do s.stats[k] = s.stats[k] + g * (level - 1) end
  s.hp = Game.maxHp(level, s); s.charge = Game.maxCharge(level, s)
  s.route.km = km
  return s
end
local fixed = function(n) return n end   -- no crits, no dodges, no tempo

-- Kent stays the tutorial: no wind-ups, no Elites
for _ = 1, 300 do
  local m = Combat.newMonster(player(4, 20), rng)
  assert(not m.windup and not m.elite and not m.name:find("^Elite"), "Kent changed")
end
-- past Kent: about 12% Elites, all with wind-ups except fuse/burrow
local elites, n = 0, 2000
for _ = 1, n do
  local m = Combat.newMonster(player(9, 100), rng)
  if m.elite then elites = elites + 1; assert(m.name:find("^Elite ")) end
  assert((m.windup == true) == (m.quirk ~= "fuse" and m.quirk ~= "burrow"), "windup flag " .. m.quirk)
end
assert(elites / n > 0.08 and elites / n < 0.16, "elite rate " .. elites / n)

-- a normal enemy winds up on its 3rd turn, hits 1.8x on the 4th unless answered
local function dummy(km)
  local p = player(12, km or 100); p.abilities = { "ram", "blink" }
  p.fight = Combat.newMonster(p, function(k) return k == 100 and 100 or 1 end) -- never Elite
  local f = p.fight; f.quirk, f.windup, f.hp, f.max, f.def = "corrode", true, 900, 900, 0
  return p, f
end
local p, f = dummy()
local r
for _ = 1, 3 do r = Combat.act(p, "attack", fixed) end
assert(f.telegraph and r:find("gathers itself"), r)
p.hp = 999; r = Combat.act(p, "attack", fixed)
assert(r:find("heavy blow!") and not f.telegraph, r)
p, f = dummy()
for _ = 1, 3 do Combat.act(p, "attack", fixed) end
r = Combat.act(p, "ability:ram", fixed)
assert(r:find("wind%-up is broken") and not f.telegraph, r)

-- Elites: tougher than a normal roll at the same spot, double XP and dust, always drop Uncommon+
local p2 = player(9, 100)
local e
repeat e = Combat.newMonster(p2, rng) until e.elite
p2.fight = e; e.hp = 1
local xp0, dust0, bag0 = p2.xp, p2.inv.dust or 0, #p2.gear.bag
r = Combat.act(p2, "attack", rng)
assert(r:find("Defeated Elite") and r:find("Loot:"), r)
assert(#p2.gear.bag == bag0 + 1 and p2.gear.bag[#p2.gear.bag].rarity >= 2, "elite loot")
assert((p2.inv.dust - dust0) >= 4, "elite dust")

-- a loss costs Integrity
local p3 = player(9, 100); p3.integrity = 100
p3.fight = Combat.newMonster(p3, rng); p3.fight.hp, p3.fight.atk = 999, 999; p3.hp = 1
r = Combat.act(p3, "attack", rng)
assert(not p3.fight and p3.hp == 1 and p3.integrity == 100 - Combat.LOSS_INTEGRITY and r:find("Integrity"), r)
p3.integrity = 5; p3.fight = Combat.newMonster(p3, rng); p3.fight.hp, p3.fight.atk = 999, 999; p3.hp = 1
Combat.act(p3, "attack", rng); assert(p3.integrity == 0)

-- guardians keep their old multipliers
local g = Combat.newGuardian(player(16, 316), 14)
local h1 = Combat.monsterStats(g.lv, 1, 1, 316, true)
assert(h1 < Combat.monsterStats(g.lv, 1, 1, 316), "guardian uses its own multipliers")

-- MY ROAD: always some road ahead; the last map at the end
local js = Game.ROUTE.journeys
assert(js and #js >= 8)
for km = 0, 1862, 7 do
  local j = Game.journeyFor(km)
  assert(j.km1 >= km, "journey ends behind the player at " .. km)
  if km < 1600 then assert(j.km1 >= km * 1.1 + 5, "no road ahead at " .. km) end
end
assert(Game.journeyFor(1862) == js[#js])
for _, j in ipairs(js) do
  assert(io.open(j.image), "missing " .. j.image)
  assert(#j.path > 10 and #j.towns >= 2)
  local x, y = Game.mapPoint(j.path, j.km1 / 2); assert(x >= 0 and x <= 720 and y >= 0 and y <= 470)
end
print("difficulty ok")
