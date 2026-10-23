-- Gold, loot, barrel cancel, distance to next stage (v37).
-- Run from relic.koplugin/:  luajit ../tools/tests/test_loot.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
Game.GEAR = dofile("gear.lua")
local now = os.time()

-- migration from v11 adds gold and the starting loot
local old = Game.newState(now); old.save_version = 11; old.loot = nil
local m = Game.migrate(old)
assert(m.save_version >= 12 and m.loot.gold == 0 and #m.loot.items == #Game.STARTING_LOOT)

-- gold by base tier only: dread and buffs add nothing
local s = Game.newState(now)
local q = Game.addQuest(s, "Write proposal", "major"); q.dread = true
table.insert(s.buffs, { kind = "xp_pct", amt = 30, ["until"] = now + 3600 })
Game.completeQuest(s, q.id, now)
assert(Game.goldBalance(s) == 20, Game.goldBalance(s))  -- Major = $2 (v38)

-- Minor soft cap halves gold too
local s2 = Game.newState(now)
for i = 1, 10 do local x = Game.addQuest(s2, "m" .. i, "minor"); Game.completeQuest(s2, x.id, now) end
local want = 8 * 2.5 + 2 * 1.25
assert(math.abs(Game.goldBalance(s2) - want) < 1e-9)

-- flat gold by tier (Mike, 2026-10-22): $0.25 / $0.50 / $2 / $10
for key, usd in pairs{ minor = 0.25, standard = 0.5, major = 2, epic = 10 } do
  local t = Game.newState(now)
  local x = Game.addQuest(t, "q", key); Game.completeQuest(t, x.id, now)
  assert(math.abs(Game.goldBalance(t) / Game.GOLD_PER_DOLLAR - usd) < 1e-9, key)
end

-- parse loot titles
local n, p = Game.parseLoot("Bandsaw $200"); assert(n == "Bandsaw" and p == 200)
n, p = Game.parseLoot("Jags/Noles shirt - $35"); assert(n == "Jags/Noles shirt" and p == 35)
n, p = Game.parseLoot("20 lb kettlebell 35"); assert(n == "20 lb kettlebell" and p == 35)
n, p = Game.parseLoot("$12.50 socks"); assert(n == "socks" and p == 12.5)
n, p = Game.parseLoot("Glassware $1,200"); assert(n == "Glassware" and p == 1200)
assert(Game.parseLoot("No price here") == nil)

-- claim
local s3 = Game.newState(now)
local base = #s3.loot.items  -- starting list is empty since the shared build
local kb = Game.addLoot(s3, "20 lb kettlebell", 35)
assert(Game.lootPrice(kb) == 350)
local ok, why = Game.claimLoot(s3, kb.id, now); assert(not ok and why:match("Need 350"))
Game.addGold(s3, 400)
assert(Game.claimLoot(s3, kb.id, now))
assert(Game.goldBalance(s3) == 50 and #s3.loot.items == base and s3.loot.claims[1].name == "20 lb kettlebell")
local it = Game.addLoot(s3, "Socks", 12); assert(Game.removeLoot(s3, it.id) and #s3.loot.items == base)

-- cancel a bake: both inputs come back, Fine kept
local s4 = Game.newState(now)
s4.inv.grain, s4.inv.herb_fine = 3, 1
assert(Game.startBake(s4, "grain", "herb_fine", now))
assert(s4.inv.grain == 2 and s4.inv.herb_fine == 0)
assert(Game.cancelBarrel(s4, 1, now + 60))
assert(s4.inv.grain == 3 and s4.inv.herb_fine == 1 and not s4.barrels[1])
-- a ready barrel can't be cancelled
assert(Game.startBake(s4, "grain", "grain", now))
assert(Game.cancelBarrel(s4, 1, now + 10 * 86400) == nil and s4.barrels[1])
-- pre-v37 bake (no ins) comes back from its combo
local s5 = Game.newState(now)
s5.barrels[1] = { combo = "grain+herb", key = "bread", label = "Bread", done_at = now + 600 }
local g0, h0 = s5.inv.grain, s5.inv.herb
assert(Game.cancelBarrel(s5, 1, now))
assert(s5.inv.grain == g0 + 1 and s5.inv.herb == h0 + 1)

-- cancel salvage
local s6 = Game.newState(now)
local cnt = Game.BOOK.salvage.count
s6.inv.grain = cnt
assert(Game.startSalvage(s6, "grain", now))
assert(Game.cancelBarrel(s6, 1, now) and s6.inv.grain == cnt)

-- cancel merge: both pieces and the dust back, even with a full pack
local s7 = Game.newState(now)
for i = 1, Game.BAG_MAX do Game.addItem(s7, { name = "Piece" .. i, slot = "main", rarity = 1, tier = 1 }) end
local a, b = s7.gear.bag[1], s7.gear.bag[2]
s7.inv.dust = 50
assert(Game.startMerge(s7, a.id, b.id, now))
local bag_mid, dust_mid = #s7.gear.bag, s7.inv.dust
Game.addItem(s7, { name = "Filler", slot = "main", rarity = 1, tier = 1 })
Game.addItem(s7, { name = "Filler2", slot = "main", rarity = 1, tier = 1 })
local before = #s7.gear.bag
assert(Game.cancelBarrel(s7, 1, now))
assert(#s7.gear.bag == before + 2 and s7.inv.dust == 50, #s7.gear.bag)

-- cancel regrow
local s8 = Game.newState(now)
s8.starters.bread = 1; s8.inv.dust = 10
assert(Game.startRegrow(s8, "bread", now))
assert(Game.cancelBarrel(s8, 1, now) and s8.starters.bread == 1 and s8.inv.dust == 10)

-- distance to the next stage
local s9 = Game.newState(now); s9.route.km = 132.8
local left, st = Game.kmToNextStage(s9)
assert(st == 7 and math.abs(left - (Game.STAGE_END[7] - 132.8)) < 1e-9)
print("test_loot OK")
