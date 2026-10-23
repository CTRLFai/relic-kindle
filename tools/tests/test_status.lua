-- Status report text, save v10 tallies, Status.run upload. Run from relic.koplugin/:  luajit ../tools/tests/test_status.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local Gear = dofile("gear.lua"); local Combat = dofile("combat.lua"); Combat.bind(Game, Gear); Game.GEAR, Game.COMBAT = Gear, Combat
local Status = dofile("status.lua")
local now = os.time()

-- 1. migration from v9 adds tally
local old = Game.newState(now); old.save_version = 9; old.tally = nil
local m = Game.migrate(old); assert(m.save_version == Game.SAVE_VERSION and type(m.tally) == "table")

-- 2. tally counts
local s = Game.newState(now - 3 * 86400)
Game.tally(s, "wins"); Game.tally(s, "wins"); Game.tally(s, "bakes", 3)
assert(s.tally.wins == 2 and s.tally.bakes == 3)

-- 3. build: fresh state, every line present, no crash on missing info
local info = { running = 24, installed = 24, update = "2026-10-01 08:00 installed v24", errors = { "10-01 07:00 Relic inbox: GET failed" },
  crash = { "line a", "line b" }, stage = Game.currentStage(s), stage_name = Game.STAGE_NAMES[1], region = "1", total_km = 1862,
  day = Game.dayIndex(s, now), xp_next = Game.xpToNext(s.level), now = now, history = { "h1" },
  late = function(q) local d = Game.daysLeft(q, now); return d and d < 0 end }
local q = Game.addQuest(s, "Late thing", "standard"); q.due = os.date("%Y-%m-%d", now - 3 * 86400)
local text = Status.build(s, info)
for _, want in ipairs{ "RELIC STATUS", "running v24", "update: 2026", "of 1862 km", "fights: 2 won", "3 bakes", "1 late",
    "errors since last report (1)", "Relic inbox: GET failed", "crash.log changed", "line b", "history:" } do
  assert(text:find(want, 1, true), "missing: " .. want .. "\n" .. text)
end
assert(Status.build(Game.newState(now), {}):find("errors since last report: none"))
-- no story text: no scene ids or story fields leak
assert(not text:find("scene") and not text:find("cantor"))

-- 4. run: creates once, then updates the same task; skips same day unless forced; offline skips
local calls = {}
local tasks = {}
local Inbox = {
  config = function() return {} end, projectId = function() return 77 end, isSet = function(v) return v ~= nil end,
  online = function() return true end,
  list = function() return tasks end,
  request = function(_, method, path, body) table.insert(calls, { method, path, body })
    if path == "tasks" then tasks = { { id = 5, content = body.content } } end; return true end,
}
local store = { d = {} }
function store:readSetting(k) return self.d[k] end
function store:saveSetting(k, v) self.d[k] = v end
function store:delSetting(k) self.d[k] = nil end
function store:flush() end
assert(Status.run(Inbox, store, function() return "A" end, false))
assert(calls[1][2] == "tasks" and calls[1][3].project_id == 77 and calls[1][3].content:match("^Relic status"))
local r, why = Status.run(Inbox, store, function() return "B" end, false); assert(not r and why == "skipped")
assert(Status.run(Inbox, store, function() return "C" end, true))
assert(calls[2][2] == "tasks/5" and calls[2][3].description == "C" and not calls[2][3].content)
store.d.last_status = nil; Inbox.online = function() return false end
r, why = Status.run(Inbox, store, function() return "D" end, false); assert(not r and why == "offline")
-- huge text is truncated
local big = Status.build(s, { errors = (function() local e = {} for i = 1, 400 do e[i] = string.rep("x", 60) end return e end)() })
assert(#big <= 15000 and big:find("%[truncated%]"))
print("test_status OK")
