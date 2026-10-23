-- SEALED: skill catalog. Skills appear the first time a quest of that kind is done.
-- Keywords are matched against quest titles (lower case, whole or partial words).
return {
    { key = "endurance", name = "Endurance", words = { "workout", "gym", "run", "walk", "lift", "bike", "cycle", "swim", "yoga", "hike", "stretch", "pushup", "push-up", "squat", "cardio", "training", "exercise", "steps" } },
    { key = "hearth",    name = "Hearthcraft", words = { "cook", "dinner", "lunch", "breakfast", "dish", "laundry", "clean", "vacuum", "grocer", "trash", "dog", "kitchen", "tidy", "bake", "meal" } },
    { key = "envoy",     name = "Envoy", words = { "client", "call", "meeting", "email", "proposal", "sales", "pitch", "follow up", "follow-up", "reply", "invoice", "contract", "demo" } },
    { key = "scribe",    name = "Scribe", words = { "write", "blog", "post", "draft", "article", "doc", "edit", "outline", "newsletter", "journal" } },
    { key = "scholar",   name = "Scholar", words = { "read", "study", "learn", "research", "course", "lesson", "practice", "book" } },
    { key = "artificer", name = "Artificer", words = { "fix", "repair", "build", "install", "wood", "tool", "truck", "garden", "yard", "mow", "paint", "assemble" } },
    { key = "steward",   name = "Stewardship", words = { "plan", "budget", "tax", "bill", "pay", "organize", "schedule", "admin", "file", "bank", "review", "sort" } },
    -- Might grows only from TRAIN sets (no quest words).
    { key = "might",     name = "Might", words = {}, train_only = true },
    -- Focus grows only from Meditate sessions.
    { key = "focus",     name = "Focus", words = {}, train_only = true },
    { key = "kinship",   name = "Kinship", words = { "wife", "son", "daughter", "kid", "family", "friend", "mom", "dad", "date", "visit", "birthday" } },
}
