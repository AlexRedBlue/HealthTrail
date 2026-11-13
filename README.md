# Health Trail

A World of Warcraft Forever Addon.

A lingering **"health lost"** trail for nameplates. When a mob takes damage, its health bar drops instantly, but the chunk it just lost stays visible as a pale bar for a moment, then drains away smoothly, a classic fighting-game health bar effect.

## Features

*   **Works with any nameplate addon.** Plater and Blizzard's default nameplates are supported directly; most other nameplate addons are detected automatically.
*   **Your current health is always accurate.** Only the trail lingers; the real health bar updates instantly.
*   **Lightweight.** No libraries, no configuration window, one small file.

## Usage

Install and play - no setup needed.

*   `/healthtrail` - show the current linger time
*   `/healthtrail 1.2` - set how many seconds the lost chunk holds before draining (0–5, saved between sessions)

## Notes

*   The trail replaces the health bar's background, so the empty part of the bar shows a dark background with the trail on top.
*   Under sustained damage the trail steps down once per linger interval so it never falls too far behind.

## Something not working?

If the trail is missing or misplaced with a particular nameplate addon, leave a comment naming the addon and I'll add support for it.
