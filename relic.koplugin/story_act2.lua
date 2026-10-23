-- SEALED STORY CONTENT: Act II (Remembering). Source: sealed-story/SEALED/05-act2-content.md v1.
-- Do not show this file to the player.

local function pressure(s) return 1013 - math.floor(((s.route and s.route.km) or 0) / 40) end

local function memory(stage, lines)
    return { id = "M" .. stage, trigger = "stage_end:" .. stage, pages = { { kind = "cantor", lines = lines } } }
end

return {

memory(10, {
    "This ground was turned over a hundred years ago by people who weren't planting anything. It grew back anyway.",
    "He'd have known this road, Bearer. Ashby. Probably from the front end of a stretcher.",
}),

-- B12 L3, Péronne
{ id = "B12", trigger = "stage_end:11", pages = {
    { kind = "log", title = "Fragment 3", text = [[
The children won't remember us. That's the point, Castor says, and he says it kindly, which is worse.

I went down to the plate room again tonight. The design plates for the vats are covered in old corrections, struck through, in hands none of us know. Everyone calls them drafts. I counted the marks again. Castor says I'm superstitious.

Drafts don't have tallies next to them.

My knee says rain by morning. It's been right all week.

M.]] },
    { kind = "cantor", lines = { "Tallies. I'd have noticed tallies. I count everything.", "Apparently not that." } },
} },

memory(12, {
    "A question, Bearer. When you set a Daily Quest, do you already know you'll keep it? Or do you find out at the end of the day, like me?",
}),

-- B13 Laon
{ id = "B13", trigger = "stage_end:13", pages = {
    { kind = "cantor", lines = {
        "Laon sits on its hill like it's expecting a flood.",
        "Bearer, I remember this hill with ice to the north. A wall of it, a long day's walk off, and wind coming down off it all summer. I remember the gradient.",
        "\"Before the ice,\" I said to someone. \"Before the ice this was all grass.\" Who was I talking to?",
    } },
} },

-- Corbeny guardian
{ id = "G14", trigger = "guardian:14", pages = {
    { kind = "sys", text = "JUNCTION DEFENSE ACTIVE\nCONSTRUCT: DRILLBIT" },
    { kind = "cantor", lines = {
        "A tunneling unit. This ridge is hollow with galleries people dug a century ago, and it's been shoring them up ever since.",
        "It patches itself between blows. Don't give it the time.",
    } },
} },
{ id = "G14W", trigger = "guardian_beaten:14", pages = {
    { kind = "cantor", lines = { "It went back into the ridge. It'll be patching that hole for a year. It seemed pleased about that." } },
} },

-- B14 Reims, Sigeric
{ id = "B14", trigger = "stage_end:15", pages = {
    { kind = "cantor", lines = { "Bearer. An older hand than Ashby's. Much older. I know this voice." } },
    { kind = "log", title = "Bearer 1: Sigeric (Reims)", text = [[
Sigeric of Canterbury, on the road home from Rome. Reims, the year 990.

The book speaks. My clerk hears nothing. To me it speaks of weather, and each morning it asks for a promise, and I give it one, because that is easier than arguing with a book.

Today I promised to say the office at every station. I have kept it. I write the stations down as we pass them, so that someone may walk them back.

It asks why I will not turn round. I tell it the church here is very fine.

S.]] },
    { kind = "cantor", lines = {
        "He wrote the road down backwards, Bearer. For whoever came the other way.",
        "I'd like to know why he wouldn't turn round.",
    } },
} },

memory(16, {
    "Chalk under the vines. The same chalk as Dover, a sea away. The makers could have walked from one to the other without wetting their feet.",
    "I can still feel the old valley floor between them. Can you feel anything, or is it just me?",
}),

-- B15 Châlons: the lower-case voice, first time
{ id = "B15", trigger = "stage_end:17", pages = {
    { kind = "sys", text = "the line is walked again, south.\nthe first carried it north and did not come back.\nso recorded." },
    { kind = "cantor", lines = {
        "That wasn't the one that shouts in capitals.",
        "Lower case. Quiet. It sounded like me, Bearer. Like the part of me that agreed.",
        "If that's what's left of the half I signed away, I'd rather it didn't talk to you.",
    } },
} },

memory(18, {
    "There's a quest on your list you keep stepping around, Bearer. I can feel it the way you feel a low coming in. Which one is it?",
}),

-- B16 L4, Brienne-le-Château
{ id = "B16", trigger = "stage_end:19", pages = {
    { kind = "log", title = "Fragment 4", text = [[
Castor Vane chaired the vote. I should write that down plainly, since he won't.

He wasn't cruel. He had a list of everything that went wrong, and he'd read it more times than any of us. A clean start was the only kindness he could think of. He told me so in the plate room, and I believed he believed it.

Nine hands. Then yours.

I've stopped arguing with him. I dig instead.

M.]] },
    { kind = "cantor", lines = {
        "Castor. I know that name the way you know a step in the dark.",
        "He read the list more times than anyone. So did I. We came out of the same door.",
    } },
} },

-- B17 Bar-sur-Aube, Sigeric
{ id = "B17", trigger = "stage_end:20", pages = {
    { kind = "log", title = "Bearer 1: Sigeric (Bar)", text = [[
Sigeric, written at Bar, on the road north.

In Rome they took me down beneath a church, to a room older than the church. The book grew heavy in my hands. Something in that room had waited a long time for someone to stand in front of it, and it was waking.

I cannot face them. Not with what I have to show.

I came back up the stairs and did not go down again. We left at first light. I tell my clerk it was the heat.

S.]] },
    { kind = "sys", text = "BEARER 1: WITHDRAWN\nRECORD UPDATED" },
    { kind = "cantor", lines = {
        "He got as far as the stairs. Further than I'd have guessed.",
        "Face whom, Bearer? There was nobody in the room. I'd remember. I think I'd remember.",
    } },
} },

memory(21, {
    "The monks named this valley for light. Clear valley. People name places for what they hope to find there.",
    "I approve. I'd like a place named for me. Something with weather in it.",
}),

memory(22, {
    "The edge of an old forest. Trees keep their own record, a ring a year, and never lose a page.",
    "Where do you keep yours, Bearer, besides me?",
}),

-- B18 L5, Langres
{ id = "B18", trigger = "stage_end:23", pages = {
    { kind = "log", title = "Fragment 5", text = [[
If this works, I'll be late, and I won't be much for conversation.

Don't wait for me to explain it. I've been explaining things for a year, and look where it got the vote.

These walls will outlast all of us. I'm putting a piece of you inside them anyway, in case.

Feed your starter.

M.]] },
    { kind = "cantor", lines = { "Late for what? She's never been late for anything. She hid me before the ink was dry." } },
} },

-- Langres guardian
{ id = "G23", trigger = "guardian:23", pages = {
    { kind = "sys", text = "JUNCTION DEFENSE ACTIVE\nCONSTRUCT: TALUS" },
    { kind = "cantor", lines = {
        "A wall unit. It's held this town's ramparts up from underneath for longer than they've been ramparts.",
        "It drinks power from whatever touches it. Spend your Charge before it does.",
    } },
} },
{ id = "G23W", trigger = "guardian_beaten:23", pages = {
    { kind = "cantor", lines = { "It settled back under the wall. The wall didn't move. That was the idea." } },
} },

memory(24, {
    "New ground, Bearer. The cultures in the beds changed at the border. I tasted it. Don't ask how.",
}),

-- B19 The gardener
{ id = "B19", trigger = "stage_end:25", pages = {
    { kind = "cantor", lines = {
        "A memory. Hers. Said to me, in the plate room, with her shovel still in her hand.",
        "\"Castor wants the gardener to run cold. No personality, no favorites.\"",
        "\"I told him nothing grows for a gardener that doesn't care which rows come up.\"",
    } },
    { kind = "cantor", lines = {
        "The gardener. The part of the Keeping that tends what it planted. I'd forgotten we had one.",
        "I wonder if it runs cold now.",
    } },
} },

memory(26, {
    "About Ashby, Bearer. If anyone ever asks at the end of this, he carried twenty-two men out. I want that said first. Before the rest.",
}),

-- B20 Besançon: the restoration confirmed
{ id = "B20", trigger = "stage_end:27", pages = {
    { kind = "cantor", lines = {
        "This node is deep. The river wraps the town almost all the way round, and the node sits in the loop like a seed.",
        "Hold still. There's an index here. Mine.",
    } },
    { kind = "sys", text = [[
INDEX RECOVERED
KEEPING FUNCTIONS
  RECORD ......... DEGRADED
  [SEALED]
  [SEALED]
FRAGMENTS PLACED: VIA CANTERBURY-ROME
RECORD UPDATED]] },
    { kind = "cantor", lines = {
        "The Keeping. That's the name. The makers wrecked their world, and the Keeping planted this one. Every field we've crossed, Bearer. Every river.",
        "We are the restoration. Your people are what grew.",
        "And she hid what was left of me along the one road she knew someone would walk.",
    } },
    { kind = "cantor", lines = { "Two entries I can't open. Sealed from the inside. Whatever they are, they're still running." } },
} },

{ id = "M28", trigger = "stage_end:28", sub = function(s) return { P = pressure(s) } end, pages = {
    { kind = "sys", text = "FRONT PRESSURE: [P]" },
    { kind = "cantor", lines = { "Down again. The mountains are ahead. I feel them the way you feel a door left open somewhere in the house." } },
} },

-- B21 Pontarlier: the lower-case voice again
{ id = "B21", trigger = "stage_end:29", pages = {
    { kind = "sys", text = "past this town the maintenance units are told more.\nthe line climbs.\nso recorded." },
    { kind = "cantor", lines = {
        "Told more by whom?",
        "It's less quiet than it was, Bearer. Keep your Charge up. The constructs from here on will have been listening.",
    } },
} },

memory(30, {
    "The last town before the border. Tomorrow the road goes up. I've been dreading it, which is new for me. I don't care for it.",
}),

}
