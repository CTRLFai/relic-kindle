-- Updater.config / Updater.request: token config uses the private repo through the
-- contents API; no config, or a config without a GitHub token, uses the public repo
-- over raw.githubusercontent.com with no Authorization header.
package.path = "./?.lua;" .. package.path
local SETTINGS = os.tmpname() .. "_dir"
os.execute("mkdir -p " .. SETTINGS)
local stub = function(t) return function() return t end end
package.preload["datastorage"] = stub({ getSettingsDir = function() return SETTINGS end,
    getDataDir = function() return SETTINGS end })
for _, m in ipairs({ "luasettings", "ui/network/manager", "ffi/util", "socket.http",
    "libs/libkoreader-lfs", "logger", "ltn12", "ffi/sha2", "socket", "socketutil", "util" }) do
    package.preload[m] = stub({})
end
local Updater = require("updater")
local function writeConfig(body)
    local f = assert(io.open(SETTINGS .. "/relic_config.lua", "w")); f:write(body); f:close()
end

-- 1. No config file: public repo, raw URL, no auth
os.remove(SETTINGS .. "/relic_config.lua")
local c = assert(Updater.config(), "no config should fall back to the public repo")
assert(c.public and c.github_repo == Updater.PUBLIC_REPO and c.branch == "main")
local url, h = Updater.request(c, "relic.koplugin/manifest.lua")
assert(url == "https://raw.githubusercontent.com/" .. Updater.PUBLIC_REPO .. "/main/relic.koplugin/manifest.lua", url)
assert(h.Authorization == nil)

-- 2. Todoist-only config: still public
writeConfig('return { todoist_token = "x" }')
c = Updater.config(); assert(c.public)

-- 3. Empty GitHub token: public
writeConfig('return { github_repo = "A/B", github_token = "" }')
c = Updater.config(); assert(c.public and c.github_repo == Updater.PUBLIC_REPO)

-- 4. Fork override
writeConfig('return { public_repo = "Friend/fork" }')
c = Updater.config(); assert(c.public and c.github_repo == "Friend/fork")

-- 5. Token config (Mike's Kindle): private repo via the API, unchanged behavior
writeConfig('return { github_repo = "CTRLFai/Relic", github_token = "t0k" }')
c = Updater.config(); assert(not c.public and c.github_repo == "CTRLFai/Relic" and c.branch == "main")
url, h = Updater.request(c, "relic.koplugin/manifest.lua")
assert(url == "https://api.github.com/repos/CTRLFai/Relic/contents/relic.koplugin/manifest.lua?ref=main", url)
assert(h.Authorization == "Bearer t0k" and h.Accept == "application/vnd.github.raw")

-- 6. Broken config file: public, not a crash
writeConfig('return {')
c = Updater.config(); assert(c.public)

os.execute("rm -rf " .. SETTINGS)
print("test_updater_config: ok")
