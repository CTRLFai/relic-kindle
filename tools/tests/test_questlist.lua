-- Quest order, due dates, OUT, inbox parsing. Run from relic.koplugin/:  luajit ../tools/tests/test_questlist.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil"} do package.preload[m]=function() return {} end end
package.preload["datastorage"] = function() return { getSettingsDir = function() return "/tmp" end } end
package.preload["ui/network/manager"] = function() return {} end
package.preload["logger"] = function() return { warn = function() end, info = function() end, dbg = function() end } end
local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local now = os.time()
local s = Game.newState(now - 86400)
local a = Game.addQuest(s, "A", "minor")
local b = Game.addQuest(s, "B", "standard")
local c = Game.addQuest(s, "C", "major")
local d = Game.addQuest(s, "D", "minor")
local function names(list) local t = {} for _, q in ipairs(list) do table.insert(t, q.title) end return table.concat(t) end

-- 1. move above another, to the end, no-ops
assert(names(Game.orderedQuests(s, now)) == "ABCD")
assert(Game.moveQuest(s, d.id, a.id)); assert(names(Game.orderedQuests(s, now)) == "DABC")
assert(Game.moveQuest(s, d.id, nil)); assert(names(Game.orderedQuests(s, now)) == "ABCD")
assert(not Game.moveQuest(s, a.id, a.id)); assert(not Game.moveQuest(s, 999, a.id))
assert(Game.moveQuest(s, a.id, 999) and names(s.quests) == "BCDA", "unknown target goes to the end")

-- 2. due dates: text, overdue on top (oldest first), waiting last, bad dates refused
assert(Game.setDue(s, c.id, Game.dueIn(-1, now))); assert(Game.setDue(s, d.id, Game.dueIn(-3, now)))
assert(Game.setDue(s, b.id, Game.dueIn(0, now)))
assert(not Game.setDue(s, a.id, "next tuesday")); assert(not Game.setDue(s, 999, Game.dueIn(1, now)))
b.waiting = true
assert(names(Game.orderedQuests(s, now)) == "DCAB", names(Game.orderedQuests(s, now)))
assert(Game.dueText(c, now) == "LATE 1d" and Game.dueText(d, now) == "LATE 3d" and Game.dueText(b, now) == "due TODAY")
Game.setDue(s, a.id, Game.dueIn(1, now)); assert(Game.dueText(a, now) == "due tomorrow")
Game.setDue(s, a.id, Game.dueIn(9, now)); assert(Game.dueText(a, now) == "due 9d")
assert(Game.setDue(s, a.id, nil) and Game.dueText(a, now) == nil)
assert(Game.daysLeft({ due = "2026-10-05" }, os.time{ year = 2026, month = 10, day = 1, hour = 23 }) == 4)
assert(Game.daysLeft({ due = "2026-10-01" }, os.time{ year = 2026, month = 10, day = 1, hour = 0, min = 5 }) == 0)

-- 3. inbox: @out label and Todoist due date carry over
local Inbox = dofile("inbox.lua")
local p = Inbox.parse({ content = "Pick up parcel @out @minor", labels = {}, due = { date = "2026-10-03" } })
assert(p.title == "Pick up parcel" and p.out and p.tier == "minor" and p.due == "2026-10-03", p.title)
p = Inbox.parse({ content = "Call bank", labels = { "out" }, due = { date = "2026-10-04T15:00:00" } })
assert(p.out and p.due == "2026-10-04")
p = Inbox.parse({ content = "Write", labels = {} }); assert(not p.out and not p.due)
print("questlist ok")
-- review fixes: moving onto a waiting quest lands at the end of the active list; late quests can't move;
-- late ties keep the player's order; dueIn counts calendar days
local s2 = Game.newState(now - 86400)
local A, B, C = Game.addQuest(s2, "A"), Game.addQuest(s2, "B"), Game.addQuest(s2, "C")
local W, E = Game.addQuest(s2, "W"), Game.addQuest(s2, "E"); W.waiting = true
assert(Game.moveQuest(s2, A.id, W.id, now)); assert(names(Game.orderedQuests(s2, now)) == "BCEAW", names(Game.orderedQuests(s2, now)))
Game.setDue(s2, C.id, Game.dueIn(-1, now)); Game.setDue(s2, E.id, Game.dueIn(-1, now))
local ok, why = Game.moveQuest(s2, C.id, B.id, now); assert(not ok and why:find("Late"))
assert(names(Game.orderedQuests(s2, now)):sub(1, 2) == "CE", "late ties keep stored order")
assert(Game.dueIn(1, os.time{ year = 2026, month = 3, day = 8, hour = 23, min = 30 }) == "2026-03-09")
print("questlist review fixes ok")
-- v38: change a quest's size
do
  local t = Game.newState(os.time())
  local q = Game.addQuest(t, "resize me", "minor")
  assert(Game.setTier(t, q.id, "major") and q.tier == "major" and Game.questXp(q) == 60)
  assert(not Game.setTier(t, q.id, "huge") and q.tier == "major")
  print("resize ok")
end
