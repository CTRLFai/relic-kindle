--[[
Relic status report (Todoist).

Once a day, when online, Relic writes a plain-text report into the description of one
Todoist task in the Relic project, "Relic status (don't complete)". Claude reads it through
the Todoist connector before working on Relic, so a broken update or a crash shows up
without the player having to describe it. Spoiler-free: numbers only, no story text.

Status.build(s, info) makes the text (pure, testable). Status.run(...) uploads it.
]]

local Status = {}

local TITLE = "Relic status (don't complete)"
local MAX_DESC = 15000
local HISTORY = 7

local function n(v) return tonumber(v) or 0 end

local function fmtKm(v)
    local s = string.format("%.1f", v or 0)
    return s
end

-- info: { running=, installed=, update=, errors={...}, crash={...}, stage=, stage_name=, region=,
--         total_km=, day=, xp_next=, now=, history={...} }
function Status.build(s, info)
    local now = info.now or os.time()
    local t = s.tally or {}
    local out = {}
    local function add(fmt, ...) table.insert(out, string.format(fmt, ...)) end
    add("RELIC STATUS %s", os.date("%Y-%m-%d %H:%M", now))
    if s.paused then add("PAUSED since %s", os.date("%Y-%m-%d %H:%M", s.paused.since)) end
    add("plugin: running v%s, on disk v%s, save v%s", tostring(info.running or "?"), tostring(info.installed or "?"),
        tostring(s.save_version or "?"))
    add("update: %s", info.update or "no check recorded")
    add("day %d, level %d (xp %d/%d), streak %d (best %d), shields %d, integrity %d%%",
        n(info.day), n(s.level), n(s.xp), n(info.xp_next), n(s.streak), n(s.best_streak), n(s.shields), n(s.integrity))
    add("route: %s km of %d km, stage %s (%s), region %s, range %d",
        fmtKm(s.route and s.route.km), n(info.total_km), tostring(info.stage or "?"), tostring(info.stage_name or "?"),
        tostring(info.region or "?"), n(s.range))
    local beaten = {}
    for k in pairs((s.route and s.route.guardians) or {}) do table.insert(beaten, tostring(k)) end
    table.sort(beaten)
    add("guardians beaten at stages: %s", #beaten > 0 and table.concat(beaten, ", ") or "none")
    add("fights: %d won, %d lost, %d ran, %d resolved; guardian tries %d, wins %d",
        n(t.wins), n(t.losses), n(t.runs), n(t.resolved), n(t.guardian_tries), n(t.guardian_wins))
    add("hp %d, charge %d, grit %d, train sets %d, abilities %s",
        n(s.hp), n(s.charge), n(s.grit), n(s.training and s.training.total), (s.abilities and #s.abilities > 0) and table.concat(s.abilities, "+") or "none")
    local found = 0
    for _ in pairs(s.journal or {}) do found = found + 1 end
    add("baking: %d bakes, %d salvages, %d merges, %d regrows, %d recipes found; dust %d",
        n(t.bakes), n(t.salvages), n(t.merges), n(t.regrows), found, n(s.inv and s.inv.dust))
    local l = s.loot or {}
    add("gold: %d now, %d earned, %d loot left, %d claimed", math.floor(n(l.gold)), math.floor(n(l.earned)),
        #(l.items or {}), #(l.claims or {}))
    local open, late = 0, 0
    for _, q in ipairs(s.quests or {}) do
        open = open + 1
        if info.late and info.late(q) then late = late + 1 end
    end
    add("quests: %d open, %d late; daily %s", open, late, s.daily_done and "done" or (s.daily_id and "set" or "not set"))
    add("gear: %d in pack", #((s.gear and s.gear.bag) or {}))
    if info.errors and #info.errors > 0 then
        add("errors since last report (%d):", #info.errors)
        for _, e in ipairs(info.errors) do add("  %s", e) end
    else
        add("errors since last report: none")
    end
    if info.crash and #info.crash > 0 then
        add("crash.log changed since last report, last lines:")
        for _, l in ipairs(info.crash) do add("  %s", l) end
    end
    if info.history and #info.history > 0 then
        add("history:")
        for _, h in ipairs(info.history) do add("  %s", h) end
    end
    local text = table.concat(out, "\n")
    if #text > MAX_DESC then text = text:sub(1, MAX_DESC - 20) .. "\n[truncated]" end
    return text
end

-- One line for the 7-day history.
function Status.historyLine(s, info)
    return string.format("%s v%s L%d %skm streak %d integrity %d%% fights %d/%d",
        os.date("%Y-%m-%d", info.now or os.time()), tostring(info.running or "?"), n(s.level),
        fmtKm(s.route and s.route.km), n(s.streak), n(s.integrity),
        n(s.tally and s.tally.wins), n(s.tally and s.tally.losses))
end

-- Upload. store: the inbox settings store (keeps last_status and history).
-- Returns true, or nil + reason. force = send even if already sent today.
function Status.run(Inbox, store, build_text, force)
    local cfg = Inbox.config()
    if not cfg then return nil, "no_config" end
    local today = os.date("%Y-%m-%d")
    if not force and store:readSetting("last_status") == today then return nil, "skipped" end
    if not force and Inbox.online and not Inbox.online() then return nil, "offline" end
    local pid = Inbox.projectId(cfg, store)
    if not pid then return nil, "no_project" end
    local tasks = Inbox.list(cfg, "tasks?project_id=" .. tostring(pid))
    if not tasks then store:delSetting("todoist_project_id"); return nil, "failed" end
    local existing
    for _, t in ipairs(tasks) do
        if tostring(t.content or ""):lower():match("^relic status") and not Inbox.isSet(t.parent_id) then existing = t end
    end
    local text = build_text()
    local ok
    if existing then
        ok = Inbox.request(cfg, "POST", "tasks/" .. tostring(existing.id), { description = text })
    else
        ok = Inbox.request(cfg, "POST", "tasks", { content = TITLE, project_id = pid, description = text })
    end
    if not ok then return nil, "failed" end
    store:saveSetting("last_status", today)
    store:flush()
    return true
end

Status.HISTORY = HISTORY
return Status
