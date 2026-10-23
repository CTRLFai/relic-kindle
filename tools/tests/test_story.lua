-- Story content checks (sealed files: run, don't print text). Run from relic.koplugin/:  luajit ../tools/tests/test_story.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua"); Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local Story = dofile("story.lua")
local acts = { dofile("story_act1.lua"), dofile("story_act2.lua") }
local ids = {}
for _, act in ipairs(acts) do
  for _, sc in ipairs(act) do assert(not ids[sc.id], "duplicate scene id " .. sc.id); ids[sc.id] = true end
  Story.load(act)
end
-- Act II rules: no legal words, no em dashes, no "journey", no 7 printed, every page has text
local banned = { "court", "trial", "evidence", "defendant", "verdict", "journey", "hearing", "—" }
local function check(id, t)
  local low = t:lower()
  for _, w in ipairs(banned) do assert(not low:find(w, 1, true), id .. " uses banned word: " .. w) end
  assert(not t:find("7"), id .. " prints a 7")
end
local n = 0
for _, sc in ipairs(acts[2]) do
  n = n + 1
  for _, t in ipairs(sc.triggers or { sc.trigger }) do
    assert(type(t) == "string" and (t:match("^stage_end:%d+$") or t:match("^guardian:%d+$") or t:match("^guardian_beaten:%d+$")), sc.id)
    local k = tonumber(t:match("%d+")); assert(k >= 10 and k <= 30, sc.id)
    if t:match("^guardian") then assert(Game.GUARDIANS[k], sc.id .. " guardian " .. k .. " doesn't exist") end
  end
  for _, p in ipairs(sc.pages) do
    if p.text then check(sc.id, p.text) end
    for _, l in ipairs(p.lines or {}) do check(sc.id, l) end
    assert(p.text or p.lines)
  end
end
-- Act II scenes fire on their events and fill placeholders
local s = Game.newState(os.time() - 40 * 86400); s.route.km = 690
s.events = { "stage_end:28", "guardian:23", "stage_end:27" }
Story.process(s, os.time(), 40)
local seen = {}
while Story.pending(s) do
  local sc = Story.pending(s)
  for _, p in ipairs(Story.pages(s, sc)) do assert(not (p.text or ""):find("%[P%]"), "placeholder left") end
  seen[sc.id] = true
  Story.seen(s, os.time(), 40, "2026-10-01")
end
assert(seen.M28 and seen.G23 and seen.B20, "act II scenes fire")
print("story ok (" .. n .. " act II scenes)")
