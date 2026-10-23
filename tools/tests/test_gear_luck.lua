-- Rarity odds improve with region (gear.lua, REGION_LUCK). Run: luajit tools/tests/test_gear_luck.lua
package.path = "relic.koplugin/?.lua;" .. package.path
local Gear = require("gear")
math.randomseed(7)
local rng = math.random
local function dist(tier, opts)
    local c = { 0, 0, 0, 0, 0 }
    for _ = 1, 200000 do local it = Gear.roll(rng, tier, opts); c[it.rarity] = c[it.rarity] + 1 end
    for i = 1, 5 do c[i] = c[i] / 2000 end
    return c
end
local t1, t9 = dist(1), dist(9)
print(string.format("Kent  : C %.1f%%  U %.1f%%  R %.1f%%  E %.1f%%  L %.2f%%", t1[1], t1[2], t1[3], t1[4], t1[5]))
print(string.format("Rome  : C %.1f%%  U %.1f%%  R %.1f%%  E %.1f%%  L %.2f%%", t9[1], t9[2], t9[3], t9[4], t9[5]))
assert(t9[1] < t1[1] - 10, "Common should be much rarer in Rome than in Kent")
assert(t9[5] > t1[5], "Legendary should be likelier in Rome")
assert(math.abs(t1[1] - 55) < 2, "Kent odds unchanged (Common about 55%)")
local boss = dist(1, { min_rarity = 3 })
assert(boss[1] == 0 and boss[2] == 0, "boss floor still holds")
print("ok")
