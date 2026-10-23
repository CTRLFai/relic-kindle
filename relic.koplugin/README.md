# Relic prototype (KOReader plugin)

A plain, unstyled prototype to test whether the game loop works on a Kindle Paperwhite 2.
Tested in the KOReader v2026.07.1 desktop emulator at PW2 resolution (758 x 1024, 212 dpi).

## What's in it
- **Quests:** add (title + size). Tap a quest to open it: checklist steps (add, check, edit, move, remove), OPTIONS, COMPLETE. Steps pay up to half the quest's XP as you go; the rest on completion. Hold a quest for options: Daily Quest, skill, Main Quest, rename, waiting, dread (pays double), delete
- **Daily Quest:** streak, shields, integrity damage after a 7-day grace period
- **Bake:** put any two ingredients in a barrel (second barrel at level 3). 13 hidden recipes plus failures; a journal keeps finds and hints; Fine versions are 1.5x. Quests drop ingredients by skill type. Pantry: tap an item to use it
- **Explore:** flip a card for 1 Range (steps logged by hand for now); salvage, forage, or a monster
- **Combat:** classic handheld-style battle screen (enemy and HP bar top, you bottom, text box, 2x2 menu: Attack, Spark, Potion, Run); losing just retreats. Sprites in `sprites/` are original placeholders
- **Story:** scenes play when you hit story moments (first boot, kept or missed Daily Quests, Main Quests, route stages, the Dover guardian). Reread recovered logs from STATUS > LOGS. Hold a quest to mark it as a Main Quest
- **Character:** stats (Strength, Resistance, Focus, Acuity) grow each level; skills are earned by quest type (hold a quest to change its skill); the Footing seed ability ranks up with kept days. All on STATUS
- **Unlocks:** baking day 0, map day 10, combat day 21
- **MENU** (bottom right): pull quests from phone, back to KOReader, or the Kindle home screen
- **Phone inbox:** tasks in the Todoist project "Relic" are pulled in when Relic opens or Wi-Fi connects (and from MENU). Labels or @words: @daily @main @minor @standard @major @epic @dread. Description lines and Todoist subtasks become checklist steps. Imported tasks are closed in Todoist
- Saves after every action to `koreader/settings/relic_state.lua`
- Opens automatically when KOReader starts. Also under Tools > Relic, and bindable to a gesture ("Open Relic")

## Install on the Kindle
1. **Jailbreak.** Use the Jailbreak Wizard at kindlemodding.org to confirm the method for PW2 on 5.12.2.2. WatchThis is documented for this model and **erases the device**. One public write-up used WinterBreak2 on this exact model and firmware.
2. **Hotfix, KUAL and MRPI**, per the wizard's post-jailbreak steps.
3. **Block Amazon updates** so Wi-Fi is safe (Relic needs Wi-Fi to update itself). On 5.12: install the renameotabin extension and run it from KUAL ("Rename OTA Binaries", then "Rename"). Skip this if you jailbroke with WinterBreak, which already blocks updates.
4. **KOReader:** download `koreader-kindlepw2-v2026.07.1.zip` from the KOReader GitHub releases and unzip it to the Kindle's root.
5. **Relic:** copy this `relic.koplugin` folder into `koreader/plugins/` on the Kindle. The folder name must stay `relic.koplugin`.
6. **Config (optional):** `koreader/settings/relic_config.lua` holds a Todoist token for phone sync. Mike's own Kindle also has a GitHub token there, which makes it follow the private dev repo; without one, Relic updates from the public repo (see SETUP.md at the repo root).
7. Eject, open KUAL, launch KOReader. Relic opens on its own.

Notes:
- KOReader blocks USB file transfer while it's running. Exit KOReader before copying files.
- Only turn Wi-Fi on after step 3, or an Amazon update can undo the jailbreak.
- On the Kindle, text entry uses KOReader's on-screen keyboard. The emulator used a physical keyboard.

## Updates
- Once a day, when Wi-Fi is on, Relic checks GitHub (the private repo with a token in the config, otherwise the public repo `CTRLFai/relic-kindle`). If there's a newer version it downloads it, checks every file, installs it and asks to restart.
- **Tools > Relic** has *Check for updates*, *Roll back last update* (puts the previous version back and skips the bad one) and the installed version number.
- Updates never touch the save (`koreader/settings/relic_state.lua`).

## Files
- `main.lua` - screens and buttons (KOReader widgets)
- `game.lua` - rules, pure Lua; all numbers are placeholders
- `_meta.lua` - plugin name
- `updater.lua` - self-updater
- `story.lua` - story engine (turns game events into scenes, keeps recovered logs)
- `backup.lua` - daily save backup to Todoist (7 rotating tasks "Relic save 1..7"; restore from Tools > Relic)
- `inbox.lua` - phone inbox (Todoist)
- `lockscreen.lua` - lock screen image (Daily Quest, quests, stats, Cantor); overrides the ad lock screen on this Kindle
- `recipes.lua` - recipe book (sealed-ish: discovered by experimenting)
- `skills.lua` - skill catalog (sealed-ish: skills appear when first earned)
- `story_act1.lua` - Act One scenes. **Sealed story content: don't open it if you want to be surprised.**
- `manifest.lua` - version and file list the updater checks (generated by `tools/make_manifest.py`)
