--[[
Relic self-updater.

Once a day, when Wi-Fi is connected, fetch relic.koplugin/manifest.lua from the
private GitHub repo. If its version is newer than the installed one, download
every file it lists, check size and SHA-256, and swap the new plugin folder in.
The old folder is kept in koreader/relic_update/previous for rollback.
The save file lives in koreader/settings and is never touched.

Config comes from koreader/settings/relic_config.lua (never committed):
    return { github_repo = "owner/Repo", github_token = "...", branch = "main" }
Without a GitHub token (no config file, or a config with only Todoist settings),
the plugin updates from the public repo Updater.PUBLIC_REPO over
raw.githubusercontent.com: no token, and no API rate limit (an install fetches
every file in the manifest, well over the 60 an hour GitHub allows without a token).
Set public_repo in the config to follow a fork instead.
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local NetworkMgr = require("ui/network/manager")
local ffiUtil = require("ffi/util")
local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local ltn12 = require("ltn12")
local sha2 = require("ffi/sha2")
local socket = require("socket")
local socketutil = require("socketutil")
local util = require("util")

local Updater = {}

-- Public release repo for players without a GitHub token (the stable track).
Updater.PUBLIC_REPO = "CTRLFai/relic-kindle"
Updater.RAW_BASE = "https://raw.githubusercontent.com"

local function stripSlash(p) return (p:gsub("/+$", "")) end

-- Paths ------------------------------------------------------------------------

function Updater.setPluginDir(dir) Updater.plugin_dir = stripSlash(dir) end

local function workDir() return DataStorage:getDataDir() .. "/relic_update" end
local function stagingDir() return workDir() .. "/staging" end
local function previousDir() return workDir() .. "/previous" end
local function discardDir() return workDir() .. "/discard" end

local function purge(dir)
    if lfs.attributes(dir, "mode") == "directory" then ffiUtil.purgeDir(dir) end
end

-- Config and local state -------------------------------------------------------

function Updater.config()
    local path = DataStorage:getSettingsDir() .. "/relic_config.lua"
    local ok, cfg = pcall(dofile, path)
    if not ok or type(cfg) ~= "table" then cfg = {} end
    if cfg.github_repo and cfg.github_token and cfg.github_token ~= "" then
        cfg.branch = cfg.branch or "main"
        cfg.api_base = cfg.api_base or "https://api.github.com"
        return cfg
    end
    -- No token: public repo, no auth.
    local repo = cfg.public_repo or Updater.PUBLIC_REPO
    if type(repo) ~= "string" or repo == "" then return nil end
    return { github_repo = repo, branch = cfg.public_branch or "main",
             raw_base = cfg.raw_base or Updater.RAW_BASE, public = true }
end

local function store() return LuaSettings:open(DataStorage:getSettingsDir() .. "/relic_update.lua") end

local function loadManifestString(str)
    local chunk = load(str, "manifest", "t", {})
    if not chunk then return nil end
    local ok, m = pcall(chunk)
    if ok and type(m) == "table" and tonumber(m.version) and type(m.files) == "table" then return m end
    return nil
end

function Updater.installedVersion()
    local f = io.open(Updater.plugin_dir .. "/manifest.lua", "rb")
    if not f then return 0 end
    local m = loadManifestString(f:read("*a")); f:close()
    return m and tonumber(m.version) or 0
end

-- HTTP -------------------------------------------------------------------------

-- URL and headers for one file: the contents API with a token, raw files without.
function Updater.request(cfg, repo_path)
    if cfg.public then
        return string.format("%s/%s/%s/%s", cfg.raw_base, cfg.github_repo, cfg.branch, repo_path),
            { ["User-Agent"] = "relic-kindle" }
    end
    return string.format("%s/repos/%s/contents/%s?ref=%s", cfg.api_base, cfg.github_repo, repo_path, cfg.branch),
        {
            ["Authorization"] = "Bearer " .. cfg.github_token,
            ["Accept"] = "application/vnd.github.raw",
            ["User-Agent"] = "relic-kindle",
            ["X-GitHub-Api-Version"] = "2022-11-28",
        }
end

local function fetch(cfg, repo_path)
    local url, headers = Updater.request(cfg, repo_path)
    local sink = {}
    socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
    local code, _, status = socket.skip(1, http.request{
        url = url,
        method = "GET",
        headers = headers,
        sink = ltn12.sink.table(sink),
    })
    socketutil:reset_timeout()
    if code ~= 200 then
        logger.warn("Relic updater: GET", repo_path, "failed:", status or code)
        return nil
    end
    return table.concat(sink)
end

-- Check and install --------------------------------------------------------------

-- Returns one of: "no_config", "offline", "skipped", "failed", "current", "installed"
-- plus the remote version when relevant.
local function remember(result, rv)
    local st = store()
    st:saveSetting("last_result", string.format("%s %s%s", os.date("%Y-%m-%d %H:%M"), result, rv and (" v" .. rv) or ""))
    st:flush()
end

function Updater.lastResult()
    local st = store()
    local held = st:readSetting("held_version")
    return (st:readSetting("last_result") or "none") .. (held and ("; holding back v" .. held .. " after a rollback") or "")
        .. (Updater.canRollback() and "; previous version kept" or "")
end

function Updater.check(force)
    local r, v = Updater.checkInner(force)
    if r ~= "skipped" and r ~= "offline" and r ~= "no_config" then pcall(remember, r, v) end
    return r, v
end

function Updater.checkInner(force)
    local cfg = Updater.config()
    if not cfg then return "no_config" end
    local st = store()
    local today = os.date("%Y-%m-%d")
    if not force and st:readSetting("last_check") == today then return "skipped" end
    if not force and not NetworkMgr:isConnected() then return "offline" end

    local mstr = fetch(cfg, "relic.koplugin/manifest.lua")
    if not mstr then return "failed" end
    st:saveSetting("last_check", today); st:flush()
    local remote = loadManifestString(mstr)
    if not remote then logger.warn("Relic updater: bad manifest"); return "failed" end

    local rv = tonumber(remote.version)
    local held = tonumber(st:readSetting("held_version")) or 0
    if rv <= Updater.installedVersion() or rv <= held then return "current", rv end

    -- Download everything into staging and verify it.
    local staging = stagingDir()
    purge(staging)
    util.makePath(staging)
    for _, f in ipairs(remote.files) do
        if type(f.path) ~= "string" or f.path:find("%.%.") or f.path:sub(1, 1) == "/" then
            logger.warn("Relic updater: unsafe path in manifest"); purge(staging); return "failed"
        end
        local data = fetch(cfg, "relic.koplugin/" .. f.path)
        if not data or #data ~= f.size or sha2.sha256(data) ~= f.sha256 then
            logger.warn("Relic updater: bad download", f.path); purge(staging); return "failed"
        end
        local dir = (staging .. "/" .. f.path):match("^(.*)/[^/]*$")
        util.makePath(dir)
        local out = io.open(staging .. "/" .. f.path, "wb")
        if not out then purge(staging); return "failed" end
        out:write(data); out:close()
    end
    local mout = io.open(staging .. "/manifest.lua", "wb")
    mout:write(mstr); mout:close()

    -- Swap: current -> previous, staging -> current.
    purge(previousDir())
    local ok1, err1 = os.rename(Updater.plugin_dir, previousDir())
    if not ok1 then logger.warn("Relic updater: backup failed", err1); purge(staging); return "failed" end
    local ok2, err2 = os.rename(staging, Updater.plugin_dir)
    if not ok2 then
        logger.warn("Relic updater: install failed, restoring", err2)
        os.rename(previousDir(), Updater.plugin_dir)
        return "failed"
    end
    logger.info("Relic updater: installed version", rv)
    return "installed", rv
end

function Updater.canRollback()
    return lfs.attributes(previousDir(), "mode") == "directory"
end

-- Put the previous version back and hold the bad one so it isn't reinstalled.
function Updater.rollback()
    if not Updater.canRollback() then return false end
    local bad = Updater.installedVersion()
    purge(discardDir())
    if not os.rename(Updater.plugin_dir, discardDir()) then return false end
    if not os.rename(previousDir(), Updater.plugin_dir) then
        os.rename(discardDir(), Updater.plugin_dir)
        return false
    end
    purge(discardDir())
    local st = store()
    st:saveSetting("held_version", bad); st:flush()
    pcall(remember, "rolled back", bad)
    return true, bad
end

return Updater
