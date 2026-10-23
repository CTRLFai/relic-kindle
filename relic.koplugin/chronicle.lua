--[[
Relic chronicle: a record of every finished and deleted quest.

Each event is one tab-separated line in koreader/settings/relic_chronicle.tsv
(its own file, never inside the save, so the save backup stays small):

  date  time  event  kind  tier  xp  skills  title

  event   done | deleted | skipped (a repeating quest let go for the day, v39)
  kind    daily | main | side   (daily = it was today's Daily Quest)
  xp      character XP the completion paid (0 for deleted)
  skills  skill keys the quest trained, comma-separated, or -

Backup: once a day, when online, each month's lines are compressed into the
description of a Todoist task in the Relic project, "Relic chronicle YYYY-MM
(don't complete)". The current month is uploaded daily; the previous month is
uploaded until one upload succeeds after the month ends. Lines already in
Todoist are merged in, so a wiped Kindle never shrinks the record.
]]

local DataStorage = require("datastorage")
local logger = require("logger")
local sha2 = require("ffi/sha2")
local zlib = require("ffi/zlib")

local Chronicle = {}

Chronicle.HEADER = "RELIC CHRONICLE"
Chronicle.MAX_DESC = 16000

function Chronicle.path() return DataStorage:getSettingsDir() .. "/relic_chronicle.tsv" end

local function clean(v)
    return (tostring(v == nil and "" or v):gsub("[\t\r\n]+", " "))
end

-- rec = { event=, kind=, tier=, xp=, skills={...}, title= }
function Chronicle.line(rec, now)
    local skills = (rec.skills and #rec.skills > 0) and table.concat(rec.skills, ",") or "-"
    return table.concat({
        os.date("%Y-%m-%d", now), os.date("%H:%M", now), clean(rec.event), clean(rec.kind),
        clean(rec.tier), tostring(math.floor(tonumber(rec.xp) or 0)), clean(skills), clean(rec.title),
    }, "\t")
end

-- Appends one event. Never raises: the chronicle must not break completing a quest.
function Chronicle.record(rec, now, path)
    local ok, err = pcall(function()
        local f = assert(io.open(path or Chronicle.path(), "a"))
        f:write(Chronicle.line(rec, now or os.time()), "\n")
        f:close()
    end)
    if not ok then logger.warn("Relic chronicle: write failed", err) end
    return ok
end

-- All lines for one month ("YYYY-MM"), in file order.
function Chronicle.month(key, path)
    local out = {}
    local f = io.open(path or Chronicle.path(), "r")
    if not f then return out end
    for line in f:lines() do
        if line:sub(1, 7) == key then table.insert(out, line) end
    end
    f:close()
    return out
end

-- Every line from 'since' (YYYY-MM-DD, optional) on, in file order. For the RECORDS page.
function Chronicle.lines(since, path)
    local out = {}
    local f = io.open(path or Chronicle.path(), "r")
    if not f then return out end
    for line in f:lines() do
        if not since or line:sub(1, 10) >= since then table.insert(out, line) end
    end
    f:close()
    return out
end

function Chronicle.encode(lines)
    local data = table.concat(lines, "\n")
    local z = zlib.zlib_compress(data)
    return string.format("%s|1|%d|%d\n%s", Chronicle.HEADER, #lines, #data, sha2.bin_to_base64(z))
end

function Chronicle.decode(desc)
    if type(desc) ~= "string" then return nil end
    local ver, _, len, body = desc:match("^" .. Chronicle.HEADER .. "|(%d+)|(%d+)|(%d+)\n(.+)$")
    if not ver then return nil end
    body = body:gsub("%s", "")
    local ok, data = pcall(function() return zlib.zlib_uncompress(sha2.base64_to_bin(body), tonumber(len)) end)
    if not ok or type(data) ~= "string" or #data ~= tonumber(len) then return nil end
    local lines = {}
    for line in data:gmatch("[^\n]+") do table.insert(lines, line) end
    return lines
end

-- Union of two line lists, sorted by date and time (stable for equal stamps).
function Chronicle.merge(a, b)
    local seen, out = {}, {}
    for _, list in ipairs({ a, b }) do
        for _, l in ipairs(list) do
            if not seen[l] then seen[l] = true; table.insert(out, l) end
        end
    end
    local order = {}
    for i, l in ipairs(out) do order[l] = i end
    table.sort(out, function(x, y)
        local kx, ky = x:sub(1, 16), y:sub(1, 16)
        if kx ~= ky then return kx < ky end
        return order[x] < order[y]
    end)
    return out
end

function Chronicle.taskName(key) return "Relic chronicle " .. key .. " (don't complete)" end

function Chronicle.prevMonth(key)
    local y, m = key:match("^(%d+)-(%d+)$")
    y, m = tonumber(y), tonumber(m) - 1
    if m == 0 then y, m = y - 1, 12 end
    return string.format("%04d-%02d", y, m)
end

-- Uploads one month. Returns true, or nil + reason.
local function uploadMonth(Inbox, cfg, pid, tasks, key, path)
    local name = Chronicle.taskName(key)
    local task
    for _, t in ipairs(tasks) do
        if tostring(t.content or "") == name then task = t; break end
    end
    local lines = Chronicle.month(key, path)
    if task then lines = Chronicle.merge(Chronicle.decode(task.description) or {}, lines) end
    if #lines == 0 then return true end
    local desc = Chronicle.encode(lines)
    if #desc > Chronicle.MAX_DESC then
        logger.warn("Relic chronicle: month too large", key, #desc)
        return nil, "too_large"
    end
    local ok
    if task then
        if task.description == desc then return true end
        ok = Inbox.request(cfg, "POST", "tasks/" .. tostring(task.id), { description = desc })
    else
        ok = Inbox.request(cfg, "POST", "tasks", { content = name, project_id = pid, description = desc })
    end
    if not ok then return nil, "failed" end
    return true
end

-- Daily upload. store is the inbox LuaSettings already open in the caller.
-- Returns true, or nil + reason.
function Chronicle.backup(Inbox, store, force, now, path)
    local cfg = Inbox.config()
    if not cfg then return nil, "no_config" end
    now = now or os.time()
    local today = os.date("%Y-%m-%d", now)
    if not force and store:readSetting("last_chronicle") == today then return nil, "skipped" end
    local pid = Inbox.projectId(cfg, store)
    if not pid then return nil, "no_project" end
    local tasks = Inbox.list(cfg, "tasks?project_id=" .. tostring(pid))
    if not tasks then return nil, "failed" end
    local cur = os.date("%Y-%m", now)
    local prev = Chronicle.prevMonth(cur)
    local ok, why = true, nil
    if store:readSetting("chronicle_closed") ~= prev then
        local pok, pwhy = uploadMonth(Inbox, cfg, pid, tasks, prev, path)
        if pok then store:saveSetting("chronicle_closed", prev) else ok, why = nil, pwhy end
    end
    local cok, cwhy = uploadMonth(Inbox, cfg, pid, tasks, cur, path)
    if not cok then ok, why = nil, cwhy end
    if ok then store:saveSetting("last_chronicle", today) end
    store:flush()
    return ok, why
end

return Chronicle
