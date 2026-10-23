-- Region 2-3 rosters, new quirks and guardians. Run from relic.koplugin/:  luajit ../tools/tests/test_regions.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local Gear = dofile("gear.lua"); local Combat = dofile("combat.lua")
Combat.bind(Game, Gear); Game.COMBAT = Combat; Game.GEAR = Gear
math.randomseed(11)
local rng = math.random

-- gear: number of slots filled with Common/Uncommon pieces of the region's tier (2026-10-05:
-- balance now assumes gear; Mike had 7 pieces, mostly Kent's, at stage 4)
local GEAR_SLOTS = { "chest", "gloves", "pants", "feet", "ring1", "ring2", "head", "main", "off", "cloak" }
local function player(level, km, gear)
  local s = Game.newState(os.time() - 86400)
  s.level = level
  for k, g in pairs(Game.GROWTH) do s.stats[k] = s.stats[k] + g * (level - 1) end
  s.route.km = km or 0
  for i = 1, (gear or 0) do
    local slot = GEAR_SLOTS[i]
    local it = Gear.roll(rng, math.max(1, Combat.regionTier(s) - 1), { slot = slot == "ring2" and "ring1" or slot })
    it.rarity = math.min(it.rarity, 2)
    local x = Game.addItem(s, it); Game.equip(s, x.id, slot)
  end
  s.hp = Game.maxHp(level, s); s.charge = Game.maxCharge(level, s)
  return s
end
local KM = { [1] = 10, [2] = 100, [3] = 400, [4] = 600 }
local function expLevel(km) return math.floor(Combat.levelAt(km) + 0.5) end

-- 1. every sprite named in a roster or guardian exists
for _, roster in pairs(Combat.ROSTER) do
  for _, m in ipairs(roster) do
    assert(io.open("sprites/" .. m.sprite .. ".png"), "missing sprite " .. m.sprite)
    assert(Combat.QUIRKS[m.quirk], "unknown quirk " .. m.quirk)
  end
end
for n, g in pairs(Combat.GUARDIANS) do
  assert(io.open("sprites/" .. g.sprite .. ".png"), "missing sprite " .. g.sprite)
  assert(Game.GUARDIANS[n], "guardian " .. n .. " must also block the route")
  assert(not g.quirk or Combat.QUIRKS[g.quirk])
end

-- 2. regions draw from their own roster; region 4 falls back to region 3
local function names(t) local r = {} for _, m in ipairs(t) do r[m.name] = true end return r end
for tier, km in pairs(KM) do
  local want = names(Combat.ROSTER[math.min(tier, 3)])
  for _ = 1, 50 do
    local p = player(5, km); assert(Combat.regionTier(p) == tier)
    local f = Combat.newMonster(p, rng); assert(want[(f.name:gsub("^Elite ", ""))], tier .. " drew " .. f.name)
  end
end

