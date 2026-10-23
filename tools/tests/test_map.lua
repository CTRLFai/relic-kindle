-- Logic tests for the full route and map helpers. Run from relic.koplugin/:  luajit ../tools/tests/test_map.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
local R = dofile("route.lua")
-- before setRoute: the built-in 11 stages
assert(#Game.STAGE_KM == 11)
local end11 = Game.STAGE_END[11]
Game.setRoute(R)
assert(#Game.STAGE_KM == 83 and #Game.STAGE_END == 83 and Game.STAGE_END[11] == end11, "first 11 stages unchanged")
assert(math.abs(Game.STAGE_END[83] - 1862) < 1e-6 and R.total_km == 1862)
assert(Game.STAGE_NAMES[2] == "Dover" and Game.STAGE_NAMES[83] == "St Peter's Square")
-- regions tile the route with no gaps
local prev = 0
for i, r in ipairs(R.regions) do
  assert(math.abs(r.km0 - prev) < 1e-6, "gap before region " .. i)
  assert(math.abs(r.km1 - Game.STAGE_END[r.last]) < 1e-6)
  assert(io.open(r.image), "missing " .. r.image)
  assert(#r.towns == r.last - r.first + 2)
  prev = r.km1
end
assert(io.open(R.route_image) and io.open("map/you.png") and io.open("map/stamp.png"))
local s = Game.newState(os.time())
-- region lookup, incl. waiting at a gate
s.route.km = 0; assert(Game.currentRegion(s) == 1)
s.route.km = 33; assert(Game.currentRegion(s) == 1, "at Dover gate stays in Kent")
s.route.km = 33.5; assert(Game.currentRegion(s) == 2)
s.route.km = 1862; assert(Game.currentRegion(s) == 9)
-- marker hits towns exactly and stays inside the image
for _, r in ipairs(R.regions) do
  for _, t in ipairs(r.towns) do
    local x, y = Game.mapPoint(r.path, t[3])
    assert(math.abs(x - t[1]) <= 1.5 and math.abs(y - t[2]) <= 1.5, r.name .. " town mismatch")
  end
end
for km = 0, 1862, 7 do
  local x, y = Game.mapPoint(R.route_path, km)
  assert(x >= 0 and x <= R.image_w and y >= 0 and y <= R.image_h)
end
-- end of the road: no flips past Rome
s.route.km = 1861.8; s.range = 5; s.route.guardians = {}
for n in pairs(Game.GUARDIANS) do s.route.guardians[n] = true end
local rng = function(n) return n end
Game.flipCard(s, rng); assert(math.abs(s.route.km - 1862) < 1e-9)
local kind = Game.flipCard(s, rng); assert(kind == "none" and s.range == 4)
print("ok")
