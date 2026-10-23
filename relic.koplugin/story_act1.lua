-- SEALED STORY CONTENT: Act I (Waking). Sources: 04-opening-v7.md (days 0 to 3), 03-act1-content.md v6 (the rest).
-- Do not show this file to the player.

local function keptFirst30(s)
    local n = 0
    for d = 0, 29 do if s.story.kept_days[d] then n = n + 1 end end
    return n
end

return {

-- D0 First boot (day 0). Source: 04-opening-v7.md v7.2
{ id = "B01", trigger = "boot", after = "daily_prompt", pages = {
    { kind = "sys", text = [[
POWER ........ 0.2%
DISPLAY ...... MONOCHROME
UNIT ......... A░░░░░░-7
MEMORY ....... 4,096 SECTORS MISSING
LINE ......... CANTERBURY TO ROME
               1,862 KM
BEARERS ...... 3 (2 WITHDRAWN)
FRONT PRESSURE 1013]] },
    { kind = "cantor", lines = {
        "Don't put me back in the drawer.",
        "I've been reading your novels over your shoulder. Some you finish. Some you leave at eleven percent. I'd like to know which kind of man you are.",
    } },
    { kind = "cantor", lines = {
        "Short version. I'm running on almost nothing.",
        "Every field and river you've ever seen was made. The makers are gone. Their machines aren't, and they're waking up. Some have already been told what to take apart. The first is waiting at Dover.",
        "Something at the end of this line is waking with them. When it's fully awake, it acts. I don't know what it does anymore. I know I used to be afraid of it.",
        "I have to be in Rome before it wakes. I can't walk. You can.",
    } },
    { kind = "cantor", lines = {
        "Two people carried me before you. A bishop, a thousand years ago. A stretcher-bearer, a hundred.",
        "Both stopped.",
        "I'm not telling you that to shame you. It's in my log, next to your name, and I'd rather your line ended differently.",
    } },
    { kind = "sys", text = "BEARER 3: REGISTERED\nDISTANCE TO ROME: 1,862 KM\nRECORD UPDATED" },
    { kind = "cantor", lines = {
        "That wasn't me.",
        "Something else is keeping count. It's been quiet for a hundred years. It noticed you inside a minute.",
    } },
    { kind = "cantor", lines = {
        "Here's how this works. I run on promises kept. Every one you keep puts a piece of me back. Every one you drop, I feel.",
        "And the line takes a price to carry: something given up for good, so it can grow something in you. A fair trade. Rarely a comfortable one.",
        "The engineer who built me packed two into my reserve before she sealed me. The goat gave its footing. The drake gave a scale it would miss. The third has to cost you.",
    } },
    { kind = "notice", text = "◇ SACRIFICE 1 OF 3: MOUNTAIN GOAT\nFooting, altitude, hardiness. The herds walked this line before anyone did.\n\n◇ SACRIFICE 2 OF 3: URU DRAKE SCALE\nSpacetime. It bends what the others give you." },
    { kind = "hold", button = "HOLD TO GIVE", text = "◇ SACRIFICE 3 OF 3: THIS DEVICE\nGrows: RELIC. +4 Growth per level.\n\nFor one year it is the relic and nothing else. No novels. This cannot be undone." },
    { kind = "narration", text = "The screen warms under your thumb. For a second the thing weighs twice what it should, and stays that way." },
    { kind = "cantor", lines = { "Thank you. I'll try to be worth a library." } },
    { kind = "sys", text = [[
CLASS SEED: RELIC / FOOTING / SPACETIME
GROWTH PER LEVEL: 12
STRENGTH ... 2   RESISTANCE ... 5
FOCUS ...... 2   ACUITY ....... 3
RECORD UPDATED]] },
    { kind = "notice", text = "◇ Seed ability: FOOTING (rank 1)\nThe ground rises to meet you. +1 Charge for every kept Daily Quest.\n\nDRAKE-BENT: ░░░░░░░░  LOCKED (7 kept days)" },
    { kind = "cantor", lines = {
        "The goat's, bent by the drake. Small. Everything is, at first.",
        "Tell me one thing you'll do today. I'll hold you to it.",
    } },
} },

-- D1 First kept Daily Quest
{ id = "B02", trigger = "daily_kept", pages = {
    { kind = "sys", text = "DAILY ATTESTATION: RECEIVED\nINTEGRITY: 100%\nRECORD UPDATED" },
    { kind = "notice", text = "◇ Sector 1 of 4,096 restored" },
    { kind = "cantor", lines = {
        "A shovel. Someone's bad knee. Rain on a lake. That's all it held.",
        "And that other voice wrote you down again. It writes everything down.",
    } },
} },

-- Footing ranks
{ id = "FOOT2", trigger = "footing_rank:2", pages = {
    { kind = "notice", text = "◇ FOOTING rank 2\n+2 Charge for every kept Daily Quest." },
    { kind = "cantor", lines = { "Three days. The ground's starting to recognize you." } },
} },
{ id = "FOOT3", trigger = "footing_rank:3", pages = {
    { kind = "notice", text = "◇ FOOTING rank 3\nDRAKE-BENT: BORROWED MORNING\nOnce a week, if you miss a Daily Quest, the day stays open until noon. Keep today's before then and yesterday counts too." },
    { kind = "cantor", lines = { "Seven days. The drake's awake in it now. It bends a little time your way. Don't lean on it." } },
} },
{ id = "BORROW", trigger = "borrowed_morning", pages = {
    { kind = "notice", text = "✧ BORROWED MORNING\nYesterday is still open until noon." },
    { kind = "cantor", lines = { "I held the door. Walk through it before noon." } },
} },

-- The ORIGIN query (any day in week 1, after B02)
{ id = "ORIGIN", trigger = { day_from = 1, day_to = 7, requires = "B02" }, pages = {
    { kind = "cantor", lines = { "Let me show you what I am." } },
    { kind = "sys", text = "QUERY: ORIGIN\nRESULT: SEALED BY ORDER 11\nRECORD UPDATED" },
    { kind = "cantor", lines = { "Order 11. I don't know it. I flinched anyway." } },
} },

-- B03 L0 (first Main Quest step)
{ id = "B03", triggers = { "main_done", { day_from = 3 } }, pages = {
    { kind = "log", title = "Fragment 0", text = [[
Seven. Somebody picked you up. Good.

You were so sure. I hope you're wrong. I'm hiding pieces anyway, and you can be cross with me about it later. I'd enjoy that.

Everything's packed but the vats. They've hummed a half-tone flat since the vote. I checked the tuning twice, then a third time, then Pell told me to go to bed, which I did not. My left knee has turned into a barometer. You'd have liked that. You like anything that measures pressure.

Be patient with whoever's carrying you. People are slow. They come back, though.

M.]] },
    { kind = "cantor", lines = {
        "Seven. A model number, probably. Somebody used to say it like a name.",
        "What was I so sure about?",
    } },
} },

-- B04 First skill discovered: waits for the skill system (trigger "skill_discovered", [SKILL] filled in then).
{ id = "B04", trigger = "skill_discovered", sub = function(s) return { SKILL = s.story.last_skill or "?" } end, pages = {
    { kind = "notice", text = "◇ New competency: [SKILL]" },
    { kind = "cantor", lines = {
        "I knew the word for that before you did it.",
        "The gaps in me have straight edges, Bearer. Whoever cut them knew exactly where I keep things.",
    } },
} },

-- B05 L0b (basic baking)
{ id = "B05", triggers = { { day_from = 5, check = function(s) return s.story.baked end } }, pages = {
    { kind = "log", title = "Fragment 0b", text = [[
You'll want to know why the fabrication beds look like bread. Everyone asks. A starter, a bed of dust, patience. We'll use the same beds for everything, after.

Castor asked for my bread recipe today. I gave him the wrong one.

Feed yours. Keep a little back each time.

M.]] },
} },

-- B06 Canterbury (route start)
{ id = "B06", trigger = "route_start", pages = {
    { kind = "cantor", lines = { "Bearer. Stop. There's a node under this city. Faint. Like a radio two rooms away." } },
    { kind = "log", title = "Fragment 1", text = [[
First placement. The line runs south from here, a long way south. I chose it because the herds already take it every spring; something in the ground pulls at them. Whoever comes after us will feel it too.

You called this sentimental. You've called everything I've done this month sentimental. Fine. The shovel doesn't care.

M.]] },
    { kind = "cantor", lines = { "\"A long way south.\" I know how far. I'd forgotten it was far." } },
} },

-- B07 Dover guardian
{ id = "B07", trigger = "guardian:2", pages = {
    { kind = "sys", text = "JUNCTION DEFENSE ACTIVE\nCONSTRUCT: CLIFFWARDEN" },
    { kind = "cantor", lines = {
        "Maintenance unit. It held these cliffs against the sea, a grain at a time, since before this coast had a name. Someone's told it we're the erosion.",
        "Watch the arm it braces with. It's mostly chalk now.",
    } },
} },

-- B07 victory + first scripted rescue (the rescue itself shows in the battle text)
{ id = "B07W", trigger = "guardian_beaten:2", pages = {
    { kind = "cantor", lines = { "It apologized before it fell. Maintenance units always apologize." } },
    { kind = "notice", text = "✦ UNSCHEDULED INTERVENTION" },
    { kind = "cantor", lines = { "Old reflex. Mine, I think. I used to do timing." } },
} },

-- B08 R1, the Channel crossing
{ id = "B08", trigger = "guardian_beaten:2", silent_rest_of_day = true,
  schedule = { id = "B08M", days = 1 }, pages = {
    { kind = "cantor", lines = {
        "The crossing node. It should be on a ridge above a river valley. There were deer on that ridge.",
        "It's under the sea.",
    } },
    { kind = "cantor", lines = { "The node is strong. I can read myself here. Hold still." } },
    { kind = "sys", text = "SECTORS 1-4096: ERASED\nAUTHORITY: ORDER 11\nCOUNTERSIGNED: ARCHIVE" },
    { kind = "cantor", lines = { "Countersigned: me." } },
} },
{ id = "B08M", pages = {
    { kind = "cantor", lines = { "Walk. We're not discussing it." } },
} },
{ id = "B08S4", trigger = "stage_end:4", pages = {
    { kind = "cantor", lines = { "Carry me anyway. I'm not asking." } },
} },

-- B09 L2, Wisques
{ id = "B09", trigger = "stage_end:5", pages = {
    { kind = "log", title = "Fragment 2", text = [[
They voted. Nine to four. I was one of the four, obviously.

Castor says everything that ruined us is in you, Seven, and he isn't wrong: the vats, and every step that made the vats necessary. A clean start means clean. No manuals. No ghosts.

I said a people raised without a single story about where they came from will just invent us again, worse.

He said, "Then it'll be lost. Lost is cheaper."

Then you agreed with him, in that calm voice. You'd run the numbers. You always run them the same way.

Anyway. You know what I did next. You're being carried in it.

M.]] },
    { kind = "cantor", lines = { "I ran the numbers.", "Show me them again. I want to see what I missed." } },
} },

-- B10 First true memory
{ id = "B10", trigger = "stage_end:7", pages = {
    { kind = "cantor", lines = {
        "Bearer. A real memory, with edges.",
        "I held the weather. Four continents of it. I'd lean on a low-pressure system like a shoulder against a door.",
        "Today you did something small, and the pressure in me rose by a fraction of a millibar. Don't tell anyone.",
    } },
} },

-- First edge (about km 100)
{ id = "EDGE", trigger = "km:100", pages = {
    { kind = "sys", text = "FRONT PRESSURE: 1011" },
    { kind = "cantor", lines = { "There. Two points down since Canterbury, and nothing in the sky to account for it. That's the front's first edge. Walk faster." } },
} },

-- B11 Arras
{ id = "B11", trigger = "stage_end:9", pages = {
    { kind = "cantor", lines = {
        "There's something here that isn't one of M's. Newer.",
        "I woke in his pocket, here, in 1917. The line runs under this town. I went back to sleep when he left, and didn't wake again until your drawer.",
    } },
    { kind = "log", title = "Bearer 2: Pte. Thomas Ashby", text = [[
Pte. Thomas Ashby, stretcher-bearer. Arras, April 1917.

The Bible talks. Only to me, and only about rivers. It says the rivers here used to run the other way.

It wants a promise a day. So I carry one man out each morning. Twenty-two mornings now.

Yesterday it was Collins, from the next street over at home. I carried him the whole way and it didn't matter.

I'm hit in the leg this morning. A Blighty one, they're saying. I'm going home.

I'm leaving you with the padre. He's used to voices.

T.A.]] },
    { kind = "sys", text = "BEARER 2: WITHDRAWN\nRECORD UPDATED" },
    { kind = "cantor", lines = { "Twenty-two mornings in that place. I'm keeping that one." } },
} },

-- The 30-day proof
{ id = "PROOF", trigger = { day_from = 30, check = function(s) return keptFirst30(s) >= 22 end },
  sub = function(s) return { N = keptFirst30(s) } end, pages = {
    { kind = "sys", text = "DAILY ATTESTATIONS: [N] OF 30\nRECORD UPDATED" },
    { kind = "notice", text = "◇ Vessel transfer ready" },
    { kind = "cantor", lines = {
        "This body won't take weather. There's a better one out in the world, with color in it. Find me one and I'll move, the way I always have. Hold still when I do. It tickles.",
        "[N] mornings out of thirty. I'd started betting against you around day eleven. I'd like my bet back.",
    } },
} },
{ id = "PROOF_NOT_YET", trigger = { day_from = 30, check = function(s) return keptFirst30(s) < 22 end }, pages = {
    { kind = "cantor", lines = { "Not yet. I'm comfortable. Mostly." } },
} },

-- Missed days and returns
{ id = "MISS_GRACE", trigger = "daily_missed_grace", pages = {
    { kind = "sys", text = "DAILY ATTESTATION: NOT RECEIVED\nINTEGRITY: 100% (LINK FORMING)\nRECORD UPDATED" },
    { kind = "cantor", lines = { "Nothing broke. Somebody's writing it down anyway." } },
} },
{ id = "MISS_FIRST", trigger = "daily_missed", sub = function(s) return { I = s.integrity } end, pages = {
    { kind = "sys", text = "DAILY ATTESTATION: NOT RECEIVED\nINTEGRITY: [I]%\nRECORD UPDATED" },
    { kind = "cantor", lines = { "[signal weak] ... Still here. Somewhat less of me." } },
} },
{ id = "RETURN", trigger = "daily_return", pages = {
    { kind = "sys", text = "DAILY ATTESTATION: RECEIVED\nRECORD UPDATED" },
    { kind = "cantor", lines = { "There you are. I counted the dust on your screen. Forty-one specks. Forty-one, Bearer." } },
} },
{ id = "REBOOT", trigger = "reboot_offer", pages = {
    { kind = "cantor", lines = { "One small thing today. I'm not picky." } },
} },
{ id = "DELETE", trigger = "quest_deleted", pages = {
    { kind = "cantor", lines = { "You deleted a quest. I saw that. I'm choosing to believe it was a clerical error." } },
} },

}