-- 3. normal fights past Kent are a real threat (2026-10-08): a gearless player at the expected
-- level loses often swinging ATTACK alone, and wins most fights by answering wind-ups and
-- drinking when low. (Tuned against Mike's real gear in the combat.lua comment.)
local function normals(tier, level, n, km, smart)
  local taps, wins, lost = 0, 0, 0
  for _ = 1, n do
    local p = player(level, km or KM[tier], 7); p.abilities = { "blink", "ram" }
    p.fight = Combat.newMonster(p, rng)
    local hp, t = p.hp, 0
    while p.fight and t < 40 do
      local f = p.fight
      if smart and f.telegraph and p.charge >= 3 then Combat.act(p, "ability:ram", rng)
      elseif smart and p.hp < Game.maxHp(p.level, p) * 0.35 and Game.potionCount(p) > 0 then Combat.act(p, "item", rng)
      else Combat.act(p, "attack", rng) end
      t = t + 1
    end
    taps = taps + t; lost = lost + (hp - p.hp); if not p.fight and p.hp > 1 then wins = wins + 1 end
  end
  print(string.format("Region %d normal @L%d %s: %.1f taps, %.1f HP lost of %d, win %d%%", tier, level,
    smart and "answers" or "attack-only", taps / n, lost / n, Game.maxHp(level, player(level)), math.floor(wins * 100 / n)))
  return taps / n, wins / n
end
for _, c in ipairs({ { 2, KM[2] }, { 3, KM[3] }, { 2, 300 } }) do
  local tA, wA = normals(c[1], expLevel(c[2]), 400, c[2])
  local tB, wB = normals(c[1], expLevel(c[2]), 400, c[2], true)
  assert(tA >= 4, "past Kent a fight should take a while")
  assert(wB > wA and wB > 0.6, "answers should win most fights, even without gear")
end
-- Kent is unchanged: Dover's guardian keeps its design stats at Dover (km 33)
do
  local p = player(5, 33); local g = Combat.newGuardian(p, 2); local d = Combat.GUARDIANS[2]
  assert(g.lv == d.lv and g.max == d.hp and g.atk == d.atk and g.def == d.def, "Cliffwarden changed at Dover")
  for _ = 1, 200 do local m = Combat.newMonster(player(4, 20), rng); assert(m.lv >= 2 and m.lv <= 4, "Kent level " .. m.lv) end
end

-- 4. guardians: tactical, beatable with answers at the expected level, worse attack-only
-- guardians stand at the end of their stage: Drillbit at km 316, Talus at km 548
local GKM = { [14] = 316, [23] = 548 }
local function bossRun(n, level, tier, useAbilities)
  local p = player(level, GKM[n] or KM[tier], 7); p.abilities = { "blink", "ram" }
  p.fight = Combat.newGuardian(p, n)
  local t = 0
  while p.fight and t < 60 do
    local f = p.fight
    if useAbilities and f.telegraph and p.charge >= 3 then Combat.act(p, "ability:ram", rng)
    elseif useAbilities and f.telegraph and p.charge >= 2 then Combat.act(p, "ability:blink", rng)
    elseif p.hp < Game.maxHp(p.level, p) * 0.35 and Game.potionCount(p) > 0 then Combat.act(p, "item", rng)
    else Combat.act(p, "attack", rng) end
    t = t + 1
  end
  return p.route.guardians[n] == true, t
end
local function bossStats(n, level, tier)
  local wA, wB, tt = 0, 0, 0
  for _ = 1, 300 do
    if bossRun(n, level, tier, false) then wA = wA + 1 end
    local b, t = bossRun(n, level, tier, true); if b then wB = wB + 1; tt = tt + t end
  end
  print(string.format("%s @L%d: attack-only %d%%, with answers %d%% (%.1f taps)", Combat.GUARDIANS[n].name, level,
    math.floor(wA * 100 / 300), math.floor(wB * 100 / 300), tt / math.max(1, wB)))
  return wA / 300, wB / 300
end
local L14, L23 = expLevel(GKM[14]), expLevel(GKM[23])
local a, b = bossStats(14, L14, 2); assert(b > a and b > 0.6, "Drillbit @L" .. L14)
local a2, b2 = bossStats(14, L14 - 3, 2); assert(b2 < b, "under-levelled should be harder")
a, b = bossStats(23, L23, 3); assert(b > a and b > 0.6, "Talus @L" .. L23)
bossStats(23, L23 - 2, 3)

-- 5. quirk mechanics
local function fightQ(quirk, level)
  local p = player(level or 6, KM[2]); p.abilities = { "ram", "hand" }
  p.fight = Combat.newMonster(p, rng); local f = p.fight
  f.quirk, f.hp, f.max, f.def = quirk, 500, 500, 0
  return p, f
end
-- mend heals at the start of its turn
local p, f = fightQ("mend"); f.hp = 400
local r = Combat.act(p, "attack", rng); assert(r:find("repairs itself"), r)
-- burrow: digs in on its 2nd turn; plain attack misses; Ram drags it out
p, f = fightQ("burrow")
Combat.act(p, "attack", rng); r = Combat.act(p, "attack", rng)
assert(f.burrowed and r:find("digs into"), r)
local hp0 = f.hp; r = Combat.act(p, "attack", function(n) return n end)
assert(r:find("hits dirt") and f.hp == hp0 and r:find("erupts"), r); assert(not f.burrowed)
p, f = fightQ("burrow"); f.burrowed = true; p.charge = 20
hp0 = f.hp; r = Combat.act(p, "ability:ram", rng); assert(f.hp < hp0 and not f.burrowed and r:find("drag it out"), r)
p, f = fightQ("burrow"); f.burrowed = true; p.charge = 20
hp0 = f.hp; Combat.act(p, "ability:hand", rng); assert(f.hp < hp0, "Relic Hand reaches it")
p, f = fightQ("burrow"); f.burrowed = true; p.grit = 5
hp0 = f.hp; r = Combat.act(p, "breaker", rng); assert(f.hp < hp0 and not f.burrowed, r)
-- fuse: winds up on turn 3, bursts on turn 4 unless answered
p, f = fightQ("fuse", 12)
-- fixed rolls: a free turn (KIN tempo) or crit would throw off the turn count this checks
for _ = 1, 3 do r = Combat.act(p, "attack", function(n) return n end) end
assert(f.telegraph and r:find("pressure builds"), r)
p.charge = 20; r = Combat.act(p, "ability:ram", rng); assert(r:find("wind%-up is broken") and not f.telegraph, r)
p, f = fightQ("fuse", 12); p.hp = 999
for _ = 1, 4 do r = Combat.act(p, "attack", function(n) return n end) end
assert(r:find("bursts!"), r)
-- siphon drains Charge
p, f = fightQ("siphon"); p.charge = 5
Combat.act(p, "attack", function(n) return n end); assert(p.charge == 4, p.charge)
p.charge = 0; Combat.act(p, "attack", function(n) return n end); assert(p.charge == 0)
-- guardians carry their quirk; Appraise names it
p = player(9, KM[2]); p.abilities = { "appraise", "ram" }; p.fight = Combat.newGuardian(p, 14)
assert(p.fight.quirk == "mend"); r = Combat.act(p, "ability:appraise", rng); assert(r:find("repairs itself"), r)
assert(Combat.quirkText(p.fight):find("repairs"))

-- 6. the route blocks at Corbeny and Langres until each guardian is beaten
p = player(9, 0); p.route.guardians[2] = true; p.range = 2000
p.unlocks = p.unlocks or {}
local orig = Game.unlocked; Game.unlocked = function() return true end
local met = {}
for _ = 1, 2000 do
  local k = Game.flipCard(p, rng)
  if p.fight and p.fight.boss then met[#met + 1] = p.fight.boss; p.route.guardians[p.fight.boss] = true; p.fight = nil
  elseif p.fight then p.fight = nil end
  if p.route.km >= 560 then break end
end
Game.unlocked = orig
assert(met[1] == 14 and met[2] == 23, "met " .. table.concat(met, ","))
print("regions ok")
