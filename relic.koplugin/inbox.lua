--[[
Relic phone inbox (Todoist).

Quests added on the phone land in a Todoist project named "Relic" (from the
Todoist app, or the Add Quest Shortcut via quick add). When the Kindle is on
Wi-Fi, Relic pulls them in as quests and closes them in Todoist so nothing
imports twice.

Labels (Todoist labels, or @words typed in the title):
  @daily            make it today's Daily Quest (if none is set)
  @main             Main Quest
  @minor @standard @major @epic   size (default standard)
  @dread            pays double
  @out              out of the house (marker)
  @loot             a real-world reward, not a quest: "Bandsaw $200"
A Todoist due date carries over as the quest's due date.
A recurring Todoist task ("every day", "every weekday", "every mon, fri", "every 3 days")
becomes a repeating quest and is deleted in Todoist (closing would only move it to the next
date, and it would come back as a duplicate).
The task description, one line per step, becomes the checklist.

Steps: the phone's Relic Steps Shortcut adds a task titled "Relic steps" whose
description holds daily totals, one per line: "2026-09-28 5234". Relic reads
them, hands them to steps(days), and deletes the task.
]]

local DataStorage = require("datastorage")
local JSON = require("json")
local NetworkMgr = require("ui/network/manager")
local http = require("socket.http")
local logger = require("logger")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")

local Inbox = {}

local SIZES = { minor = true, standard = true, major = true, epic = true }

-- JSON nulls decode to a sentinel, not nil; treat only real strings/numbers as set.
local function isSet(v) return type(v) == "string" or type(v) == "number" end

function Inbox.config()
    local ok, cfg = pcall(dofile, DataStorage:getSettingsDir() .. "/relic_config.lua")
    if not ok or type(cfg) ~= "table" or not cfg.todoist_token or cfg.todoist_token == "" then return nil end
    cfg.todoist_base = cfg.todoist_base or "https://api.todoist.com/api/v1"
    cfg.todoist_project = cfg.todoist_project or "Relic"
    return cfg
end

