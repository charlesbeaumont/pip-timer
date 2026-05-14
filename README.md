# Rut Timer

A tiny macOS menu-bar app that does two things:

1. **Ambient standup signal.** A colored dot (green → amber → red) counts up since your last reset, so you notice when it's been a while and should stand up.
2. **Simple time tracker** across four work modes — Maker, Manager, Reactive, Learning. Sessions written to your Second Brain as plain markdown.

It never interrupts you. No notifications, no full-screen reminders. Just two ambient signals sharing one menu bar item.

## Behavior

**Menu bar display**

Two visual styles, switchable in Configure → Display style:
- **Ring + dot** (default) — single circle. Outer ring = standup state (green/amber/red), inner dot = active category color. When not tracking, just a solid dot.
- **Two dots** — `[●][●] MM:SS` — first dot standup state, second dot category color. When not tracking, just one dot.

Time format: `MM:SS` (or `H:MM:SS` past an hour). When tracking, the time shown is the active session's elapsed; otherwise it's standup elapsed.

**Standup signal**
- **Green** while elapsed < interval. **Amber** between 1× and 2× interval. **Red** past 2× interval.
- Default interval 30 minutes. Configurable in the menu (15/20/25/30/45/60).
- Resets automatically when the Mac wakes from sleep.

**Time tracking — four categories**

| Category | Color  | What counts |
|----------|--------|-------------|
| Maker    | Blue   | Building, writing, designing, deep solo work that produces an artifact |
| Manager  | Purple | 1:1s, team meetings, coaching, reviews, planning sessions with others |
| Reactive | Pink   | Slack catch-up, email triage, ad-hoc threads, async reviews |
| Learning | Teal   | Deliberate reading, watching, courses, exploratory research |

Click the menu bar item to open the menu. Pick a category to start tracking; pick another to switch (previous session is finalized to markdown); pick "Stop Tracker" to pause. The app starts paused at launch. "Start Tracker (Last)" resumes whatever you tracked most recently.

Sessions under 30 seconds are ignored — they're typically accidental category switches and shouldn't pollute the log.

**Storage**
- Completed sessions are appended to `Daily/TimeTracking/YYYY-MM-DD.md` inside your Second Brain vault (default: iCloud Octarine path).
- The file contains a `## Sessions` list and a `## Totals` block per category. The app rewrites totals after each session.
- Today / This week / This month totals are shown in the menu, computed by re-reading the markdown files.
- The output directory is configurable: Configure → Output directory… (opens a folder picker).

**Idle detection**

If you walk away while a session is running, after a configurable threshold (default 5 min, options 3/5/10/15) the app sends a macOS notification with three actions:
- **Stop at HH:MM** — finalize the session at the time activity actually stopped (`HH:MM` is shown).
- **Continue tracking** — you were working (reading, on a call); session continues.
- **Stop and resume now** — finalize at idle-start, restart the same category at the current time. Useful when you stepped away and now you're back.

**Important macOS setup for idle notifications:**
For the popup to stay visible until you click it, set System Settings → Notifications → Rut Timer → **Alerts** (not Banners). With the default Banners style, the notification slides away after a few seconds.

**Click**
- Left or right click → opens the menu. Standup reset is a menu item ("Reset Timer").

**Sleep / wake**
- Wake: standup timer resets.
- Sleep: if you're tracking, the session is finalized at sleep time (no ghost 12-hour sessions when you close the lid).

**Crash recovery**
- A clean Quit finalizes the active session.
- A hard kill (e.g., `kill -9`) leaks the session — on next launch, the app starts paused and the orphan is discarded (no guesswork retroactive writes).

## Build & run

Requirements: macOS 13 Ventura or later, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open RutTimer.xcodeproj
```

Then hit ⌘R in Xcode. The app launches with no Dock icon — look in the menu bar.

## Signing for personal local use

The project defaults to ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`), which lets it run on your own machine without an Apple Developer account.

If macOS Gatekeeper objects when you move the built `.app` to `/Applications`, either:

1. Open it once via right-click → Open in Finder, then click Open in the dialog, or
2. Sign with your free personal Apple ID: in Xcode select the `RutTimer` target → Signing & Capabilities → check "Automatically manage signing" → pick your team.

## Launch at Login

Uses `SMAppService.mainApp` (macOS 13+). For this to survive reboots reliably, move the built `Rut Timer.app` to `/Applications` before toggling Launch at Login on. You can verify the registration under System Settings → General → Login Items.

## Menu bar managers (Bartender, Barbee, Ice, etc.)

Menu bar managers typically enumerate status items via the accessibility API at their own startup, so they only see items that were already running when they launched. If you use one and Rut Timer doesn't appear in its list:

1. Quit the menu bar manager.
2. Make sure Rut Timer is running.
3. Relaunch the menu bar manager.

The cleanest long-term setup is to enable Rut Timer's "Launch at Login" so it's always running before the manager starts.

## Files

- `project.yml` — XcodeGen spec
- `Sources/main.swift` — entry point
- `Sources/AppDelegate.swift` — status item, menu, click routing, sleep/wake handlers, image rendering, idle notification handling
- `Sources/TimerController.swift` — standup state (elapsed, persistence, color logic)
- `Sources/Category.swift` — WorkCategory enum + per-category color
- `Sources/TimeTracker.swift` — active session state, markdown writer, 30s minimum, configurable vault root, last-category memory
- `Sources/TimeAggregator.swift` — read markdown back, sum per-category for day/week/month
- `Sources/IdleWatcher.swift` — polls `CGEventSource.secondsSinceLastEventType` every 30s while tracking
- `Sources/Info.plist` — `LSUIElement = true`, bundle metadata

Total Swift: ~870 lines.
