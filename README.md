# Relic

Relic turns a jailbroken Kindle into a quest log. Your to-dos become quests. Finishing them earns XP, levels and ranks, and the game around them keeps going for months:

- a Daily Directive with a streak
- baking: combine ingredients, find recipes
- a walk along a real pilgrim road (the Via Francigena, Canterbury to Rome, 1,862 km at real scale)
- fights, gear, and a story that opens up as you go

Gold earned from quests can't be spent in the game. It unlocks real-world rewards you set yourself ("Bandsaw $200"), and you buy them with your own money when you get there.

It's a KOReader plugin and runs offline on e-ink. The map and loot rewards need a free Todoist account and a phone (see [SETUP.md](SETUP.md)).

| Console theme (default) | Beam Me Up theme |
|---|---|
| ![Quest list, Console theme](screenshots/console-quests.png) | ![Quest list, Beam Me Up theme](screenshots/beam-quests.png) |
| ![Map, Console theme](screenshots/console-map.png) | ![Map, Beam Me Up theme](screenshots/beam-map.png) |

Screenshots from the KOReader desktop emulator at Paperwhite 2 size. Switch themes under MENU > Theme.

New to it? **[HOW-TO-PLAY.md](HOW-TO-PLAY.md)** covers the basics in five minutes.

## Quick install

Already running KOReader? Copy the `relic.koplugin` folder into `koreader/plugins/` on the Kindle and restart KOReader. Relic opens on its own.

Starting from a stock Kindle: **[SETUP.md](SETUP.md)** covers the jailbreak, KOReader, Relic and the optional phone sync.

## Status

Version 42. A personal project, shared with friends. Built for and tested on a **Kindle Paperwhite 2** (758 x 1024) with KOReader v2026.07.1. Other Kindles that run KOReader may work, but the layout hasn't been checked on them. If something looks wrong on yours, a screenshot helps.

Issues are welcome. This is a personal project, so pull requests may sit.

## Updates

Relic updates itself. Once a day, when Wi-Fi is on, it fetches `relic.koplugin/manifest.lua` from this repo's `main` branch over raw.githubusercontent.com (no account, no token). If the version is newer, it downloads every file the manifest lists, checks each one's size and SHA-256, and only then swaps the new folder in. The previous version is kept: Tools > Relic > **Roll back last update** puts it back and holds the bad version. Updates never touch your save.

- **Turn it off:** create `koreader/settings/relic_config.lua` containing `return { public_repo = "" }`.
- **Follow a fork instead:** `return { public_repo = "you/your-fork" }`.
- **Know this:** KOReader doesn't verify HTTPS certificates. The SHA-256 list comes over the same connection as the files, so on an untrusted network someone could in principle serve a fake update. If that matters to you, turn updates off and install by hand.

## What it touches

- **Lock screen:** Relic draws its own (today's quests and stats) and replaces the Kindle's screensaver, including the ads on Special Offers Kindles.
- **Files:** its save and settings live in `koreader/settings/` (`relic_*.lua`, `relic_chronicle.tsv`). Updates work in `koreader/relic_update/`.
- **Todoist (optional):** if you add a token, it's stored in plain text in `koreader/settings/relic_config.lua`. Relic reads tasks from your Relic project and writes save backups, play history and a status note there. Nothing is sent anywhere else.

## Spoilers

The story ships inside the plugin (`relic.koplugin/story_act*.lua`). Reading those files reads ahead.

## What's here

- `relic.koplugin/`: the plugin. This is the only folder the Kindle needs.
- `tools/tests/`: logic tests (LuaJIT, no KOReader needed). From `relic.koplugin/`: `for t in ../tools/tests/test_*.lua; do luajit $t || echo FAIL $t; done`
- `tools/make_manifest.py`: rebuilds the manifest the updater checks. Run `--bump` on every plugin change if you run a fork.
- `tools/gear_art/`, `tools/sprites/`: art pipelines.
- `tools/steps_shortcut/`: an iPhone Shortcut that sends daily step counts through Todoist.

## License

MIT, see [LICENSE](LICENSE). Bundled fonts keep their own licenses (SIL Open Font License; see `relic.koplugin/fonts/`). Gear engravings are public domain (Viollet-le-Duc, via Wikimedia Commons).
