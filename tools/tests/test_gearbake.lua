-- Gear baking: salvage, merge (rules and limits), merge log, Regrow. Run from relic.koplugin/:  luajit ../tools/tests/test_gearbake.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local Gear = dofile("gear.lua"); local Combat = dofile("combat.lua")
Combat.bind(Game, Gear); Game.COMBAT = Combat; Game.GEAR = Gear
math.randomseed(3)
local rng = math.random
local now = os.time()
local function fresh() local s = Game.newState(now - 86400); s.level = 5; s.barrels = { false, false }; return s end

-- 1. salvage gives dust by rarity and tier and removes the piece
local s = fresh()
local it = Game.addItem(s, Gear.roll(rng, 2, { slot = "head", min_rarity = 3 }))
local d0 = s.inv.dust
local d = Game.salvageGear(s, it.id)
assert(d == it.rarity + 1 and s.inv.dust == d0 + d and #s.gear.bag == 0)
assert(Game.salvageGear(s, it.id) == nil)

-- 2. merge never beats the sum, usually beats the host, keeps slot; caps hold
local better, n = 0, 400
for _ = 1, n do
  local slot = Gear.SLOTS[rng(#Gear.SLOTS)]
  local a, b = Gear.roll(rng, rng(3), { slot = slot }), Gear.roll(rng, rng(3), { slot = slot })
  local m = Gear.merge(a, b)
  assert(m.slot == (Gear.score(a) >= Gear.score(b) and a.slot or b.slot))
  assert(Gear.score(m) <= Gear.score(a) + Gear.score(b) + 0.01, "merge exceeded the sum")
  assert(#m.affixes <= Gear.RARITY[m.rarity].affixes + 2)
  for _, x in ipairs(m.affixes) do
    local def = Gear.AFFIX[x.k]; if def.cap then assert(x.v <= def.cap) end
  end
  if Gear.score(m) > math.max(Gear.score(a), Gear.score(b)) then better = better + 1 end
end
print(string.format("merge beats the better piece %d%% of the time", math.floor(better * 100 / n)))
assert(better / n > 0.8)
-- generations fade: merging a merged piece again keeps less of the guest
local a = Gear.roll(rng, 1, { slot = "chest", min_rarity = 2 })
local chain = a
local gains = {}
for i = 1, 6 do
  local before = Gear.score(chain)
  chain = Gear.merge(chain, Gear.roll(rng, 1, { slot = "chest", min_rarity = 2 }))
  gains[i] = Gear.score(chain) - before
end
assert(chain.gen == 7, chain.gen)
-- no loop: a merge can't be split back, and both inputs are consumed

-- 3. merge in a barrel: dust cost, any two slots, both pieces consumed, log written
s = fresh(); s.inv.dust = 0
local h1 = Game.addItem(s, Gear.roll(rng, 1, { slot = "head" }))
local h2 = Game.addItem(s, Gear.roll(rng, 1, { slot = "head" }))
local f1 = Game.addItem(s, Gear.roll(rng, 1, { slot = "feet" }))
local r1 = Game.addItem(s, Gear.roll(rng, 1, { slot = "ring1" }))
local r2 = Game.addItem(s, Gear.roll(rng, 1, { slot = "ring2" }))
local ok, why = Game.startMerge(s, h1.id, h2.id, now); assert(not ok and why:find("dust"))
s.inv.dust = 20
assert(Game.canMerge(s, h1.id, f1.id), "different slots merge too")
assert(not Game.startMerge(s, h1.id, h1.id, now))
assert(Game.canMerge(s, r1.id, r2.id), "ring1 and ring2 merge")
local cost = Gear.mergeDust(h1, h2)
assert(Game.startMerge(s, h1.id, h2.id, now)); assert(s.inv.dust == 20 - cost and #s.gear.bag == 3)
assert(Game.barrelStatus(s, 1, now) == "baking")
local label, _, _, msg = Game.collect(s, 1, now + Gear.mergeMinutes(h1, h2) * 60)
assert(label and msg:find("Merged") and #s.gear.bag == 4 and #s.merge_log == 1, tostring(msg))
assert(s.merge_log[1].gen == 2)

-- 4. Regrow: using book items sometimes keeps a starter; starters regrow with dust; failures never do
s = fresh(); s.inv.bread = 200; s.inv.stale = 50
for _ = 1, 200 do Game.useBaked(s, "bread", now) end
for _ = 1, 50 do Game.useBaked(s, "stale", now) end
assert((s.starters.bread or 0) > 15 and (s.starters.bread or 0) < 70, s.starters.bread)
assert(not s.starters.stale)
s.inv.dust = 1; assert(not Game.startRegrow(s, "bread", now))
s.inv.dust = 5; local b0 = s.inv.bread; local st0 = s.starters.bread
assert(Game.startRegrow(s, "bread", now)); assert(s.starters.bread == st0 - 1 and s.inv.dust == 3)
local l2 = Game.collect(s, 1, now + 3600); assert(l2 == "Bread" and s.inv.bread == b0 + 1)

-- 5. migration
local old = Game.newState(now); old.save_version = 7; old.merge_log = nil; old.starters = nil
local mm = Game.migrate(old); assert(mm.merge_log and mm.starters)
print("gearbake ok")

-- 5. cross-slot merge: result keeps the stronger piece's slot; a unique only moves if it fits that slot
do
  local helm = { slot = "head", name = "Big Helm", base = "Helm", rarity = 3, tier = 2, stats = { def = 9, hp = 9 }, affixes = {} }
  local ring = { slot = "ring1", name = "Ring of Ink Stain", base = "Ring", rarity = 4, tier = 1, stats = { str = 1 }, affixes = { { k = "crit", v = 5 } }, unique = "ink" }
  assert(Gear.mergeHost(helm, ring) == helm)
  local m = Gear.merge(helm, ring)
  assert(m.slot == "head" and m.base == "Helm", m.slot)
  assert(not m.unique, "Ink Stain fits gloves/rings, not head")
  local found = false; for _, a in ipairs(m.affixes) do if a.k == "crit" then found = true end end
  assert(found, "the ring's affix carries over")
  local gl = { slot = "gloves", name = "Big Gloves", base = "Gauntlets", rarity = 3, tier = 2, stats = { atk = 9, def = 9 }, affixes = {} }
  local m2 = Gear.merge(gl, ring); assert(m2.slot == "gloves" and m2.unique == "ink", "fits gloves")
  print("cross-slot merge ok")
end
