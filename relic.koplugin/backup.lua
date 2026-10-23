--[[
Relic save backup (Todoist).

Once a day, when online, the save file is compressed and stored in the
description of one of seven Todoist tasks in the Relic project:
"Relic save 1" .. "Relic save 7", one per day of the week, so the last
seven days are always kept. Restore picks the newest one.
Descriptions are used (not comments) because they exist on every Todoist plan.
]]

local DataStorage = require("datastorage")
local logger = require("logger")
local sha2 = require("ffi/sha2")
local zlib = require("ffi/zlib")

local Backup = {}

local HEADER = "RELIC SAVE"
local MAX_DESC = 16000

local function encode(data)
    local z = zlib.zlib_compress(data)
    return string.format("%s|1|%d|%d\n%s", HEADER, os.time(), #data, sha2.bin_to_base64(z))
end

local function decode(desc)
    if type(desc) ~= "string" then return nil end
    local ver, t, len, body = desc:match("^" .. HEADER .. "|(%d+)|(%d+)|(%d+)\n(.+)$")
    if not ver then return nil end
    body = body:gsub("%s", "")
    local ok, data = pcall(function() return zlib.zlib_uncompress(sha2.base64_to_bin(body), tonumber(len)) end)
    if not ok or #data ~= tonumber(len) then return nil end
    return data, tonumber(t)
end
Backup.encode, Backup.decode = encode, decode

local function saveTasks(Inbox, cfg, pid)
    local tasks = Inbox.list(cfg, "tasks?project_id=" .. tostring(pid))
    if not tasks then return nil end
    local by_slot = {}
    for _, t in ipairs(tasks) do
        local slot = tostring(t.content or ""):match("^Relic save (%d)")
        if slot then by_slot[tonumber(slot)] = t end
    end
    return by_slot
end

-- Returns true, or nil + reason.
function Backup.run(Inbox, store, save_path, day_index, force)
    local cfg = Inbox.config()
    if not cfg then return nil, "no_config" end
    local today = os.date("%Y-%m-%d")
    if not force and store:readSetting("last_backup") == today then return nil, "skipped" end
    local f = io.open(save_path, "rb")
    if not f then return nil, "no_save" end
    local data = f:read("*a"); f:close()
    local desc = encode(data)
    if #desc > MAX_DESC then
        logger.warn("Relic backup: save too large", #desc)
        return nil, "too_large"
    end
    local pid = Inbox.projectId(cfg, store)
    if not pid then return nil, "no_project" end
    local slots = saveTasks(Inbox, cfg, pid)
    if not slots then return nil, "failed" end
    local slot = (day_index % 7) + 1
    local t = slots[slot]
    local ok
    if t then
        ok = Inbox.request(cfg, "POST", "tasks/" .. tostring(t.id), { description = desc })
    else
        ok = Inbox.request(cfg, "POST", "tasks", {
            content = "Relic save " .. slot .. " (don't complete)", project_id = pid, description = desc })
    end
    if not ok then return nil, "failed" end
    store:saveSetting("last_backup", today)
    store:flush()
    return true
end

-- Finds the newest backup. Returns data, time or nil + reason.
function Backup.newest(Inbox, store)
    local cfg = Inbox.config()
    if not cfg then return nil, "no_config" end
    local pid = Inbox.projectId(cfg, store)
    if not pid then return nil, "no_project" end
    local slots = saveTasks(Inbox, cfg, pid)
    if not slots then return nil, "failed" end
    local best, best_t
    for _, t in pairs(slots) do
        local data, when = decode(t.description)
        if data and (not best_t or when > best_t) then best, best_t = data, when end
    end
    if not best then return nil, "none" end
    return best, best_t
end

-- Writes the backup over the save, keeping the current save as .before_restore.
function Backup.restore(data, save_path)
    local cur = io.open(save_path, "rb")
    if cur then
        local old = cur:read("*a"); cur:close()
        local b = io.open(save_path .. ".before_restore", "wb")
        if b then b:write(old); b:close() end
    end
    local out = io.open(save_path, "wb")
    if not out then return false end
    out:write(data); out:close()
    os.remove(save_path .. ".old")  -- LuaSettings would otherwise prefer its own backup
    return true
end

return Backup