local function request(cfg, method, path, body)
    local sink = {}
    local headers = {
        ["Authorization"] = "Bearer " .. cfg.todoist_token,
        ["User-Agent"] = "relic-kindle",
    }
    local source
    if body then
        local data = JSON.encode(body)
        headers["Content-Type"] = "application/json"
        headers["Content-Length"] = tostring(#data)
        source = ltn12.source.string(data)
    elseif method == "POST" then
        headers["Content-Length"] = "0"
    end
    socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url = cfg.todoist_base .. "/" .. path,
        method = method,
        headers = headers,
        source = source,
        sink = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    local text = table.concat(sink)
    if type(code) ~= "number" or code < 200 or code >= 300 then
        logger.warn("Relic inbox:", method, path, "failed:", status or code)
        return nil
    end
    if text == "" then return true end
    local ok, data = pcall(JSON.decode, text)
    return ok and data or true
end

-- v1 lists come back as { results = [...], next_cursor = ... }; accept a bare array too.
local function list(cfg, path)
    local out, cursor = {}, nil
    for _ = 1, 20 do
        local sep = path:find("?", 1, true) and "&" or "?"
        local data = request(cfg, "GET", path .. (cursor and (sep .. "cursor=" .. cursor) or ""))
        if type(data) ~= "table" then return nil end
        local items = data.results or data
        for _, it in ipairs(items) do table.insert(out, it) end
        cursor = isSet(data.next_cursor) and data.next_cursor or nil
        if not cursor then break end
    end
    return out
end

local function projectId(cfg, store)
    local cached = store:readSetting("todoist_project_id")
    if cached then return cached end
    local projects = list(cfg, "projects")
    if not projects then return nil end
    for _, p in ipairs(projects) do
        if type(p.name) == "string" and p.name:lower() == cfg.todoist_project:lower() then
            store:saveSetting("todoist_project_id", p.id)
            return p.id
        end
    end
    logger.warn("Relic inbox: no Todoist project named", cfg.todoist_project)
end

-- Turn one Todoist task into { title=, tier=, daily=, main=, dread=, steps={} }
function Inbox.parse(task)
    local tags = {}
    for _, l in ipairs(type(task.labels) == "table" and task.labels or {}) do tags[tostring(l):lower()] = true end
    local title = tostring(task.content or "")
    title = title:gsub("@(%w+)", function(w) tags[w:lower()] = true; return "" end)
    title = title:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    local tier = "standard"
    for size in pairs(SIZES) do if tags[size] then tier = size end end
    local steps = {}
    local desc = task.description
    if isSet(desc) then
        for line in desc:gmatch("[^\r\n]+") do
            line = line:gsub("^%s*[-*•]?%s*%[?[ xX]?%]?%s*", ""):gsub("%s+$", "")
            if line ~= "" then table.insert(steps, line) end
        end
    end
    local due, rep
    if type(task.due) == "table" and type(task.due.date) == "string" then
        due = task.due.date:match("^(%d%d%d%d%-%d%d%-%d%d)")
        if task.due.is_recurring == true and Inbox.parseRecurrence then
            local known
            rep, known = Inbox.parseRecurrence(task.due.string, due)
            if known then due = nil else rep = nil end  -- not understood: a one-off quest
        end
    end
    return { title = title, tier = tier, daily = tags.daily, main = tags.main, dread = tags.dread, steps = steps,
        out = tags.out, due = due, loot = tags.loot, rep = rep }
end

-- "2026-09-28 5234" lines (newline or ";" separated) -> { ["2026-09-28"] = 5234 }. Thousands separators
-- ("5,234", "5.234", "5 234") are allowed; a line without a number is skipped.
function Inbox.parseSteps(desc)
    local days = {}
    if not isSet(desc) then return days end
    for line in tostring(desc):gmatch("[^\r\n;]+") do
        local key, num = line:match("^%s*(%d%d%d%d%-%d%d%-%d%d)[%s:=]+([%d,%.' ]+)")
        local n = num and tonumber((num:gsub("[^%d]", "")))
        if n and n > (days[key] or -1) then days[key] = n end
    end
    return days
end

local function isStepsTask(name) return name:lower():match("^relic steps") ~= nil end
local function isSaveTask(name) return name:lower():match("^relic save") ~= nil end
local function isStatusTask(name) return name:lower():match("^relic status") ~= nil end
local function isChronicleTask(name) return name:lower():match("^relic chronicle") ~= nil end

-- Pulls new quests into the game state. Returns number imported, or nil + reason.
-- add(parsed) must add the quest to the state and save it before we close the task.
-- steps(days) (optional) must credit and save step totals before we delete the task.
function Inbox.pull(store, add, force, steps)
    local cfg = Inbox.config()
    if not cfg then return nil, "no_config" end
    if not force and not NetworkMgr:isConnected() then return nil, "offline" end
    local pid = projectId(cfg, store)
    if not pid then return nil, "no_project" end
    local tasks = list(cfg, "tasks?project_id=" .. tostring(pid))
    if not tasks then
        store:delSetting("todoist_project_id")  -- project may have been recreated
        return nil, "failed"
    end
    -- Todoist subtasks become checklist steps of their parent.
    local children = {}
    for _, t in ipairs(tasks) do
        if isSet(t.parent_id) then
            children[tostring(t.parent_id)] = children[tostring(t.parent_id)] or {}
            table.insert(children[tostring(t.parent_id)], t)
        end
    end
    local n = 0
    -- Step totals first, merged across tasks (keep the highest per day).
    local days, step_tasks = {}, {}
    for _, t in ipairs(tasks) do
        if isStepsTask(tostring(t.content or "")) then
            for key, v in pairs(Inbox.parseSteps(t.description)) do
                if v > (days[key] or -1) then days[key] = v end
            end
            table.insert(step_tasks, t)
        end
    end
    if steps and #step_tasks > 0 then
        if steps(days) ~= false then
            for _, t in ipairs(step_tasks) do request(cfg, "DELETE", "tasks/" .. tostring(t.id)) end
        end
    end
    -- Tasks already imported whose close failed are skipped, not imported twice.
    local imported = store:readSetting("imported_ids") or {}
    local seen = {}
    for _, id in ipairs(imported) do seen[id] = true end
    -- recurring tasks imported as repeating quests (v39+): a failed delete is retried, never re-imported
    local rep_imported = store:readSetting("imported_rep_ids") or {}
    local rep_seen = {}
    for _, id in ipairs(rep_imported) do rep_seen[id] = true end
    for _, t in ipairs(tasks) do
        local name = tostring(t.content or "")
        if not isSaveTask(name) and not isStepsTask(name) and not isStatusTask(name) and not isChronicleTask(name)
            and not isSet(t.parent_id) then
          local id = tostring(t.id)
          local recurring = type(t.due) == "table" and t.due.is_recurring == true
          local parsed = Inbox.parse(t)
          -- A recurring task Relic understood becomes a repeating quest and is deleted (closing
          -- would only move it to its next date). One it couldn't read is imported once as a
          -- normal quest and left alone in Todoist; it's never deleted on a guess.
          local known = recurring and parsed.rep ~= nil
          local function finish()
              if known then request(cfg, "DELETE", "tasks/" .. id)
              elseif not recurring then request(cfg, "POST", "tasks/" .. id .. "/close") end
          end
          if recurring and not known then
              if not seen[id] then logger.warn("Relic inbox: repeat not understood, left in Todoist:", tostring(t.due.string)) end
          end
          if (seen[id] and not known) or (known and rep_seen[id]) then
            finish()  -- retry the close or delete only (an unreadable recurring task is left alone)
          else
            -- (a recurring task seen before v39 was only ever closed: it's imported once now as a repeating quest)
            local q = Inbox.parse(t)
            for _, c in ipairs(children[tostring(t.id)] or {}) do
                local sub = Inbox.parse(c)
                if sub.title ~= "" then table.insert(q.steps, sub.title) end
            end
            if q.title ~= "" and add(q) ~= false then
                table.insert(imported, id)
                while #imported > 200 do table.remove(imported, 1) end
                store:saveSetting("imported_ids", imported)
                if known then
                    table.insert(rep_imported, id)
                    while #rep_imported > 200 do table.remove(rep_imported, 1) end
                    store:saveSetting("imported_rep_ids", rep_imported)
                end
                store:flush()
                finish()
                n = n + 1
            end
          end
        end
    end
    store:saveSetting("last_pull", os.time())
    store:flush()
    return n
end

-- shared with backup.lua
Inbox.request = request
Inbox.list = list
Inbox.projectId = projectId
Inbox.isSet = isSet
Inbox.isStatusTask = isStatusTask
function Inbox.online() return NetworkMgr:isConnected() end

return Inbox
