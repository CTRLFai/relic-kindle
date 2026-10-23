-- Gear art lookup: every variant has its files (all rarities for the ladder), every base has art,
-- tier gating holds, old items without .base/.art still find art, and merges keep the look.
-- Run from relic.koplugin/
local Gear = dofile("gear.lua")
for base, vs in pairs(Gear.ART) do
  for _, v in ipairs(vs) do
    for _, r in ipairs(Gear.RARITY) do
      local f = string.format(v.file, r.key) .. ".png"
      assert(io.open("gear_art/" .. f), "missing gear_art/" .. f)
    end
  end
end
for slot, bases in pairs(Gear.BASES) do
  for _, b in ipairs(bases) do assert(Gear.ART[b.name], "no art for " .. b.name) end
end
assert(Gear.artFor({ slot = "main", name = "Keen Shortsword", rarity = 4, art = "shortsword_%s" }) == "shortsword_epic.png")
assert(Gear.artFor({ slot = "off", name = "Worn Holdout Dagger", rarity = 1 }):match("^h"), "longest base name wins")
assert(Gear.artFor({ slot = "main", name = "Dagger of Tracers", rarity = 5 }))
assert(Gear.artFor({ slot = "head", name = "Merged Helm", rarity = 2 }))
assert(Gear.artFor({ slot = "main", name = "Keen Tomahawk", rarity = 2 }):match("^t%d%.png$"))
assert(Gear.artFor({ slot = "main", name = "Keen Wand", rarity = 2 }) == nil)
-- gated variants: never below region 3, and they do turn up from region 3
local gated = { d2 = true, m2 = true, bu1 = true, ga3 = true }
local seen = {}
math.randomseed(2)
for _ = 1, 3000 do
  local it = Gear.roll(math.random, 1); assert(it.base); assert(it.art, "no art on " .. it.name)
  assert(not gated[it.art], it.art .. " in region 1")
  local it3 = Gear.roll(math.random, 3)
  if gated[it3.art] then seen[it3.art] = true end
  assert(Gear.artFor(it) == Gear.artFor(it), "stable")
end
for k in pairs(gated) do assert(seen[k], k .. " never dropped in region 3") end
-- merges keep the host's art; old hosts keep the art they showed
local a, b = Gear.roll(math.random, 1, { slot = "head" }), Gear.roll(math.random, 1, { slot = "head" })
local host = Gear.mergeHost(a, b)
local m = Gear.merge(a, b); assert(m.base); assert(m.art == host.art)
local old = { slot = "feet", name = "Worn Boots", rarity = 1, tier = 1, stats = { def = 1 }, affixes = {} }
local old2 = { slot = "feet", name = "Worn Stompers", rarity = 1, tier = 1, stats = {}, affixes = {} }
local shown = Gear.artFor(old)
assert(Gear.artFor(Gear.merge(old, old2)) == shown, "old host keeps its look")
print("gear art ok")
