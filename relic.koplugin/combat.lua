--[[
Relic combat rules (turn-based, one tap per action, built for e-ink).

Past Kent, normal fights are a real threat (Mike, 2026-10-08: "a reason to grind"): about 5-6
swings, ATTACK alone costs about a third of your HP, and every enemy winds up a heavy blow a turn
ahead now and then. Elites (rarer, tougher, better loot) show up past Kent. Losing costs 10%
Integrity. Guardians wind up more often and harden at half HP. Answers: Blink (dodge),
Ram (Displace = interrupt), Breaker, or a potion. RESOLVE once you out-level an enemy by 3.

The Kent roster and the unique affixes are sealed: discovered in play.
Bind with Combat.bind(Game, Gear) before use.
]]

local Combat = {}
local Game, Gear

function Combat.bind(g, gear) Game, Gear = g, gear end

-- First abilities (pick 2 at the combat unlock, like Will's Trial). cost = Charge.
Combat.ABILITIES = {
    { key = "goat", name = "Aspect of the Goat", passive = true,
      text = "Passive. +1 defense, +1 more per 5 Resistance. You can't be Displaced or Bound, and RUN always works." },
    { key = "hand", name = "Relic Hand", cost = 2,
      text = "2 Charge. A ghost hand strikes for 3 + Acuity, ignoring defense." },
    { key = "blink", name = "Blink", cost = 2,
      text = "2 Charge. Step through space: dodge the next attack, and your next hit is a critical." },
    { key = "ram", name = "Ram", cost = 3,
      text = "3 Charge. Hit for 150%. The enemy is Displaced and loses its next turn (a wind-up is broken)." },
    { key = "appraise", name = "Appraise", cost = 1,
      text = "1 Charge. Read the enemy: reveal its quirk, +25% damage this fight, better loot." },
    { key = "vow", name = "Vow Strike", cost = 3,
      text = "3 Charge. Hit for your attack + 2 per day of Daily Directive streak (up to +20)." },
}
Combat.ABILITY = {}
for _, a in ipairs(Combat.ABILITIES) do Combat.ABILITY[a.key] = a end

-- Enemy quirks (shown once revealed).
Combat.QUIRKS = {
    corrode = "Its hits corrode your armor (-1 defense each, up to -3).",
    evasive = "Hard to pin down: 30% of attacks miss until you Appraise it.",
    frenzy = "Below half HP it attacks twice.",
    armored = "Thick plating: +3 defense. Relic Hand ignores it.",
    bind = "Its tendrils can Bind you (20%): you lose your next action.",
    -- region 2
    mend = "It repairs itself a little at the start of each of its turns. Hit hard and fast.",
    burrow = "It digs in every few turns. While BURROWED your attacks hit dirt; Relic Hand, Ram and Breaker still reach it, and Ram or Breaker drags it out.",
    -- region 3
    fuse = "Pressure builds: every third turn it winds up a burst (double damage). Ram, Blink or Breaker answer it.",
    siphon = "Its hits drain 1 Charge (2 on a heavy blow). Spend Charge before it does.",
}

-- Rosters by region (SEALED). A region without its own roster uses the nearest one before it, scaled up.
Combat.ROSTER = {
    [1] = {
        { name = "Rust Crawler", sprite = "rust_crawler", quirk = "corrode", hp = 1.0, atk = 1.0 },
        { name = "Static Wisp", sprite = "static_wisp", quirk = "evasive", hp = 0.8, atk = 1.1 },
        { name = "Scrap Hound", sprite = "scrap_hound", quirk = "frenzy", hp = 1.1, atk = 0.9 },
        { name = "Chalk Crawler", sprite = "rust_crawler", quirk = "armored", hp = 0.9, atk = 0.9 },
        { name = "Bine Lurker", sprite = "static_wisp", quirk = "bind", hp = 1.0, atk = 1.0 },
    },
    [2] = {  -- Pas-de-Calais & Picardy: fields, canals, pits, marsh
        { name = "Mining Drone", sprite = "mining_drone", quirk = "burrow", hp = 1.1, atk = 1.0 },
        { name = "Caretaker Bot", sprite = "caretaker_bot", quirk = "mend", hp = 1.1, atk = 0.9 },
        { name = "Bodyguard Golem", sprite = "bodyguard_golem", quirk = "armored", hp = 1.0, atk = 0.9 },
        { name = "Harvesting Machine", sprite = "harvesting_machine", quirk = "frenzy", hp = 1.0, atk = 1.0 },
        { name = "Mapping Drone", sprite = "mapping_drone", quirk = "evasive", hp = 0.8, atk = 1.1 },
    },
    [3] = {  -- Champagne & Langres: cellars, vines, presses, spires
        { name = "Demolition Droid", sprite = "demolition_droid", quirk = "fuse", hp = 1.1, atk = 0.9 },
        { name = "Sanitation Droid", sprite = "sanitation_droid", quirk = "siphon", hp = 0.9, atk = 1.0 },
        { name = "Contamination Bot", sprite = "contamination_bot", quirk = "corrode", hp = 1.0, atk = 1.0 },
        { name = "Cultivation Golem", sprite = "cultivation_golem", quirk = "bind", hp = 1.0, atk = 1.0 },
        { name = "Utility Automaton", sprite = "utility_automaton", quirk = "mend", hp = 1.1, atk = 0.9 },
    },
}

-- Guardians by stage (the Dover guardian keeps its scripted rescue on turn 2). quirk is optional;
-- guardians support only on-hit and turn-start quirks (mend, siphon, corrode, bind, evasive), not fuse/burrow/frenzy/armored.
Combat.GUARDIANS = {
    [2] = { name = "Cliffwarden", sprite = "cliffwarden", lv = 5, hp = 80, atk = 8, def = 3, rescue_turn = 2,
            windup = "The Cliffwarden braces its whole weight on the cliff edge.",
            heavy = "The Cliffwarden throws itself forward like a falling cliff!",
            phase2 = "Its chalk shell cracks. It hardens (+2 defense, +1 attack) and Braces: no more knocking it off its feet." },
    [14] = { name = "Drillbit", sprite = "drillbit", lv = 9, hp = 110, atk = 11, def = 3, quirk = "mend",
            windup = "The Drillbit drives its bit deep into the ridge and spins up.",
            heavy = "The Drillbit bores up through the ridge beneath you!",
            phase2 = "Its timbers split. It shores itself up (+2 defense, +1 attack) and Braces." },
    [23] = { name = "Talus", sprite = "talus", lv = 13, hp = 200, atk = 18, def = 6, quirk = "siphon",
            windup = "The Talus draws the old wall's weight into its arm.",
            heavy = "The Talus swings the rampart itself at you!",
            phase2 = "Its stonework cracks. It settles into the wall (+2 defense, +1 attack) and Braces." },
}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

Combat.HEAVY = 2.2  -- guardian wind-up multiplier

-- Breaker: the Grit banked by TRAIN sets, spent in one blow (once per fight).
Combat.BREAKER = { name = "Breaker", min_grit = 3,
    text = "Spend all Grit: a blow that ignores defense, can't miss, and breaks a wind-up. Once per fight." }

-- Player numbers ----------------------------------------------------------------------

function Combat.totals(s) return Game.gearTotals(s) end

function Combat.has(s, ability)
    for _, k in ipairs(s.abilities or {}) do if k == ability then return true end end
    return false
end

local function lowHp(s) return s.hp < Game.maxHp(s.level, s) / 2 end

-- Sublime Retribution: after you're hurt, doubling lasts through your next turn.
local function sublimeOn(f) return (f.sublime_until or -1) >= (f.turn or 0) end

local function debuffCount(f)
    return (f.venom or 0) + (f.ink or 0) + ((f.burn or 0) > 0 and 1 or 0) + ((f.frost or 0) > 0 and 1 or 0)
end

local function streakPct(s, T)
    if (T.sets.vow or 0) >= 4 then return math.min(30, 2 * (s.streak or 0)) end
    return 0
end

local function statTotal(s, T, k) return (s.stats and s.stats[k] or 0) + (T[k] or 0) end

-- Kinesthetics: dodge chance (up to 20%), tempo (a free turn, up to 15%), getting away.
function Combat.kinDodge(s, T) return math.min(20, math.floor(statTotal(s, T, "kin") / 2)) end
function Combat.tempoChance(s, T) return math.min(15, math.floor(statTotal(s, T, "kin") / 2)) end
function Combat.runChance(s, T) return math.min(95, 75 + statTotal(s, T, "kin")) end

function Combat.breakerMin(s) return Game.mightRank(s) >= 8 and 2 or Combat.BREAKER.min_grit end

function Combat.canBreak(s, f)
    return f and not f.broke and (s.grit or 0) >= Combat.breakerMin(s)
end

function Combat.breakerDamage(s, T, f)
    return Combat.attackValue(s, T, f) + (s.grit or 0) * (2 + math.floor(Game.mightRank(s) / 3))
end

function Combat.attackValue(s, T, f)
    local v = 2 + math.floor(s.level / 2) + math.floor(statTotal(s, T, "str") / 2) + (T.atk or 0) + (s.whet or 0)
    if Game.mightRank(s) >= 2 then v = v + 1 end
    if T.uniq.servitude then v = v + 2 * (s.thralls or 0) end
    if T.uniq.vowbound or (T.sets.vow or 0) >= 2 then v = v + math.min(6, math.floor((s.streak or 0) / 3)) end
    if f then v = v + (f.ink or 0) end
    return v
end

function Combat.defenseValue(s, T, f)
    local v = math.floor(statTotal(s, T, "res") / 8) + (T.def or 0)
    if Combat.has(s, "goat") then v = v + 1 + math.floor(statTotal(s, T, "res") / 5) end
    if f then v = v - (f.corrode or 0) end
    return math.max(0, v)
end

function Combat.critChance(s, T)
    return clamp(5 + statTotal(s, T, "acu") + (T.aff.crit or 0), 0, 60)
end

-- Enemies ------------------------------------------------------------------------------

function Combat.regionTier(s)
    local ri = Game.currentRegion and Game.currentRegion(s)
    return ri or 1
end

-- Monster strength follows distance walked, not the player (design rule 7), and climbs
-- smoothly inside a region instead of sitting still for weeks (Picardy alone is 283 km).
-- The curve tracks a typical pace: about level 7 at 45 km, 16 at 316 km, 33 at Rome.
-- Tuned 2026-10-05 against Mike's real gear: about 5 swings and a quarter of HP per fight
-- at stage 4 (3 with a weapon); a full set at the expected level needs about 3.
Combat.MON_HP = 4.0     -- x the old (12 + 4 * lv) HP (2.0 before 2026-10-08)
Combat.MON_ATK = 1.4    -- x the old (2 + 1.5 * lv) attack (1.2 before 2026-10-08)
-- Retuned 2026-10-08 against Mike's day-10 save (level 9, 93 km, 18-0 with ATTACK alone in
-- about 2.6 swings): normal fights now about 5-6 swings and about a third of HP with ATTACK only.
Combat.WINDUP_EVERY = 4   -- a normal enemy winds up on every 4th of its turns (past Kent)
Combat.WINDUP_HEAVY = 1.8 -- its heavy blow
Combat.ELITE_PCT = 12     -- chance a monster past Kent is an Elite
Combat.LOSS_INTEGRITY = 10
Combat.ARMOR_CAP = 0.6  -- armor blocks at most this share of a hit
function Combat.levelAt(km)
    return math.max(2, (1.76 * math.max(0, km)) ^ 0.435)
