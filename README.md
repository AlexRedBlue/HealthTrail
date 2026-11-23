# Health Trail

A World of Warcraft Forever Addon.

A lingering **"health lost"** trail for nameplates. When a mob takes damage, its health bar drops instantly, but the chunk it just lost stays visible as a pale bar for a moment, then drains away smoothly, a classic fighting-game health bar effect.

## Features

*   **Works with any nameplate addon.** Plater, Platynator, Threat Plates and Blizzard's default nameplates are supported directly; most other nameplate addons are detected automatically.
*   **Your current health is always accurate.** Only the trail lingers; the real health bar updates instantly.
*   **Health ticks.** Thin half-height and thick full-height vertical lines on the filled part of the health bar make it easy to read how much health a target has left: every 100 / 1,000 health on players and normal mobs, every 1,000 / 10,000 on elites, and every 10,000 / 100,000 on bosses. In the options window, each mob type's thick-line spacing can be set to 10%, 25%, 50%, 200%, 400% or 1000% of the default, or any whole number, and the gap between thick lines can be split into 10, 4 or 2 thin lines.
*   **Options window and minimap button.** Change the linger time, colours, tick spacing and how many tick lines each bar gets, without typing commands.
*   **Lightweight.** No libraries.

## Usage

Install and play - no setup needed. To change settings, left-click the minimap button, type `/healthtrail`, or find Health Trail in the game's AddOns settings.

Minimap button: **left-click** opens options, **right-click** toggles health ticks, **drag** moves it around the minimap.

*   `/healthtrail` - open the options window
*   `/healthtrail 1.2` - set how many seconds the lost chunk holds before draining (0–5, saved between sessions)
*   `/healthtrail ticks` - turn the health tick lines on or off (or `/healthtrail ticks on` / `off`)
*   `/healthtrail minimap` - show or hide the minimap button
*   `/healthtrail help` - list commands

## Notes

*   The trail replaces the health bar's background, so the empty part of the bar shows a dark background with the trail on top.
*   Under sustained damage the trail steps down once per linger interval so it never falls too far behind.

## Something not working?

If the trail is missing or misplaced with a particular nameplate addon, leave a comment naming the addon and I'll add support for it.
