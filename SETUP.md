# Setting up Relic

About an hour the first time, most of it the jailbreak. You need the Kindle, a computer and a USB cable. Todoist is optional.

## 1. Jailbreak the Kindle

There's no single method: it depends on the model and the exact firmware version (Settings > Device Options > Device Info). Use the model tables and guides at **[kindlemodding.org](https://kindlemodding.org)** to pick the right one, then follow its post-jailbreak steps: hotfix, KUAL and MRPI.

Keep Wi-Fi off (airplane mode) until step 2 is done. An Amazon update can undo the jailbreak.

## 2. Block Amazon updates

Relic uses Wi-Fi to update itself, so Wi-Fi has to be safe. Follow kindlemodding.org's update-blocking step for your method. (Some methods block updates already; the guide says which.)

## 3. Install KOReader

Install the KOReader package for your Kindle from the [KOReader releases](https://github.com/koreader/koreader/releases) (kindlemodding.org says which package fits your model and firmware; some jailbreaks install it through KPM instead). Launch it once from KUAL to check it runs, then exit it.

## 4. Install Relic

1. Download this repo (Code > Download ZIP) and unzip it.
2. Exit KOReader on the Kindle (it blocks USB file transfer while running) and plug the Kindle into the computer.
3. Copy the `relic.koplugin` folder into `koreader/plugins/` on the Kindle. The folder name must stay `relic.koplugin`.
4. Eject, open KUAL, launch KOReader.

Relic opens on its own whenever KOReader starts. It's also under Tools > Relic, and you can bind "Open Relic" to a gesture.

The opening plays the first time. Some screens wait for a long press on NEXT (about 3 seconds) instead of a tap.

## 5. Updates

Nothing to set up. Once a day, when Wi-Fi is on, Relic checks this repo for a newer version, verifies every file and asks to restart. Tools > Relic has **Check for updates** and **Roll back last update**. Updates never touch your save (`koreader/settings/relic_state.lua`).

## 6. Optional: phone sync through Todoist

With a Todoist account, Relic can pull quests you add on your phone and back up your save every day.

1. In Todoist, create a project named **Relic**.
2. Copy your API token (Todoist web: Settings > Integrations > Developer).
3. On the Kindle, create `koreader/settings/relic_config.lua`:
   ```lua
   return { todoist_token = "paste-your-token-here" }
   ```
4. Restart KOReader.

Then, whenever the Kindle is on Wi-Fi:
- Tasks in the Relic project become quests and are closed in Todoist. Labels or @words in the title: `@minor` `@standard` `@major` `@epic` (size), `@daily`, `@main`, `@dread` (pays double), `@loot` with a price for a reward ("Kettlebell $35"). The description, one line per step, becomes a checklist. Recurring tasks ("every weekday") become repeating quests.
- Relic keeps its own tasks in that project: `Relic save 1..7`, `Relic chronicle YYYY-MM` and `Relic status`, all marked "don't complete". Leave them alone; they're your backups and play history. Restore a backup from Tools > Relic.

Everything goes to your own Todoist. Nothing is sent anywhere else.

Don't add a `github_token` to the config. That switches the updater to a private repo.

## Good to know

- **Lock screen:** Relic draws its own lock screen (today's quests and stats) and replaces the Kindle's screensaver, including the ads on Special Offers Kindles.
- **Offline is normal.** Relic runs without Wi-Fi for days and catches up when it connects.
- **If something breaks:** `koreader/crash.log` on the Kindle has the details. Tools > Relic > Roll back last update puts the previous version back.

## For developers

- Game rules live in pure Lua modules (`game.lua`, `combat.lua`, `gear.lua`, ...). Screens are in `main.lua` and `console.lua`.
- Tests, from `relic.koplugin/`: `for t in ../tools/tests/test_*.lua; do luajit $t || echo FAIL $t; done`
- Running a fork: bump the manifest with `python3 tools/make_manifest.py --bump` on every plugin change, and point your Kindle at your fork with `public_repo = "you/your-fork"` in `relic_config.lua`.
