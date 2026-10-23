-- Chronicle: completion records, file append, month upload/merge, inbox skip.
-- Run from relic.koplugin/:  luajit ../tools/tests/test_chronicle.lua
for _,m in ipairs{"json","socket.http","ltn12","socket","socketutil","ui/network/manager"} do package.preload[m]=function() return {} end end
local tmp = os.tmpname()
package.preload["datastorage"] = function() return { getSettingsDir = function() return "/tmp" end } end
package.preload["logger"] = function() return { warn = function() end } end
-- reversible stand-ins for the KOReader compression helpers
package.preload["ffi/zlib"] = function() return { zlib_compress = function(d) return d:reverse() end,
  zlib_uncompress = function(d) return d:reverse() end } end
package.preload["ffi/sha2"] = function() return { bin_to_base64 = function(d) return (d:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end,
  base64_to_bin = function(h) return (h:gsub("..", function(x) return string.char(tonumber(x, 16)) end)) end } end

local Game = dofile("game.lua")
Game.setRoute(dofile("route.lua"))
Game.SKILLS = dofile("skills.lua"); Game.BOOK = dofile("recipes.lua")
local Gear = dofile("gear.lua"); local Combat = dofile("combat.lua"); Combat.bind(Game, Gear); Game.GEAR, Game.COMBAT = Gear, Combat
local Chronicle = dofile("chronicle.lua")
local now = os.time()
os.remove(tmp)

-- 1. completeQuest returns a record: daily, xp includes step pay, skills from tags
local s = Game.newState(now)
local q = Game.addQuest(s, "Cook dinner", "standard")
q.steps = { { text = "a" }, { text = "b" } }
Game.toggleStep(s, q.id, 1, now)
local paid = q.paid
assert(paid and paid > 0)
Game.setDaily(s, q.id)
local msg, rec = Game.completeQuest(s, q.id, now)
assert(type(msg) == "string" and rec, "record returned")
assert(rec.event == "done" and rec.kind == "daily" and rec.tier == "standard" and rec.title == "Cook dinner")
assert(rec.xp >= 25, "xp counts the step pay too: " .. rec.xp)
assert(#rec.skills >= 1, "cook tags a skill")
-- main and side kinds; tags override keywords
local m = Game.addQuest(s, "Write plan", "major", true)
local _, mrec = Game.completeQuest(s, m.id, now)
assert(mrec.kind == "main" and mrec.tier == "major")
local sq = Game.addQuest(s, "Thing", "minor"); sq.tags = {}
local _, srec = Game.completeQuest(s, sq.id, now)
assert(srec.kind == "side" and #srec.skills == 0)
-- missing quest: no record
local nm, nrec = Game.completeQuest(s, 9999, now)
assert(nm == "Quest not found." and nrec == nil)

-- 2. line format, tab/newline cleaning, deleted entry
local d = Game.chronicleEntry({ title = "bad\ttitle\nhere", tier = "minor" }, "deleted", 0, false)
local line = Chronicle.line(d, now)
local f = {}
for part in (line .. "\t"):gmatch("([^\t]*)\t") do table.insert(f, part) end
assert(#f == 8, "8 fields, got " .. #f)
assert(f[3] == "deleted" and f[4] == "side" and f[5] == "minor" and f[6] == "0" and f[7] == "-" and f[8] == "bad title here")
assert(f[1] == os.date("%Y-%m-%d", now))

-- 3. record appends; month filters
assert(Chronicle.record(rec, now, tmp))
assert(Chronicle.record(d, now, tmp))
local cur = os.date("%Y-%m", now)
local lines = Chronicle.month(cur, tmp)
assert(#lines == 2, "two lines")
assert(#Chronicle.month("1999-01", tmp) == 0)
assert(Chronicle.record(rec, now, "/nonexistent/dir/x.tsv") == false, "bad path doesn't raise")

-- 4. encode/decode round trip, merge dedupes and sorts
local back = Chronicle.decode(Chronicle.encode(lines))
assert(#back == 2 and back[1] == lines[1] and back[2] == lines[2])
assert(Chronicle.decode("junk") == nil)
local early = "2026-10-01\t08:00\tdone\tside\tminor\t10\t-\tearly"
local merged = Chronicle.merge({ lines[2], early }, { lines[1], lines[2] })
assert(#merged == 3 and merged[1] == early)
assert(Chronicle.prevMonth("2026-01") == "2025-12" and Chronicle.prevMonth("2026-10") == "2026-09")

-- 5. backup: creates the month task, merges remote lines, closes previous month once, skips same day
local tasks, calls = {}, {}
local Inbox = {
  config = function() return {} end, projectId = function() return 77 end,
  list = function() return tasks end,
  request = function(_, method, path, body) table.insert(calls, { method, path, body }); return true end,
}
local store = { v = {} }
function store:readSetting(k) return self.v[k] end
function store:saveSetting(k, v) self.v[k] = v end
function store:flush() end
local ok = Chronicle.backup(Inbox, store, false, now, tmp)
assert(ok and #calls == 1, "prev month empty: only the current month posts")
assert(calls[1][2] == "tasks" and calls[1][3].content == Chronicle.taskName(cur) and calls[1][3].project_id == 77)
assert(store.v.chronicle_closed == Chronicle.prevMonth(cur) and store.v.last_chronicle == os.date("%Y-%m-%d", now))
calls = {}
assert(select(2, Chronicle.backup(Inbox, store, false, now, tmp)) == "skipped" and #calls == 0)
-- remote has a line the Kindle lost: upload keeps it
local remote_only = os.date("%Y-%m-%d", now) .. "\t00:01\tdone\tside\tminor\t10\t-\tfrom before wipe"
tasks = { { id = 5, content = Chronicle.taskName(cur), description = Chronicle.encode({ remote_only }) } }
calls = {}
assert(Chronicle.backup(Inbox, store, true, now, tmp))
assert(#calls == 1 and calls[1][2] == "tasks/5")
local up = Chronicle.decode(calls[1][3].description)
assert(#up == 3 and up[1] == remote_only, "remote line kept and sorted first")
-- unchanged: no write
tasks[1].description = calls[1][3].description
calls = {}
assert(Chronicle.backup(Inbox, store, true, now, tmp) and #calls == 0)
-- failure: last_chronicle not advanced
store.v.last_chronicle = nil
Inbox.request = function() return nil end
os.remove(tmp); Chronicle.record(rec, now, tmp)
tasks = {}
local fok, fwhy = Chronicle.backup(Inbox, store, false, now, tmp)
assert(not fok and fwhy == "failed" and store.v.last_chronicle == nil)
Inbox.config = function() return nil end
assert(select(2, Chronicle.backup(Inbox, store, false, now, tmp)) == "no_config")

-- 6. the inbox never imports chronicle tasks
local src = io.open("inbox.lua"):read("*a")
assert(src:find("isChronicleTask(name)", 1, true), "inbox skips chronicle tasks")

os.remove(tmp)
print("test_chronicle OK")
