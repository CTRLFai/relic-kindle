--[[
Relic story engine. Pure Lua, no KOReader dependencies.

The rules (game.lua) push event strings into s.events. process() matches them
against each scene's trigger, queues the scene once, and handles day-based
triggers and scenes scheduled for a later day. The UI shows queued scenes one
at a time and calls seen() when the player closes one.

Scene content lives in separate files (story_act1.lua, ...). Each file returns
a list of scenes: { id=, trigger=, pages={...}, ... }. Page kinds:
  sys    = { kind="sys", text=... }        SYSTEM or hardware readout (monospace)
  cantor = { kind="cantor", lines={...} }  the companion speaking
  log    = { kind="log", title=, text= }   a recovered log (archived when shown)
  notice = { kind="notice", text=... }     a notice (◇ or ✦); first line large
  hold   = { kind="hold", text=..., button= } a notice the player must long-press to pass
  narration = { kind="narration", text=... } plain description
Optional scene fields:
  after = "daily_prompt"     the UI asks for a Daily Quest when the scene closes
  silent_rest_of_day = true  Cantor says nothing more today
  schedule = { id=, days= }  queue another scene that many days later
  sub = function(s) -> table substitutions for [KEY] placeholders
]]

local Story = {}

Story.scenes = {}   -- id -> scene
local by_trigger = {}

function Story.load(list)
    for _, sc in ipairs(list) do
        Story.scenes[sc.id] = sc
        -- trigger: an event string or a day table; triggers: a list of those
        sc.triggers = sc.triggers or (sc.trigger and { sc.trigger }) or {}
        for _, t in ipairs(sc.triggers) do
            if type(t) == "string" then
                by_trigger[t] = by_trigger[t] or {}
                table.insert(by_trigger[t], sc)
            end
        end
    end
end

local function queue(st, id)
    if st.fired[id] or not Story.scenes[id] then return end
    st.fired[id] = true
    table.insert(st.queue, id)
end

-- Day-based triggers, checked every time the game ticks.
local function dayTriggers(s, st, day)
    for i = #st.scheduled, 1, -1 do
        local item = st.scheduled[i]
        if day >= item.day then
            table.remove(st.scheduled, i)
            queue(st, item.id)
        end
    end
    for _, sc in pairs(Story.scenes) do
        for _, t in ipairs(sc.triggers) do
            if type(t) == "table" and t.day_from and not st.fired[sc.id] then
                local ok = day >= t.day_from and (not t.day_to or day <= t.day_to)
                if ok and t.requires and not st.fired[t.requires] then ok = false end
                if ok and t.check and not t.check(s) then ok = false end
                if ok then queue(st, sc.id) end
            end
        end
    end
end

function Story.process(s, now, dayIndex)
    local st = s.story
    local events = s.events or {}
    s.events = {}
    for _, ev in ipairs(events) do
        for _, sc in ipairs(by_trigger[ev] or {}) do
            queue(st, sc.id)
        end
    end
    dayTriggers(s, st, dayIndex)
end

function Story.pending(s)
    local id = s.story.queue[1]
    return id and Story.scenes[id] or nil
end

local function substitute(text, subs)
    if not subs or not text then return text end
    return (text:gsub("%[(%u+)%]", function(k) return subs[k] and tostring(subs[k]) or "[" .. k .. "]" end))
end

-- Pages with placeholders filled in.
function Story.pages(s, sc)
    local subs = sc.sub and sc.sub(s) or nil
    local out = {}
    for _, p in ipairs(sc.pages) do
        local q = {}
        for k, v in pairs(p) do q[k] = v end
        q.text = substitute(p.text, subs)
        if p.lines then
            q.lines = {}
            for i, l in ipairs(p.lines) do q.lines[i] = substitute(l, subs) end
        end
        table.insert(out, q)
    end
    return out
end

-- Call when the player closes the scene at the front of the queue.
function Story.seen(s, now, dayIndex, dayKey)
    local st = s.story
    local id = table.remove(st.queue, 1)
    local sc = id and Story.scenes[id]
    if not sc then return nil end
    for _, p in ipairs(sc.pages) do
        if p.kind == "log" then table.insert(st.logs, { scene = id, title = p.title }) end
    end
    if sc.silent_rest_of_day then st.silent_day = dayKey end
    if sc.schedule then
        table.insert(st.scheduled, { id = sc.schedule.id, day = dayIndex + (sc.schedule.days or 1) })
    end
    return sc
end

-- A recovered log page, for rereading from the archive.
function Story.logPage(entry)
    local sc = Story.scenes[entry.scene]
    if not sc then return nil end
    for _, p in ipairs(sc.pages) do
        if p.kind == "log" and p.title == entry.title then return p end
    end
end

return Story
