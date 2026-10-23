--[[
Relic gear: slots, item bases, rarities, affixes.

Affix design follows The Legend of William Oh: flat stat boosts on everything, a few
percentage affixes (Thorns, lifesteal), and on rare+ Relics a triggered effect that fires at
a moment in the fight (on hit, when hurt, on kill...). The UNIQUE list is discovered in play;
treat it as sealed (don't list it for Mike).

Stats: str (attack), res (defense, HP), foc (Charge), acu (crit, ability scaling),
kin (Kinesthetics: dodge, tempo, getting away).
Nothing here grants steps, Range or XP (rule 2).
]]

local Gear = {}

Gear.SLOTS = { "main", "off", "head", "chest", "gloves", "pants", "feet", "cloak", "amulet", "ring1", "ring2" }
Gear.SLOT_NAMES = { main = "Main hand", off = "Off hand", head = "Head", chest = "Chest", gloves = "Gloves",
    pants = "Pants", feet = "Feet", cloak = "Cloak", amulet = "Amulet", ring1 = "Ring", ring2 = "Ring" }

Gear.RARITY = {
    { key = "common",    name = "Common",    weight = 55, stats = 1, affixes = 0, mult = 1.0 },
    { key = "uncommon",  name = "Uncommon",  weight = 28, stats = 2, affixes = 1, mult = 1.2 },
    { key = "rare",      name = "Rare",      weight = 12, stats = 2, affixes = 2, mult = 1.45 },
    { key = "epic",      name = "Epic",      weight = 4,  stats = 3, affixes = 2, mult = 1.75, unique = true },
    { key = "legendary", name = "Legendary", weight = 1,  stats = 3, affixes = 3, mult = 2.1, unique = true },
}

-- Item bases per slot. kind: weapon damage type (crush/slash/pierce) for main/off weapons.
-- base: the slot's core stat line at tier 1 (scaled by tier and rarity).
Gear.BASES = {
    main = {
        { name = "Warhammer", kind = "crush", base = { atk = 3 } },
        { name = "Shortsword", kind = "slash", base = { atk = 3 } },
        { name = "Sickle", kind = "slash", base = { atk = 2, acu = 1 } },
        { name = "Tomahawk", kind = "slash", base = { atk = 3 } },
        { name = "Mace", kind = "crush", base = { atk = 2, res = 1 } },
        { name = "Dagger", kind = "pierce", base = { atk = 2, acu = 1 } },
    },
    off = {
        { name = "Buckler", base = { def = 2 } },
        { name = "Holdout Dagger", kind = "pierce", base = { atk = 1, acu = 1 } },
        { name = "Tome", base = { foc = 2 } },
    },
    head = { { name = "Helm", base = { def = 1, hp = 2 } }, { name = "Circlet", base = { foc = 1, acu = 1 } }, { name = "Mask", base = { acu = 2 } } },
    chest = { { name = "Cuirass", base = { def = 2, hp = 3 } }, { name = "Gambeson", base = { def = 1, hp = 5 } } },
    gloves = { { name = "Gauntlets", base = { atk = 1, def = 1 } }, { name = "Gloves", base = { str = 1, acu = 1 } } },
    pants = { { name = "Leggings", base = { def = 1, hp = 2 } }, { name = "Chaps", base = { res = 2 } } },
    feet = { { name = "Boots", base = { def = 1, res = 1 } }, { name = "Stompers", base = { res = 2 } }, { name = "Treads", base = { kin = 2 } } },
    cloak = { { name = "Cloak", base = { def = 1, foc = 1 } }, { name = "Mantle", base = { res = 1, hp = 2 } } },
    amulet = { { name = "Amulet", base = { foc = 2 } }, { name = "Torc", base = { res = 1, foc = 1 } } },
    ring1 = { { name = "Ring", base = { str = 1 } }, { name = "Signet", base = { acu = 1 } }, { name = "Band", base = { res = 1 } } },
}
Gear.BASES.ring2 = Gear.BASES.ring1

Gear.STAT_NAMES = { str = "Strength", res = "Resistance", foc = "Focus", acu = "Acuity", kin = "Kinesthetics",
    atk = "Attack", def = "Defense", hp = "HP", charge = "Charge" }

-- Build styles ("soft sets"): affixes lean into a style, and pieces of one style work together.
-- Feeders build something up (stacks, frost, dodges, low HP); payoffs cash it in.
Gear.STYLES = {
    affliction = "Affliction: stack debuffs, then exploit them",
    retribution = "Retribution: get hit, hit back, drink it in",
    rime = "Rime: frost the joints, then shatter them",
    blood = "Blood: stronger the closer you are to falling",
    riposte = "Riposte: slip the blow, answer it",
}

-- Minor affixes (uncommon and up). v = percent or flat, scaled by tier.
Gear.AFFIXES = {
    -- plain
    { key = "crit",      name = "Crit",      fmt = "+%d%% crit chance",     lo = 3,  hi = 8 },
    { key = "fire",      name = "Fire",      fmt = "+%d fire damage",       lo = 1,  hi = 2, flat = true },
    { key = "acid",      name = "Acid",      fmt = "+%d acid damage",       lo = 1,  hi = 2, flat = true },
    { key = "lightning", name = "Lightning", fmt = "+%d lightning damage",  lo = 1,  hi = 2, flat = true },
    { key = "first",     name = "Opening",   fmt = "+%d damage on your first hit", lo = 3, hi = 6, flat = true },
    { key = "killcharge",name = "Siphon",    fmt = "+%d Charge on a kill",  lo = 1,  hi = 1, flat = true },
    { key = "guard",     name = "Guard",     fmt = "%d%% less damage taken", lo = 4, hi = 8 },
    -- affliction
    { key = "twin",      style = "affliction", fmt = "%d%% chance to strike twice", lo = 10, hi = 20 },
    { key = "stack2",    style = "affliction", fmt = "Hits add %d extra debuff stack", lo = 1, hi = 1, flat = true, cap = 1 },
    { key = "exploit",   style = "affliction", fmt = "+%d damage per debuff on the enemy", lo = 1, hi = 2, flat = true },
    -- retribution
    { key = "thorns",    style = "retribution", fmt = "%d%% Thorns",        lo = 8,  hi = 15 },
    { key = "lifesteal", style = "retribution", fmt = "%d%% Lifesteal",     lo = 4,  hi = 10 },
    { key = "retaliate", style = "retribution", fmt = "+%d Thorns damage when hit", lo = 1, hi = 3, flat = true },
    -- rime
    { key = "cold",      style = "rime", fmt = "+%d cold damage",           lo = 1,  hi = 2, flat = true },
    { key = "chill",     style = "rime", fmt = "%d%% chance hits frost the enemy", lo = 15, hi = 30 },
    { key = "shatter",   style = "rime", fmt = "+%d%% damage to frosted enemies", lo = 10, hi = 25 },
    -- blood
    { key = "bleedout",  style = "blood", fmt = "+%d%% damage below half HP", lo = 10, hi = 25 },
    { key = "bloodprice",style = "blood", fmt = "Lifesteal doubled below half HP (+%d%% Lifesteal)", lo = 3, hi = 6 },
    { key = "spite",     style = "blood", fmt = "+%d%% Thorns below half HP", lo = 10, hi = 25 },
    -- riposte
    { key = "dodge",     style = "riposte", fmt = "%d%% chance to dodge",   lo = 5,  hi = 12 },
    { key = "brace",     style = "riposte", fmt = "%d%% chance to Brace when hit (next hit halved)", lo = 15, hi = 30 },
    { key = "counter",   style = "riposte", fmt = "After a dodge, strike back for %d%% of your attack", lo = 40, hi = 80 },
}
Gear.AFFIX = {}
for _, a in ipairs(Gear.AFFIXES) do Gear.AFFIX[a.key] = a end

-- Named sets (SEALED): 2- and 4-piece bonuses, handled in combat.lua.
Gear.SETS = {
    retribution = { name = "Retribution", style = "retribution", slots = { "ring1", "amulet", "head", "pants" },
        bonus2 = "+10% Thorns", bonus4 = "When hit, Thorns and Lifesteal double until your next turn; +10% Lifesteal" },
    serpent = { name = "the Coiled Serpent", style = "affliction", slots = { "main", "gloves", "feet", "amulet" },
        bonus2 = "Hits drain 1 enemy attack (Venom)", bonus4 = "Venom stacks to 8; +2 damage per Venom stack" },
    rime = { name = "Hoarfrost", style = "rime", slots = { "main", "head", "chest", "cloak" },
        bonus2 = "Frost lasts 3 turns", bonus4 = "Every hit frosts; frosted enemies lose every third turn" },
    vow = { name = "the Kept Vow", style = "blood", slots = { "ring1", "amulet", "cloak", "feet" },
        bonus2 = "Vow Strike costs 1 less; +1 attack per 3 streak days", bonus4 = "+2% damage per streak day (up to +30%)" },
}

-- Unique triggered affixes (epic and legendary). SEALED: discovered in play.
-- hook: fight_start | hit | hurt | kill | ability | turn
Gear.UNIQUE = {
    hoarfrost = { name = "Hoarfrost", slots = { main = true, off = true, head = true },
        text = "Hits frost the enemy's joints for 2 turns: it hits 30% softer. Crushing blows +25% on frosted foes; slashing and fire -15%." },
    venom = { name = "Serpent Venom", slots = { main = true, off = true, gloves = true },
        text = "Each hit drains 1 enemy attack (stacks to 5)." },
    retribution = { name = "Explosive Retribution", slots = { ring1 = true, ring2 = true, chest = true },
        text = "When hit, burst for 3 + Resistance/3 damage." },
    sublime = { name = "Sublime Retribution", slots = { main = true, amulet = true },
        text = "When hit, your Thorns and Lifesteal double until your next turn ends." },
    wraiths = { name = "Blood Wraiths", slots = { cloak = true, chest = true, amulet = true },
        text = "Below half HP, each hit you take sends a wraith: 30% the enemy is Feared and loses its next turn." },
    rebound = { name = "Rebounding", slots = { off = true },
        text = "After you dodge or Brace, your next attack deals +25%." },
    tracers = { name = "Tracers", slots = { main = true, gloves = true },
        text = "Hits leave burning trails: 2 fire damage on each of the enemy's next 2 turns." },
    harvest = { name = "Cold Harvest", slots = { main = true },
        text = "Heal 2 per hit; 4 if the enemy is frosted." },
    servitude = { name = "Eternal Servitude", slots = { main = true, off = true },
        text = "Kills raise a bone thrall (max 3). Each thrall adds 2 damage to every attack. Thralls crumble at day's end." },
    ink = { name = "Ink Stain", slots = { gloves = true, ring1 = true, ring2 = true },
        text = "Your marks linger: each hit adds 1 damage to your next hits this fight (up to +5)." },
    archive = { name = "Archive", slots = { head = true, amulet = true },
        text = "At the start of a fight, reveal the enemy's quirk (as Appraise)." },
    vowbound = { name = "Vow-bound", slots = { amulet = true, ring1 = true, ring2 = true },
        text = "+1 attack for every 3 days of Daily Directive streak (up to +6)." },
    resonance = { name = "Resonance", slots = { gloves = true, head = true },
        text = "Abilities deal +3 lightning damage." },
    oiled = { name = "Oiled Up", slots = { chest = true },
        text = "+20% damage while at full HP. Oils up the muscles nice and shiny." },
    bridgeguard = { name = "Stubborn", slots = { head = true, feet = true, pants = true },
        text = "You can't be Displaced or Bound." },
}

-- Name flavor by rarity (prefix) and unique (suffix).
local PREFIX = { common = { "Worn", "Plain", "Pitted" }, uncommon = { "Sturdy", "Keen", "Tempered" },
    rare = { "Runed", "Gleaming", "Veteran's" }, epic = { "Tower-forged", "Relic-bound" }, legendary = { "Mythic", "Storied" } }

local STAT_POOL = { "str", "res", "foc", "acu", "kin" }

Gear.REGION_LUCK = 0.12

local function pick(list, rng) return list[rng(#list)] end

local function rollRarity(rng, luck, climb)
    -- luck lifts every non-Common rarity alike (Appraise); climb lifts each step more
    -- than the one below it (region depth), so deep regions favour the top rarities.
    local w = {}
    local total = 0
    for i, r in ipairs(Gear.RARITY) do
        w[i] = r.weight * (r.key == "common" and 1 or (1 + (luck or 0))) * (1 + (climb or 0) * (i - 1))
        total = total + w[i]
    end
    local roll = rng(1000) / 1000 * total
    for i = 1, #w do
        roll = roll - w[i]
        if roll <= 0 then return i end
    end
    return 1
end

-- Make one item. tier = region index (1-9). min_rarity forces a floor (bosses).
function Gear.roll(rng, tier, opts)
    opts = opts or {}
    rng = rng or math.random
    local slot = opts.slot or pick(Gear.SLOTS, rng)
    local base = pick(Gear.BASES[slot], rng)
    -- Deeper regions turn up better gear (Mike, 2026-10-01): each region past Kent adds
    -- 0.12 climb, so by Rome Uncommon odds are x1.96 and Legendary x4.84.
    local climb = Gear.REGION_LUCK * (math.max(1, tier) - 1)
    local ri = math.max(rollRarity(rng, opts.luck, climb), opts.min_rarity or 1)
    local R = Gear.RARITY[ri]
    local scale = (1 + 0.6 * (tier - 1)) * R.mult
    local stats = {}
    for k, v in pairs(base.base) do stats[k] = math.max(1, math.floor(v * scale + 0.5)) end
    for _ = 1, R.stats do
        local k = pick(STAT_POOL, rng)
        stats[k] = (stats[k] or 0) + math.max(1, math.floor((1 + rng(2)) * scale / 1.5 + 0.5))
    end
    local affixes, used = {}, {}
    -- items lean into one style: after the first styled affix, later ones prefer the same style
    local lean
    for _ = 1, R.affixes do
        local a = pick(Gear.AFFIXES, rng)
        if lean and rng(100) <= 60 then
            local same = {}
            for _, x in ipairs(Gear.AFFIXES) do if x.style == lean and not used[x.key] then table.insert(same, x) end end
            if #same > 0 then a = pick(same, rng) end
        end
        lean = lean or a.style
        if not used[a.key] then
            used[a.key] = true
            local v = a.lo + rng(a.hi - a.lo + 1) - 1
            if a.flat and not a.cap then v = math.max(1, math.floor(v * (1 + 0.3 * (tier - 1)))) end
            table.insert(affixes, { k = a.key, v = v })
        end
    end
    local unique, set
    if R.unique and rng(100) <= 40 then
        local fits = {}
        for key, st in pairs(Gear.SETS) do
            for _, sl in ipairs(st.slots) do
                if sl == slot or (sl == "ring1" and (slot == "ring1" or slot == "ring2")) then table.insert(fits, key) end
            end
        end
        table.sort(fits)
        if #fits > 0 then set = pick(fits, rng) end
    end
    if R.unique and not set then
        local fits = {}
        for key, u in pairs(Gear.UNIQUE) do if u.slots[slot] then table.insert(fits, key) end end
        table.sort(fits)
        if #fits > 0 then unique = pick(fits, rng) end
    end
    local name = pick(PREFIX[R.key], rng) .. " " .. base.name
    if unique then name = base.name .. " of " .. Gear.UNIQUE[unique].name end
    if set then name = base.name .. " of " .. Gear.SETS[set].name end
    local key = name
    for _, k in ipairs({ "atk", "def", "hp", "str", "res", "foc", "acu", "kin" }) do key = key .. (stats[k] or 0) end
    return { slot = slot, name = name, base = base.name, rarity = ri, tier = tier, kind = base.kind, stats = stats, affixes = affixes, unique = unique, set = set,
        art = Gear.pickArt(base.name, tier, key) }
end

-- Styles an item leans into (from its affixes and set).
function Gear.styles(item)
    local seen, out = {}, {}
    local function add(st) if st and not seen[st] then seen[st] = true; table.insert(out, st) end end
    for _, a in ipairs(item.affixes or {}) do add(Gear.AFFIX[a.k] and Gear.AFFIX[a.k].style) end
    if item.set then add(Gear.SETS[item.set].style) end
    return out
end

local function cap(str) return (str:gsub("^%l", string.upper)) end

-- One-line summary for lists (fits a 758 px wide screen at 18 px).
function Gear.summary(item)
    local parts = {}
    for _, k in ipairs({ "atk", "def", "hp", "str", "res", "foc", "acu", "kin", "charge" }) do
        local v = item.stats and item.stats[k]
        if v and v ~= 0 then table.insert(parts, string.format("%+d %s", v, k:upper())) end
    end
    local st = Gear.styles(item)
    if #st > 0 then
        local names = {}
        for _, x in ipairs(st) do table.insert(names, cap(x)) end
        table.insert(parts, "[" .. table.concat(names, "/") .. "]")
    end
    return table.concat(parts, "  ")
end

-- Full description lines for the detail view.
function Gear.describe(item)
    local lines = { item.name, Gear.RARITY[item.rarity].name .. "  ·  " .. (Gear.SLOT_NAMES[item.slot] or item.slot) .. "  ·  tier " .. item.tier }
    for _, k in ipairs({ "atk", "def", "hp", "str", "res", "foc", "acu", "kin", "charge" }) do
        local v = item.stats and item.stats[k]
        if v and v ~= 0 then table.insert(lines, string.format("%+d %s", v, Gear.STAT_NAMES[k])) end
    end
    for _, a in ipairs(item.affixes or {}) do
        local def = Gear.AFFIX[a.k]
        if def then table.insert(lines, string.format(def.fmt, a.v) .. (def.style and ("  [" .. cap(def.style) .. "]") or "")) end
    end
    if item.set then
        local st = Gear.SETS[item.set]
        table.insert(lines, "Set of " .. st.name .. " (" .. #st.slots .. " pieces). 2: " .. st.bonus2 .. ". 4: " .. st.bonus4 .. ".")
    end
    if item.unique then table.insert(lines, Gear.UNIQUE[item.unique].name .. ": " .. Gear.UNIQUE[item.unique].text) end
    return lines
end

-- Rough worth for the better/worse marker: stats plus affixes, uniques count extra.
function Gear.score(item)
    if not item then return 0 end
    local w = { atk = 3, def = 3, hp = 1, str = 2, res = 2, foc = 1.5, acu = 1.5, kin = 1.5, charge = 1 }
    local sc = 0
    for k, v in pairs(item.stats or {}) do sc = sc + (w[k] or 1) * v end
    for _, a in ipairs(item.affixes or {}) do sc = sc + (a.v >= 3 and a.v / 2 or a.v * 2) end
    if item.unique then sc = sc + 8 end
    if item.set then sc = sc + 6 end
    return sc
end

-- Which equip slot an item goes to (rings can use either ring slot).
function Gear.slotsFor(item)
    if item.slot == "ring1" or item.slot == "ring2" then return { "ring1", "ring2" } end
    return { item.slot }
end

-- Art (tools/gear_art: build_plugin.py made the first five, batch.py the rest). Each base has
-- variants; a variant with min_tier drops only from that region on (Mike 2026-10-02: D2, M2,
-- BU1, GA3 from region 3). %s is the rarity key, for the shortsword's rarity ladder.
local function V(list)
    local out = {}
    for _, v in ipairs(list) do
        if type(v) == "table" then out[#out + 1] = { file = v[1], min_tier = v[2] }
        else out[#out + 1] = { file = v, min_tier = 1 } end
    end
    return out
end
Gear.ART = {
    Shortsword = V{ "shortsword_%s", "s1", "s2", "s3" },
    Dagger = V{ "dagger", "d1", { "d2", 3 } },
    ["Holdout Dagger"] = V{ "holdout", "h1" },
    Tomahawk = V{ "t1", "t2", "t3" },
    Warhammer = V{ "w1", "w2", "w3" },
    Mace = V{ "m1", { "m2", 3 }, "m3" },
    Sickle = V{ "sk1" },
    Buckler = V{ { "bu1", 3 }, "bu2", "bu3" },
    Tome = V{ "tm1", "tm2", "tm3" },
    Helm = V{ "helm", "he1", "he2", "he3" },
    Circlet = V{ "ci1", "ci2", "ci3" },
    Mask = V{ "ma1", "ma3", "ma4" },
    Cuirass = V{ "cuirass", "cu1", "cu2" },
    Gambeson = V{ "gb1" },
    Gauntlets = V{ "ga1", "ga2", { "ga3", 3 } },
    Gloves = V{ "gl1", "gl2" },
    Leggings = V{ "le1", "le2" },
    Chaps = V{ "ch1", "ch2" },
    Boots = V{ "bo1", "bo2", "bo3" },
    Stompers = V{ "st1", "st2" },
    Treads = V{ "tr1", "tr2" },
    Cloak = V{ "cl1", "cl2" },
    Mantle = V{ "mn1", "mn2" },
    Amulet = V{ "am1", "am2", "am3" },
    Torc = V{ "to1", "to2", "to3" },
    Ring = V{ "ri1", "ri2", "ri3" },
    Signet = V{ "si1" },
    Band = V{ "ba1" },
}

-- The item's base name: stored on new items; older items are matched by name within their slot.
function Gear.baseName(item)
    if item.base then return item.base end
    local best
    for _, b in ipairs(Gear.BASES[item.slot] or {}) do
        if item.name and item.name:find(b.name, 1, true) and (not best or #b.name > #best) then best = b.name end
    end
    return best
end

-- Variants a piece of this base and tier can show.
local function artChoices(base, tier)
    local out = {}
    for _, v in ipairs(Gear.ART[base] or {}) do
        if (tier or 1) >= v.min_tier then out[#out + 1] = v.file end
    end
    return out
end

-- Picks a variant without using the rng (so drops stay the same as before art existed).
function Gear.pickArt(base, tier, key)
    local c = artChoices(base, tier)
    if #c == 0 then return nil end
    local h = 0
    for i = 1, #key do h = (h * 31 + key:byte(i)) % 1000003 end
    return c[h % #c + 1]
end

-- Art file name (without folder) for an item, or nil. New items carry .art (kept through
-- merges); older ones get a variant from their name.
function Gear.artFor(item)
    local base = Gear.baseName(item)
    if not base or not Gear.ART[base] then return nil end
    local a = item.art
    if not a then a = Gear.pickArt(base, item.tier, item.name or base) end
    if not a then return nil end
    local r = Gear.RARITY[item.rarity or 1]
    return string.format(a, r and r.key or "common") .. ".png"
end

-- Merging (SEALED rules: Mike works them out from the merge log) ---------------------
-- Any two pieces become one (any slots, Mike 2026-10-05). The stronger is the host: it keeps
-- its slot, base, name and its own affixes in full. The guest gives part of itself:
--   stats at 50%; affixes at 60%, or 85% when both pieces share a style;
--   an affix both carry stacks as the larger plus a quarter of the smaller;
--   each generation past the second costs the guest another 10% (floor 20%).
-- A unique or set moves over only if the host has neither and it fits the host's slot. Affixes cap at the rarity's
-- count + 2, weakest dropped. Nothing ever comes out bigger than the two put together.
function Gear.sameSlot(a, b)
    local function norm(sl) return (sl == "ring2") and "ring1" or sl end
    return a and b and norm(a.slot) == norm(b.slot)
end

local function affixWorth(a) return a.v >= 3 and a.v / 2 or a.v * 2 end

-- The piece that keeps its form (and slot) when a and b merge.
function Gear.mergeHost(a, b)
    if Gear.score(b) > Gear.score(a) then return b, a end
    return a, b
end

function Gear.merge(a, b)
    local host, guest = Gear.mergeHost(a, b)
    local shared = false
    local hs = {}
    for _, st in ipairs(Gear.styles(host)) do hs[st] = true end
    for _, st in ipairs(Gear.styles(guest)) do if hs[st] then shared = true end end
    local gen = math.max(host.gen or 1, guest.gen or 1) + 1
    local fade = math.max(0.2, 1 - 0.1 * math.max(0, gen - 2))
    local keep_stat = 0.5 * fade
    local keep_aff = (shared and 0.85 or 0.6) * fade

    local stats = {}
    for k, v in pairs(host.stats or {}) do stats[k] = v end
    for k, v in pairs(guest.stats or {}) do
        stats[k] = (stats[k] or 0) + math.floor(v * keep_stat)
    end

    local aff, order = {}, {}
    for _, x in ipairs(host.affixes or {}) do aff[x.k] = x.v; table.insert(order, x.k) end
    for _, x in ipairs(guest.affixes or {}) do
        local def = Gear.AFFIX[x.k]
        local add = math.max(1, math.floor(x.v * keep_aff + 0.5))
        if aff[x.k] then
            local hi, lo = math.max(aff[x.k], x.v), math.min(aff[x.k], x.v)
            aff[x.k] = hi + math.floor(lo / 4)
        else
            aff[x.k] = add
            table.insert(order, x.k)
        end
        if def and def.cap then aff[x.k] = math.min(aff[x.k], def.cap) end
    end
    local rarity = math.max(host.rarity or 1, guest.rarity or 1)
    local list = {}
    for _, k in ipairs(order) do table.insert(list, { k = k, v = aff[k] }) end
    local max_aff = Gear.RARITY[rarity].affixes + 2
    if #list > max_aff then
        table.sort(list, function(x, y) return affixWorth(x) > affixWorth(y) end)
        while #list > max_aff do table.remove(list) end
    end

    local unique, set = host.unique, host.set
    if not unique and not set then
        local hs = (host.slot == "ring2") and "ring1" or host.slot
        if guest.unique and Gear.UNIQUE[guest.unique] and Gear.UNIQUE[guest.unique].slots[hs] then unique = guest.unique end
        if guest.set and Gear.SETS[guest.set] then
            for _, sl in ipairs(Gear.SETS[guest.set].slots) do if sl == hs then set = guest.set end end
        end
    end
    local name = host.name
    if not host.unique and not host.set then
        local base = host.name:match("%S+$") or host.name
        if unique then name = base .. " of " .. Gear.UNIQUE[unique].name
        elseif set then name = base .. " of " .. Gear.SETS[set].name end
    end
    if not name:find("^Merged ") and not unique and not set then name = "Merged " .. (name:match("%S+$") or name) end
    return { slot = host.slot, name = name, base = Gear.baseName(host), rarity = rarity, tier = math.max(host.tier or 1, guest.tier or 1),
        kind = host.kind, stats = stats, affixes = list, unique = unique, set = set, gen = gen,
        art = host.art or Gear.pickArt(Gear.baseName(host) or "", host.tier, host.name or "") }
end

-- Merge bake time in minutes, by the rarer piece (plan section 8, 2-item row).
Gear.MERGE_MINUTES = { 60, 180, 720, 2880, 10080 }
function Gear.mergeMinutes(a, b) return Gear.MERGE_MINUTES[math.max(a.rarity or 1, b.rarity or 1)] end
function Gear.mergeDust(a, b) return 1 + (a.rarity or 1) + (b.rarity or 1) end
-- Instant salvage: Dust by rarity and tier.
function Gear.salvageDust(item) return (item.rarity or 1) + math.max(0, (item.tier or 1) - 1) end

return Gear
