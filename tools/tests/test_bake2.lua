-- Salvage, second bakes, nudges, tried combos, battle items. Run from relic.koplugin/:  luajit ../tools/tests/test_bake2.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local B = Game.BOOK
local now = os.time()
local function fresh()
  local s = Game.newState(now - 86400); s.level = 5
  s.barrels = { false, false }
  return s
end

-- 1. book is well formed: sorted keys, unique result keys, tier-2 inputs are real baked items
local keys = {}
for combo, r in pairs(B.recipes) do
  local a, b = combo:match("^(.-)%+(.+)$"); assert(a and a <= b, "unsorted " .. combo)
  assert(not keys[r.key], "duplicate key " .. r.key); keys[r.key] = true
  assert(r.hint and r.minutes and r.effect, combo)
end
for combo, r in pairs(B.recipes) do
  if r.tier == 2 then
    assert(keys[r.from], combo .. " from unknown " .. tostring(r.from))
    assert(combo:find(r.from, 1, true), combo .. " doesn't use " .. r.from)
  end
end
local n = 0; for _ in pairs(B.recipes) do n = n + 1 end
print("recipes: " .. n)

-- 2. salvage: 5 in, 1 rarer out (fewest held, never the input); barrel busy meanwhile
local s = fresh(); s.inv.grain = 12; s.inv.honey = 3; s.inv.salt = 0; s.inv.ink = 1; s.inv.wax = 2; s.inv.filings = 4
assert(not Game.canSalvage(s, "herb"))
assert(Game.startSalvage(s, "grain", now)); assert(s.inv.grain == 7)
assert(Game.barrelStatus(s, 1, now) == "baking")
local label, _, _, msg = Game.collect(s, 1, now + B.salvage.minutes * 60)
assert(label == "Salt" and s.inv.salt == 1 and msg:find("5 Grain into 1 Salt"), tostring(msg))
s.inv.salt = 5
for _ = 1, 50 do assert(Game.salvageOutput(s, "salt") ~= "salt") end
-- 3. tier-2: baked goods go back in, combo by base key, fine input helps fine output
s = fresh(); s.inv.bread_fine = 1; s.inv.honey = 1
assert(Game.isBakedInput("bread_fine") and not Game.isBakedInput("grain") and not Game.isBakedInput("stale"))
local r, combo, known = Game.bakeResult("bread_fine", "honey"); assert(known and combo == "bread+honey" and r.key == "honeyloaf")
assert(Game.startBake(s, "bread_fine", "honey", now, function(n) return 30 end))  -- 30 <= 10+acu+25: fine
assert(s.inv.bread_fine == 0 and s.inv.honey == 0 and s.barrels[1].fine)
local l2, _, new, extra = Game.collect(s, 1, now + 3600, function(n) return 1 end)
assert(new and extra and s.journal["bread+honey"] and s.inv.honeyloaf_fine == 1, l2)
-- two of the same baked item
s = fresh(); s.inv.potion = 1; assert(not Game.canBake(s, "potion", "potion")); s.inv.potion = 2
assert(Game.startBake(s, "potion", "potion", now)); assert(s.inv.potion == 0)
-- 4. misses: tried is recorded, a nudge points at an input with unfound recipes
s = fresh(); s.inv.grain = 1; s.inv.wax = 1
assert(Game.startBake(s, "grain", "wax", now))
local lab, _, nw, nudge = Game.collect(s, 1, now + 3600)
assert(lab == "Stale loaf" and not nw and s.tried["grain+wax"] and nudge, tostring(nudge))
-- no nudge once everything with those inputs is found
for c in pairs(B.recipes) do s.journal[c] = true end
assert(Game.nudge(s, "grain+wax") == nil)
-- 5. battle items: all battle recipes, weakest first; the new potions count and drink
local list = Game.battleItems(); assert(list[1] == "potion", list[1])
s = fresh(); s.inv.potion = 0; s.inv.greater = 1; s.hp = 1
assert(Game.potionCount(s) == 1); local m = Game.drinkPotion(s); assert(m and s.hp == 31 and s.inv.greater == 0, m)
-- 6. every recipe's effect is usable
for c, rr in pairs(B.recipes) do
  local q = fresh(); q.inv[rr.key] = 1; q.hp = 1
  assert(Game.useBaked(q, rr.key, now), c)
end
-- 7. migration to v8 adds tried
local old = Game.newState(now); old.save_version = 7; old.tried = nil
local mm = Game.migrate(old); assert(mm.save_version == Game.SAVE_VERSION and mm.tried)
print("bake2 ok")

-- 8. regional ingredients: forage in a region finds its own; recipes using them exist; hidden until held
local Gear = dofile("gear.lua"); local Combat = dofile("combat.lua"); Combat.bind(Game, Gear); Game.COMBAT = Combat; Game.GEAR = Gear
for region, km in pairs({ [1] = 10, [2] = 100, [3] = 400 }) do
  local want = {}; for _, k in ipairs(Game.regionIngredients(region)) do want[k] = true end
  assert(next(want), "region " .. region .. " has ingredients")
  local q = fresh(); q.route.km = km; q.route.guardians = { [2] = true, [14] = true }; q.range = 3000
  local got = {}
  for _ = 1, 600 do
    local kind = Game.flipCard(q, math.random); if q.fight then q.fight = nil end
    q.route.km = km
  end
  for k in pairs(want) do assert((q.inv[k] or 0) > 0 and q.ing_seen[k], "region " .. region .. " never foraged " .. k) end
  for _, ing in ipairs(B.ingredients) do
    if ing.region and ing.region ~= region then assert((q.inv[ing.key] or 0) == 0, ing.key .. " outside its region") end
  end
end
for _, ing in ipairs(B.ingredients) do
  if ing.region then
    local uses = 0
    for c, r in pairs(B.recipes) do if r.uses == ing.key then uses = uses + 1; assert(c:find(ing.key, 1, true), c) end end
    assert(uses >= 2, ing.key .. " needs recipes")
  end
end
local q = fresh(); assert(#Game.shownIngredients(q) == 8); Game.gainIngredient(q, "apple", 1); assert(#Game.shownIngredients(q) == 9)
-- monster drops carry local ingredients sometimes
q = fresh(); q.route.km = 100; local drops = 0
for _ = 1, 200 do
  q.fight = Combat.newMonster(q, math.random); Combat.win(q, q.fight, math.random)
end
assert((q.inv.beet or 0) + (q.inv.leek or 0) > 20, "monster drops")
print("regional ok")

-- 9. ITEM menu: pick a specific battle item; it takes the turn; unknown or missing items refuse
q = fresh(); q.route.km = 10; q.inv.potion = 2; q.inv.strong = 1; q.inv.honeyloaf = 1; q.hp = 5
local held = Game.heldBattleItems(q)
assert(#held == 2 and held[1].key == "potion" and held[2].key == "strong", #held)
q.fight = Combat.newMonster(q, math.random); q.fight.hp, q.fight.max = 999, 999
local r9 = Combat.act(q, "item:strong", function(n) return n end)
assert(q.inv.strong == 0 and r9:find("Strong potion"), r9)
assert(Combat.act(q, "item:strong", math.random):find("don't have"))
assert(Combat.act(q, "item:honeyloaf", math.random):find("don't have"), "non-battle food can't be used in battle")
print("item menu ok")
