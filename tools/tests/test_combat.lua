-- Combat, gear and affix tests. Run from relic.koplugin/:  luajit ../tools/tests/test_combat.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local Gear = dofile("gear.lua"); local Combat = dofile("combat.lua")
Combat.bind(Game, Gear); Game.COMBAT = Combat; Game.GEAR = Gear
math.randomseed(7)
local rng = math.random

local function player(level)
  local s = Game.newState(os.time() - 86400)
  s.level = level
  for k, g in pairs(Game.GROWTH) do s.stats[k] = s.stats[k] + g * (level - 1) end
  s.hp = Game.maxHp(level, s); s.charge = Game.maxCharge(level, s)
  return s
end

-- 1. gear rolls are well formed for every slot and rarity
for i = 1, 3000 do
  local it = Gear.roll(rng, 1 + (i % 9))
  assert(it.slot and it.name and Gear.RARITY[it.rarity] and next(it.stats), "bad item")
  if it.unique then assert(Gear.UNIQUE[it.unique].slots[it.slot], "unique on wrong slot " .. it.unique .. " " .. it.slot) end
  assert(#Gear.describe(it) >= 3)
end
local boss = Gear.roll(rng, 1, { min_rarity = 3 }); assert(boss.rarity >= 3)

-- 2. equip / unequip, rings in either slot, HP follows gear
local s = player(4)
local ring = Game.addItem(s, { slot = "ring1", name = "t", rarity = 1, tier = 1, stats = { res = 10 }, affixes = {} })
local hp0 = Game.maxHp(s.level, s)
assert(Game.equip(s, ring.id, "ring2") and Game.maxHp(s.level, s) == hp0 + 5)
assert(not Game.equip(s, 999, "head"))
assert(Game.unequip(s, "ring2") and #s.gear.bag == 1 and Game.maxHp(s.level, s) == hp0)
local helm = Game.addItem(s, { slot = "head", name = "h", rarity = 1, tier = 1, stats = { def = 1 }, affixes = {} })
assert(not Game.equip(s, helm.id, "feet"), "wrong slot must fail")

-- 3. normal Kent fights at level 4 with starter gear: quick (about 3-4 taps), survivable
local taps, hplost, wins, n = 0, 0, 0, 400
for _ = 1, n do
  local p = player(4); p.abilities = { "blink", "ram" }
  p.fight = Combat.newMonster(p, rng)
  local hp = p.hp; local t = 0
  while p.fight and t < 30 do Combat.act(p, "attack", rng); t = t + 1 end
  taps = taps + t; hplost = hplost + (hp - p.hp); if not p.fight and p.hp > 1 then wins = wins + 1 end
end
print(string.format("Kent normal @L4: %.1f taps, %.1f HP lost of %d, win %d%%", taps / n, hplost / n, Game.maxHp(4, player(4)), math.floor(wins * 100 / n)))
assert(taps / n >= 2.5 and taps / n <= 5.5, "normal fights should be quick")
assert(wins / n > 0.9, "normal fights should be winnable")

-- 4. Dover guardian at level 5: tactical; attack-only is risky, answering the wind-up helps
local function bossRun(level, useAbilities)
  local p = player(level); p.abilities = { "blink", "ram" }
  p.fight = Combat.newGuardian(p, 2)
  local t = 0
  while p.fight and t < 40 do
    local f = p.fight
    if useAbilities and f.telegraph and p.charge >= 3 then Combat.act(p, "ability:ram", rng)
    elseif useAbilities and f.telegraph and p.charge >= 2 then Combat.act(p, "ability:blink", rng)
    elseif p.hp < Game.maxHp(p.level, p) * 0.35 and Game.potionCount(p) > 0 then Combat.act(p, "item", rng)
    else Combat.act(p, "attack", rng) end
    t = t + 1
  end
  return p.route.guardians[2] == true, t
end
local wA, wB, tt = 0, 0, 0
for _ = 1, 300 do
  local a = bossRun(5, false); if a then wA = wA + 1 end
  local b, t = bossRun(5, true); if b then wB = wB + 1; tt = tt + t end
end
print(string.format("Cliffwarden @L5: attack-only %d%%, with answers %d%% (%.1f taps)", math.floor(wA * 100 / 300), math.floor(wB * 100 / 300), tt / math.max(1, wB)))
assert(wB > wA, "answering the wind-up should help")
assert(wB / 300 > 0.5, "boss should be beatable with answers at level 5")

-- 5. RESOLVE only when 3+ levels above, never on bosses
local p = player(8); p.fight = Combat.newMonster(p, rng); p.fight.lv = 3
assert(Combat.canResolve(p, p.fight)); local msg = Combat.act(p, "resolve", rng); assert(not p.fight and msg:find("Defeated"))
p.fight = Combat.newGuardian(p, 2); assert(not Combat.canResolve(p, p.fight))

-- 6. affix hooks fire
local function fightWith(unique, aff, kind)
  local q = player(4)
  q.gear.equipped.main = { slot = "main", name = "x", rarity = 4, tier = 1, kind = kind or "crush", stats = { atk = 2 }, affixes = aff or {}, unique = unique }
  q.fight = Combat.newMonster(q, function(n) return 1 end); q.fight.hp, q.fight.max = 999, 999; q.fight.quirk = "corrode"
  return q
end
local q = fightWith("hoarfrost"); Combat.act(q, "attack", rng); assert(q.fight.frost == 1, "hoarfrost applies then ticks")
q = fightWith("venom"); Combat.act(q, "attack", rng); Combat.act(q, "attack", rng); assert(q.fight.venom == 2)
q = fightWith("tracers"); Combat.act(q, "attack", rng); assert(q.fight.burn == 1)
q = fightWith("ink"); for _ = 1, 8 do Combat.act(q, "attack", rng) end; assert(q.fight.ink == 5, "ink caps at 5")
q = fightWith(nil, { { k = "thorns", v = 50 } }); local before = q.fight.hp; Combat.act(q, "attack", rng); assert(q.fight.hp < before)
q = fightWith("retribution"); local l = Combat.act(q, "attack", rng); assert(l:find("back"), l)
q = fightWith("archive"); assert(q.fight.revealed)
q = fightWith("servitude"); q.fight.hp = 1; Combat.act(q, "attack", rng); assert(q.thralls == 1)
q = fightWith(nil, { { k = "lifesteal", v = 100 } }); q.hp = 5; Combat.act(q, "attack", rng); assert(q.hp > 5 - 20)
-- 7. abilities: Ram displaces (breaks a wind-up), Blink dodges, Appraise reveals, charge is spent
q = player(5); q.abilities = { "ram", "blink" }; q.fight = Combat.newGuardian(q, 2); q.fight.rescued = true
q.fight.telegraph = true; local c0 = q.charge; local r = Combat.act(q, "ability:ram", rng)
assert(q.charge == c0 - 3 and r:find("wind%-up is broken"), r)
q.fight.telegraph = true; local hp1 = q.hp; r = Combat.act(q, "ability:blink", rng); assert(q.hp == hp1 and r:find("empty air"), r)
assert(Combat.act(q, "ability:vow", rng):find("don't have"))
q = player(4); q.abilities = { "appraise", "hand" }; q.fight = Combat.newMonster(q, rng); Combat.act(q, "ability:appraise", rng)
assert(q.fight == nil or q.fight.appraised)
-- 8. losing: HP floor 1, fight ends, nothing else lost
q = player(1); q.fight = Combat.newGuardian(q, 2); q.fight.rescued = true; q.inv.dust = 5
for _ = 1, 60 do if not q.fight then break end; Combat.act(q, "attack", rng) end
assert(q.hp >= 1 and q.inv.dust >= 5)
-- 9. migration to v6 and flipCard creates Combat fights
local old = Game.newState(os.time()); old.save_version = 5; old.gear = nil; old.fight = { name = "legacy" }
local m = Game.migrate(old); assert(m.save_version == Game.SAVE_VERSION and m.gear and m.gear.bag and m.fight == nil)
q = player(4); q.range = 50; q.route.guardians[2] = true
local got
for _ = 1, 50 do local k = Game.flipCard(q, rng); if k == "monster" then got = q.fight break end end
assert(got and got.quirk and got.tier == 1, "monster from Combat")
print("ok")

-- 10. soft sets: one Affliction piece is modest, three together are much stronger
local function avgDamage(items, n)
  local total = 0
  for _ = 1, n do
    local q = player(5)
    q.gear.equipped = {}
    for slot, it in pairs(items) do q.gear.equipped[slot] = it end
    q.fight = Combat.newMonster(q, rng); q.fight.hp, q.fight.max, q.fight.quirk = 9999, 9999, "armored"
    local h0 = q.fight.hp
    for _ = 1, 6 do q.hp = Game.maxHp(q.level, q); Combat.act(q, "attack", rng) end
    total = total + (h0 - q.fight.hp)
  end
  return total / n
end
local w = { slot = "main", name = "w", rarity = 4, tier = 1, kind = "slash", stats = { atk = 2 }, affixes = {}, unique = "venom" }
local g1 = { slot = "gloves", name = "g", rarity = 3, tier = 1, stats = {}, affixes = { { k = "exploit", v = 2 } } }
local r1 = { slot = "ring1", name = "r", rarity = 3, tier = 1, stats = {}, affixes = { { k = "twin", v = 20 }, { k = "stack2", v = 1 } } }
local base = avgDamage({ main = { slot = "main", name = "p", rarity = 1, tier = 1, kind = "slash", stats = { atk = 2 }, affixes = {} } }, 300)
local one = avgDamage({ main = w }, 300)
local three = avgDamage({ main = w, gloves = g1, ring1 = r1 }, 300)
print(string.format("6 attacks: plain %.0f, venom alone %.0f, venom+exploit+twin/stack %.0f", base, one, three))
assert(three > one * 1.3, "soft set should compound")
-- set bonuses switch on at 2 and 4 pieces
local q = player(5)
for _, slot in ipairs({ "ring1", "amulet", "head", "pants" }) do q.gear.equipped[slot] = { slot = slot, name = "s", rarity = 4, tier = 1, stats = {}, affixes = {}, set = "retribution" } end
local T = Game.gearTotals(q); assert(T.sets.retribution == 4 and T.aff.thorns == 10 and T.aff.lifesteal == 10 and T.uniq.sublime)
q.gear.equipped.pants = nil; T = Game.gearTotals(q); assert(T.aff.thorns == 10 and not T.aff.lifesteal)
-- riposte: dodge + counter answers
q = player(5); q.gear.equipped.feet = { slot = "feet", name = "f", rarity = 3, tier = 1, stats = {}, affixes = { { k = "dodge", v = 40 }, { k = "counter", v = 80 } } }
q.fight = Combat.newMonster(q, rng); q.fight.hp = 9999; local answered = false
for _ = 1, 30 do if Combat.act(q, "attack", rng):find("You answer") then answered = true end end
assert(answered, "counter should fire after dodges")
-- gear rolls carry styles and sets
local sets, styled = 0, 0
for _ = 1, 2000 do local it = Gear.roll(rng, 2, { min_rarity = 4 }); if it.set then sets = sets + 1 end; if #Gear.styles(it) > 0 then styled = styled + 1 end end
assert(sets > 400 and sets < 1200 and styled > 1000, sets .. " " .. styled)
print("soft sets ok")
-- 11. a Ram that knocks the guardian into phase 2 still breaks the wind-up that turn
do
  local q = player(5); q.abilities = { "ram", "blink" }; q.fight = Combat.newGuardian(q, 2); q.fight.rescued = true
  q.fight.hp = q.fight.max / 2 + 5; q.fight.telegraph = true
  local hp = q.hp; local r = Combat.act(q, "ability:ram", function(n) return n end)
  assert(r:find("wind%-up is broken"), r); assert(q.hp == hp); assert(q.fight.braced)
  print("phase-2 ram ok")
end
-- 12. review fixes
do
  -- thorns kill a frenzied enemy: it must not attack again, and a win never leaves HP below 1
  local q = player(4); q.gear.equipped.ring1 = { slot = "ring1", name = "r", rarity = 3, tier = 1, stats = {}, affixes = { { k = "retaliate", v = 50 } } }
  q.fight = Combat.newMonster(q, rng); q.fight.quirk = "frenzy"; q.fight.hp = 30; q.fight.max = 100; q.fight.def = 99; q.hp = 5
  local r = Combat.act(q, "attack", rng)
  assert(not r:find("snaps again"), r); assert(q.hp >= 1)
  -- sublime doubles lifesteal on your next hit
  q = player(4); q.gear.equipped.amulet = { slot = "amulet", name = "a", rarity = 4, tier = 1, stats = {}, affixes = { { k = "lifesteal", v = 20 } }, unique = "sublime" }
  q.fight = Combat.newMonster(q, rng); q.fight.hp, q.fight.max = 999, 999
  Combat.act(q, "attack", rng)               -- enemy hurts you -> sublime armed
  local f = q.fight; assert((f.sublime_until or -1) >= f.turn, "sublime armed for your next turn")
  -- equip clamps Charge
  q = player(4)
  local am = Game.addItem(q, { slot = "amulet", name = "big", rarity = 1, tier = 1, stats = { charge = 20 }, affixes = {} })
  assert(Game.equip(q, am.id, "amulet")); q.charge = Game.maxCharge(q.level, q)
  local am2 = Game.addItem(q, { slot = "amulet", name = "small", rarity = 1, tier = 1, stats = { foc = 1 }, affixes = {} })
  assert(Game.equip(q, am2.id, "amulet")); assert(q.charge <= Game.maxCharge(q.level, q))
  -- pack cap salvages the weakest
  q = player(4); q.inv.dust = 0
  for i = 1, Game.BAG_MAX + 5 do Game.addItem(q, Gear.roll(rng, 1)) end
  assert(#q.gear.bag == Game.BAG_MAX and q.inv.dust >= 5)
  -- two rings of one set count once
  q = player(4)
  q.gear.equipped.ring1 = { slot = "ring1", name = "a", rarity = 4, tier = 1, stats = {}, affixes = {}, set = "retribution" }
  q.gear.equipped.ring2 = { slot = "ring2", name = "b", rarity = 4, tier = 1, stats = {}, affixes = {}, set = "retribution" }
  assert(Game.gearTotals(q).sets.retribution == 1)
  print("review fixes ok")
end