end
-- Kent stays the tutorial (and Dover's guardian deliberately weak): the multipliers fade
-- in over the first 20 km past the Channel.
function Combat.toughness(km)
    return math.max(0, math.min(1, ((km or 0) - 33) / 20))
end
-- Guardians keep the pre-2026-10-08 multipliers: they were already tuned as the hard fights.
Combat.GUARD_HP, Combat.GUARD_ATK = 2.0, 1.2
function Combat.monsterStats(lv, hpm, atkm, km, guardian)
    local k = Combat.toughness(km)
    local HPX = guardian and Combat.GUARD_HP or Combat.MON_HP
    local ATX = guardian and Combat.GUARD_ATK or Combat.MON_ATK
    return math.floor((12 + 4 * lv) * (1 + (HPX - 1) * k) * (hpm or 1)),
        math.floor((2 + 1.5 * lv) * (1 + (ATX - 1) * k) * (atkm or 1)),
        math.floor(lv / 3)
end

function Combat.newMonster(s, rng)
    local tier = Combat.regionTier(s)
    local rt = tier
    while rt > 1 and not Combat.ROSTER[rt] do rt = rt - 1 end
    local roster = Combat.ROSTER[rt]
    local m = roster[rng(#roster)]
    local km = s.route and s.route.km or 0
    local old = 2 + math.floor(2.5 * (tier - 1))  -- the region's own floor (all of Kent)
    local base = math.max(old, math.floor(old + (Combat.levelAt(km) - old) * Combat.toughness(km) + 0.5))
    -- Kent keeps its old roll (floor to floor+2); past it the roll centres on the curve
    local lv = math.max(1, base + rng(3) - (Combat.toughness(km) > 0 and 2 or 1))
    local hp, atk, def = Combat.monsterStats(lv, m.hp, m.atk, km)
    local past_kent = Combat.toughness(km) > 0
    local elite = past_kent and rng(100) <= Combat.ELITE_PCT
    if elite then
        lv = lv + 2
        hp, atk, def = Combat.monsterStats(lv, m.hp, m.atk, km)
        hp, atk = math.floor(hp * 1.5), math.floor(atk * 1.15)
    end
    local f = { name = (elite and "Elite " or "") .. m.name, sprite = m.sprite, quirk = m.quirk, lv = lv, hp = hp, max = hp,
        atk = atk, def = def + (m.quirk == "armored" and 3 or 0),
        turn = 0, tier = tier, elite = elite or nil,
        windup = (past_kent and m.quirk ~= "fuse" and m.quirk ~= "burrow") or nil }
    Combat.onFightStart(s, f)
    return f
end

function Combat.newGuardian(s, n)
    local g = Combat.GUARDIANS[n]
    -- A guardian stays ahead of the monsters around it: if the distance curve has passed
    -- its design level, its stats grow by the same ratio a monster's would.
    local km = s.route and s.route.km or 0
    local glv = math.max(g.lv, math.floor(g.lv + (Combat.levelAt(km) + 2 - g.lv) * Combat.toughness(km) + 0.5))
    -- (h0, a0: the old unmultiplied stats at its design level, so guardians get the same
    -- HP and attack multipliers as monsters)
    local h0, a0 = Combat.monsterStats(g.lv, 1, 1, 0)
    local h1, a1, d1 = Combat.monsterStats(glv, 1, 1, km, true)
    local ghp = math.floor(g.hp * h1 / h0)
    local f = { name = g.name, sprite = g.sprite, lv = glv, hp = ghp, max = ghp,
        atk = math.floor(g.atk * a1 / a0), def = g.def + math.max(0, d1 - math.floor(g.lv / 3)),
        boss = n, rescue_turn = g.rescue_turn, quirk = g.quirk, turn = 0, phase = 1, tier = Combat.regionTier(s) }
    Combat.onFightStart(s, f)
    return f
end

function Combat.onFightStart(s, f)
    local T = Combat.totals(s)
    if T.uniq.archive then f.revealed = true end
    Combat.resetThralls(s)
end

function Combat.resetThralls(s)
    local today = Game.dayKey(os.time())
    if s.thrall_day ~= today then s.thralls, s.thrall_day = 0, today end
end

function Combat.quirkText(f)
    if f.boss then
        local q = (f.quirk and (f.revealed or f.appraised)) and (" " .. Combat.QUIRKS[f.quirk]) or ""
        return "Guardian. Watch for its wind-up." .. q
    end
    if f.revealed or f.appraised then return Combat.QUIRKS[f.quirk] or "" end
    return "Quirk unknown. Appraise to read it."
end

function Combat.statusLine(f)
    local t = {}
    if f.frost and f.frost > 0 then table.insert(t, "Frosted " .. f.frost) end
    if f.venom and f.venom > 0 then table.insert(t, "Venom x" .. f.venom) end
    if f.burn and f.burn > 0 then table.insert(t, "Burning " .. f.burn) end
    if f.displaced then table.insert(t, "Displaced") end
    if f.fear then table.insert(t, "Feared") end
    if f.burrowed then table.insert(t, "BURROWED") end
    if f.telegraph then table.insert(t, "WINDING UP") end
    return table.concat(t, "  ")
end

function Combat.canResolve(s, f)
    return f and not f.boss and s.level >= (f.lv or 1) + 3
end

-- Your hits ----------------------------------------------------------------------------

local function dealDamage(s, T, f, base, opts, rng, lines)
    opts = opts or {}
    if f.quirk == "evasive" and not (f.appraised or f.revealed) and not opts.sure and rng(100) <= 30 then
        table.insert(lines, "It flickers aside. Miss.")
        return 0
    end
    if f.burrowed and not opts.sure and not opts.unearth then
        table.insert(lines, "It's dug in. Your blow hits dirt.")
        return 0
    end
    if f.burrowed and opts.unearth then
        f.burrowed = false
        table.insert(lines, "You drag it out of the ground.")
    end
    local dmg = base + rng(4) - 1
    local elem = (T.aff.fire or 0) + (T.aff.cold or 0) + (T.aff.acid or 0) + (T.aff.lightning or 0)
    dmg = dmg + elem
    if not f.first_hit then dmg = dmg + (T.aff.first or 0); f.first_hit = true end
    if opts.ability and T.uniq.resonance then dmg = dmg + 3 end
    dmg = dmg + (T.aff.exploit or 0) * debuffCount(f)
    if (T.sets.serpent or 0) >= 4 then dmg = dmg + 2 * (f.venom or 0) end
    local mult = 1 + streakPct(s, T) / 100
    if lowHp(s) then mult = mult + (T.aff.bleedout or 0) / 100 end
    if f.frost and f.frost > 0 then mult = mult + (T.aff.shatter or 0) / 100 end
    if f.appraised then mult = mult + 0.25 end
    if T.uniq.oiled and s.hp >= Game.maxHp(s.level, s) then mult = mult + 0.2 end
    if f.frost and f.frost > 0 then
        if T.kind == "crush" then mult = mult + 0.25 elseif T.kind == "slash" or (T.aff.fire or 0) > 0 then mult = mult - 0.15 end
    end
    if f.rebound then mult = mult + 0.25; f.rebound = false end
    if opts.mult then mult = mult * opts.mult end
    local crit = f.crit_next or rng(100) <= Combat.critChance(s, T)
    f.crit_next = false
    if crit then mult = mult * 1.5 end
    local def = opts.pierce and 0 or (f.def or 0)
    dmg = math.max(1, math.floor(dmg * mult) - def)
    f.hp = f.hp - dmg
    table.insert(lines, (opts.verb or "You hit") .. " for " .. dmg .. (crit and " (critical)" or "") .. ".")
    -- on-hit affixes
    local ls = (T.aff.lifesteal or 0) + (T.aff.bloodprice or 0)
    if lowHp(s) and (T.aff.bloodprice or 0) > 0 then ls = ls * 2 end
    if sublimeOn(f) then ls = ls * 2 end
    local heal = math.floor(dmg * ls / 100)
    if T.uniq.harvest then heal = heal + ((f.frost and f.frost > 0) and 4 or 2) end
    if heal > 0 then
        local maxhp = Game.maxHp(s.level, s)
        local before = s.hp
        s.hp = math.min(maxhp, s.hp + heal)
        if s.hp > before then table.insert(lines, "+" .. (s.hp - before) .. " HP.") end
    end
    local extra = T.aff.stack2 or 0
    local vcap = (T.sets.serpent or 0) >= 4 and 8 or 5
    if T.uniq.venom then f.venom = math.min(vcap, (f.venom or 0) + 1 + extra) end
    if T.uniq.ink then f.ink = math.min(5, (f.ink or 0) + 1 + extra) end
    local frost_turns = (T.sets.rime or 0) >= 2 and 3 or 2
    if T.uniq.hoarfrost or (T.sets.rime or 0) >= 4 then f.frost = frost_turns
    elseif (T.aff.chill or 0) > 0 and rng(100) <= T.aff.chill then f.frost = math.max(f.frost or 0, frost_turns - 1) end
    if T.uniq.tracers then f.burn = 2 end
    return dmg
end

-- Enemy turn ---------------------------------------------------------------------------

local function counter(s, T, f, rng, lines)
    if (T.aff.counter or 0) > 0 and f.hp > 0 then
        local lines2 = {}
        dealDamage(s, T, f, math.floor(Combat.attackValue(s, T, f) * T.aff.counter / 100), { verb = "You answer" }, rng, lines2)
        for _, l in ipairs(lines2) do table.insert(lines, l) end
    end
end

local function enemyHit(s, T, f, mult, rng, lines, label)
    if f.hp <= 0 then return end  -- already dead (thorns, counter, burn)
    if f.dodge then
        f.dodge = false
        table.insert(lines, "You blink aside. It hits empty air.")
        if T.uniq.rebound then f.rebound = true end
        counter(s, T, f, rng, lines)
        return
    end
    local dc = math.min(40, (T.aff.dodge or 0) + Combat.kinDodge(s, T))
    if dc > 0 and rng(100) <= dc then
        table.insert(lines, "You slip the blow.")
        if T.uniq.rebound then f.rebound = true end
        counter(s, T, f, rng, lines)
        return
    end
    local atk = f.atk - (f.venom or 0)
    local dmg = atk + rng(3) - 2
    if f.frost and f.frost > 0 then dmg = math.floor(dmg * 0.7) end
    dmg = math.floor(dmg * (mult or 1))
    -- armor takes a flat amount off, but past Kent never more than ARMOR_CAP of the hit
    local cap = 1 - (1 - Combat.ARMOR_CAP) * Combat.toughness(s.route and s.route.km)
    dmg = math.max(dmg - Combat.defenseValue(s, T, f), math.floor(dmg * (1 - cap)))
    dmg = math.floor(dmg * (1 - math.min(40, T.aff.guard or 0) / 100))
    if f.you_braced then dmg = math.floor(dmg / 2); f.you_braced = false end
    dmg = math.max(1, dmg)
    s.hp = s.hp - dmg
    if label and label:match("[%.!]$") then
        table.insert(lines, label .. " It hits you for " .. dmg .. ".")
    else
        table.insert(lines, (label or (f.name .. " hits you")) .. " for " .. dmg .. ".")
    end
    -- quirks on hit
    if f.quirk == "corrode" then f.corrode = math.min(3, (f.corrode or 0) + 1) end
    if f.quirk == "siphon" and (s.charge or 0) > 0 then
        local d = math.min(s.charge, (mult or 1) > 1 and 2 or 1)
        s.charge = s.charge - d
        table.insert(lines, "It siphons " .. d .. " Charge.")
    end
    if f.quirk == "bind" and not Combat.has(s, "goat") and not T.uniq.bridgeguard and rng(100) <= 20 then
        f.bound = true
        table.insert(lines, "Tendrils Bind you.")
    end
    -- when-hurt affixes
    local th = (T.aff.thorns or 0) + (lowHp(s) and (T.aff.spite or 0) or 0)
    if sublimeOn(f) then th = th * 2 end
    local back = math.floor(dmg * th / 100) + (T.aff.retaliate or 0)
    if T.uniq.retribution then back = back + 3 + math.floor(statTotal(s, T, "res") / 3) end
    if back > 0 and s.hp > 0 then
        f.hp = f.hp - back
        table.insert(lines, "It takes " .. back .. " back.")
    end
    if T.uniq.sublime then f.sublime_until = (f.turn or 0) + 1 end
    if (T.aff.brace or 0) > 0 and rng(100) <= T.aff.brace then
        f.you_braced = true
        table.insert(lines, "You Brace.")
        if T.uniq.rebound then f.rebound = true end
    end
    if T.uniq.wraiths and s.hp > 0 and s.hp < Game.maxHp(s.level, s) / 2 and rng(100) <= 30 then
        f.fear = true
        table.insert(lines, "Blood wraiths shriek. It is Feared.")
    end
end

local function enemyTurn(s, T, f, rng, lines)
    f.turn = (f.turn or 0) + 1
    if f.burn and f.burn > 0 then
        f.hp = f.hp - 2; f.burn = f.burn - 1
        table.insert(lines, "Tracers burn it for 2.")
        if f.hp <= 0 then return end
    end
    if f.quirk == "mend" and f.hp < f.max and not f.displaced and not f.fear then
        local heal = math.min(f.max - f.hp, math.max(2, math.floor(f.max * 0.06)))
        f.hp = f.hp + heal
        table.insert(lines, f.name .. " repairs itself (+" .. heal .. ").")
    end
    if f.boss and f.turn == f.rescue_turn and not f.rescued then
        f.rescued = true
        f.telegraph, f.displaced, f.fear = false, false, false
        Game.emit(s, "rescue:" .. f.boss)
        table.insert(lines, "✦ UNSCHEDULED INTERVENTION. " .. f.name .. "'s braced arm gives way. It loses its turn.")
        return
    end
    if f.displaced and f.braced then
        f.displaced = false
        table.insert(lines, f.name .. " is Braced and holds its footing.")
    end
    -- (turn % 3 == 1 so it never lands on a guardian's wind-up turn)
    local T4rime = (T.sets.rime or 0) >= 4 and f.frost and f.frost > 0 and f.turn % 3 == 1
    if T4rime and not f.displaced and not f.fear then
        table.insert(lines, f.name .. "'s frozen joints lock. It loses its turn.")
        if f.telegraph then table.insert(lines, "Its wind-up is broken.") end
        f.telegraph = false
    elseif f.displaced or f.fear then
        table.insert(lines, f.name .. (f.displaced and " is off its footing" or " cowers") .. " and loses its turn.")
        if f.telegraph then table.insert(lines, "Its wind-up is broken.") end
        f.displaced, f.fear, f.telegraph = false, false, false
    elseif f.boss then
        local g = Combat.GUARDIANS[f.boss]
        if f.telegraph then
            f.telegraph = false
            enemyHit(s, T, f, Combat.HEAVY, rng, lines, g.heavy)
        elseif f.turn % 3 == 0 then
            f.telegraph = true
            table.insert(lines, g.windup .. " (Next turn: a heavy blow.)")
        else
            enemyHit(s, T, f, 1, rng, lines)
        end
    elseif f.quirk == "fuse" and f.telegraph then
        f.telegraph = false
        enemyHit(s, T, f, 2, rng, lines, f.name .. " bursts!")
    elseif f.quirk == "fuse" and f.turn % 3 == 0 then
        f.telegraph = true
        table.insert(lines, f.name .. " hisses as pressure builds. (Next turn: a burst.)")
    elseif f.quirk == "burrow" and f.burrowed then
        f.burrowed = false
        enemyHit(s, T, f, 1.5, rng, lines, f.name .. " erupts from below!")
    elseif f.quirk == "burrow" and f.turn % 3 == 2 then
        f.burrowed = true
        table.insert(lines, f.name .. " digs into the ground.")
    elseif f.windup and f.telegraph then
        f.telegraph = false
        enemyHit(s, T, f, Combat.WINDUP_HEAVY, rng, lines, f.name .. " lands its heavy blow!")
    elseif f.windup and f.turn % Combat.WINDUP_EVERY == Combat.WINDUP_EVERY - 1 then
        f.telegraph = true
        table.insert(lines, f.name .. " gathers itself. (Next turn: a heavy blow.)")
    else
        enemyHit(s, T, f, 1, rng, lines)
        if f.quirk == "frenzy" and f.hp > 0 and f.hp < f.max / 2 and s.hp > 0 then enemyHit(s, T, f, 1, rng, lines, f.name .. " snaps again") end
    end
    if f.frost and f.frost > 0 then f.frost = f.frost - 1 end
    if f.brace_next then f.braced, f.brace_next = true, nil end
end

-- Outcomes -----------------------------------------------------------------------------

function Combat.win(s, f, rng)
    Game.tally(s, "wins")
    if f.boss then Game.tally(s, "guardian_wins") end
    local T = Combat.totals(s)
    s.fight = nil
    s.whet = 0
    if s.hp < 1 then s.hp = 1 end
    local out = { "Defeated " .. f.name .. "." }
    if (T.aff.shatter or 0) > 0 and f.frost and f.frost > 0 then
        s.hp = math.min(Game.maxHp(s.level, s), s.hp + 5)
        table.insert(out, "It shatters. +5 HP.")
    end
    if f.boss then
        s.route.guardians[f.boss] = true
        Game.emit(s, "guardian_beaten:" .. f.boss)
    end
    local dust = (1 + rng(2)) * (f.elite and 2 or 1)
    s.inv.dust = (s.inv.dust or 0) + dust
    local xp = (5 + (f.lv or 1)) * (f.elite and 2 or 1)
    s.xp = s.xp + xp
    Game.levelUps(s)
    table.insert(out, "+" .. dust .. " dust, +" .. xp .. " XP.")
    if (T.aff.killcharge or 0) > 0 then
        s.charge = math.min(Game.maxCharge(s.level, s), s.charge + T.aff.killcharge)
        table.insert(out, "+" .. T.aff.killcharge .. " Charge.")
    end
    if T.uniq.servitude and (s.thralls or 0) < 3 then
        s.thralls = (s.thralls or 0) + 1
        table.insert(out, "A bone thrall rises (" .. s.thralls .. ").")
    end
    -- region ingredients: sometimes a monster was carrying something local
    local local_ings = Game.regionIngredients(f.tier or 1)
    if #local_ings > 0 and rng(100) <= 25 then
        local k = local_ings[rng(#local_ings)]
        Game.gainIngredient(s, k, 1)
        table.insert(out, "+1 " .. Game.ingLabel(k):lower() .. ".")
    end
    local drop = f.boss or f.elite or rng(100) <= (f.appraised and 40 or 30)
    if drop then
        local item = Gear.roll(rng, f.tier or 1, { min_rarity = f.boss and 3 or (f.elite and 2) or 1,
            luck = ((f.appraised or f.elite) and 0.5 or 0) + ((f.appraised and f.elite) and 0.25 or 0) })
        local _, gone = Game.addItem(s, item)
        table.insert(out, "Loot: " .. item.name .. " (" .. Gear.RARITY[item.rarity].name .. ").")
        if gone then table.insert(out, "Pack full: " .. gone.name .. " salvaged to dust.") end
    end
    local msg = table.concat(out, " ")
    Game.say(s, msg)
    return msg
end

local function lose(s, f, lines)
    Game.tally(s, "losses")
    s.hp = 1
    s.fight = nil
    s.integrity = math.max(0, (s.integrity or 100) - Combat.LOSS_INTEGRITY)
    local msg = "You go down and crawl away from " .. f.name .. ". Integrity -" .. Combat.LOSS_INTEGRITY .. "%. Eat or drink before the next fight."
    table.insert(lines, msg)
    Game.say(s, msg)
end

-- action: attack | ability:<key> | item | run | resolve
function Combat.act(s, action, rng)
    rng = rng or math.random
    local f = s.fight
    if not f then return "No fight." end
    local T = Combat.totals(s)
    local lines = {}
    if action == "run" then
        if f.boss or Combat.has(s, "goat") or rng(100) <= Combat.runChance(s, T) then
            s.fight = nil
            Game.tally(s, "runs")
            return "You get away. " .. f.name .. " heals. Nothing lost."
        end
        table.insert(lines, "You can't shake it.")
    elseif action == "resolve" then
        if not Combat.canResolve(s, f) then return "Too close a match to resolve." end
        Game.tally(s, "resolved")
        return "Over in a moment. " .. Combat.win(s, f, rng)
    elseif f.bound then
        f.bound = false
        lines.struggled = true
        table.insert(lines, "You struggle free of the Bind.")
    elseif action == "attack" then
        dealDamage(s, T, f, Combat.attackValue(s, T, f), {}, rng, lines)
        if f.hp > 0 and not f.burrowed and (T.aff.twin or 0) > 0 and rng(100) <= math.min(50, T.aff.twin) then
            dealDamage(s, T, f, Combat.attackValue(s, T, f), { verb = "Twin strike" }, rng, lines)
        end
    elseif action == "breaker" then
        if f.broke then return "Breaker is spent for this fight." end
        if not Combat.canBreak(s, f) then return "Not enough Grit (need " .. Combat.breakerMin(s) .. "). TRAIN to bank it." end
        local spent = s.grit
        local base = Combat.breakerDamage(s, T, f)
        s.grit, f.broke = 0, true
        dealDamage(s, T, f, base, { pierce = true, sure = true, unearth = true, ability = true, verb = "BREAKER (" .. spent .. " Grit)" }, rng, lines)
        if f.telegraph and f.hp > 0 then
            f.telegraph = false
            f.displaced = true   -- staggered: loses its turn (a Braced guardian still loses the heavy blow)
            table.insert(lines, "Its wind-up is broken.")
        end
    elseif action == "item" or action:sub(1, 5) == "item:" then
        local m
        if action == "item" then m = Game.drinkPotion(s)
        else m = Game.useBattleItem(s, action:sub(6)) end
        if not m then return "You don't have that." end
        table.insert(lines, m .. ".")
    elseif action:sub(1, 8) == "ability:" then
        local key = action:sub(9)
        local a = Combat.ABILITY[key]
        if not a or a.passive or not Combat.has(s, key) then return "You don't have that ability." end
        local cost = Combat.cost(s, T, key)
        if s.charge < cost then return "Not enough Charge (need " .. cost .. ")." end
        s.charge = s.charge - cost
        if key == "hand" then
            dealDamage(s, T, f, 3 + statTotal(s, T, "acu"), { pierce = true, sure = true, ability = true, verb = "Relic Hand strikes" }, rng, lines)
        elseif key == "blink" then
            f.dodge, f.crit_next = true, true
            table.insert(lines, "You fold a step of space around you.")
        elseif key == "ram" then
            local rm = Game.mightRank(s) >= 6 and 1.75 or 1.5
            dealDamage(s, T, f, Combat.attackValue(s, T, f), { mult = rm, ability = true, unearth = true, verb = "You ram it" }, rng, lines)
            f.displaced = true
        elseif key == "appraise" then
            f.appraised = true
            local gq = (f.boss and f.quirk) and (" " .. Combat.QUIRKS[f.quirk]) or ""
            table.insert(lines, "Appraised: " .. (f.boss and ("a guardian; it telegraphs its heavy blows." .. gq) or Combat.QUIRKS[f.quirk]))
        elseif key == "vow" then
            local bonus = math.min(20, 2 * (s.streak or 0))
            dealDamage(s, T, f, Combat.attackValue(s, T, f) + bonus, { ability = true, verb = "Vow Strike lands" }, rng, lines)
        end
    else
        return "Unknown action."
    end
    if f.hp <= 0 then
        table.insert(lines, Combat.win(s, f, rng))
        return table.concat(lines, " ")
    end
    if f.boss and f.phase == 1 and f.hp <= f.max / 2 then
        f.phase = 2
        local g = Combat.GUARDIANS[f.boss]
        f.def, f.atk = f.def + 2, f.atk + 1
        f.brace_next = true   -- phase 2: Braces from its next turn (a Ram that caused the crack still lands)
        table.insert(lines, g.phase2)
    end
    local tempo = Combat.tempoChance(s, T)
    -- (no tempo roll when the enemy is already staggered: that would be two free turns)
    if action:sub(1, 4) ~= "item" and action ~= "run" and not lines.struggled and not f.displaced and not f.fear
        and tempo > 0 and rng(100) <= tempo then
        table.insert(lines, "Quick feet: you move again before it recovers.")
    else
        enemyTurn(s, T, f, rng, lines)
    end
    -- Might rank 4: Second Wind
    local maxhp = Game.maxHp(s.level, s)
    if f.hp > 0 and s.hp > 0 and s.hp < maxhp / 3 and Game.mightRank(s) >= 4 and not f.second_wind then
        f.second_wind = true
        local heal = math.floor(maxhp / 4)
        s.hp = math.min(maxhp, s.hp + heal)
        table.insert(lines, "Second Wind: +" .. heal .. " HP.")
    end
    if f.hp <= 0 then
        table.insert(lines, Combat.win(s, f, rng))
    elseif s.hp <= 0 then
        lose(s, f, lines)
    end
    return table.concat(lines, " ")
end

function Combat.cost(s, T, key)
    local a = Combat.ABILITY[key]
    local c = a.cost or 0
    if key == "vow" and (T.sets.vow or 0) >= 2 then c = math.max(1, c - 1) end
    return c
end

function Combat.pickAbilities(s, a, b)
    if a == b or not Combat.ABILITY[a] or not Combat.ABILITY[b] then return false end
    s.abilities = { a, b }
    return true
end

return Combat
