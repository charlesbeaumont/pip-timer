# Pip

A macOS menu-bar app that does two things in one click target:

1. **Ambient standup signal.** A colored ring (green → amber → red) counts up since your last reset, so you notice when it's been a while and should stand up.
2. **Simple time tracker** across four work modes — Maker, Manager, Reactive, Learning. Sessions written to your Second Brain as plain markdown.

No notifications other than the idle prompt, no main window, no Dock icon. Lives entirely in the menu bar.

## Menu bar display

A single composite glyph + elapsed time.

- **Not tracking:** solid filled dot in the standup-state color + standup elapsed.
- **Tracking:** thin colored ring (standup state) with a filled dot inside (category color) + active session elapsed.

The standup color stays as the outer ring at all times so it's always glanceable. The inner dot tells you what mode you're in.

## Standup

- **Green** while elapsed < interval. **Amber** between 1× and 2× interval. **Red** past 2×.
- Default interval 30 minutes. Configurable (10 sec for testing, then 15 / 20 / 25 / 30 / 45 / 60 min).
- Resets automatically when the Mac wakes from sleep.
- Resets automatically after a configurable "break threshold" of inactivity (default 10 min). The idea: if you've been away long enough to count as a real break, the clock should start fresh when you return.

## Time tracking

Four fixed categories:

| Category | Color  | What counts |
|----------|--------|-------------|
| Maker    | Blue   | Building, writing, designing, deep solo work that produces an artifact |
| Manager  | Purple | 1:1s, team meetings, coaching, reviews, planning sessions with others |
| Reactive | Pink   | Slack catch-up, email triage, ad-hoc threads, async reviews |
| Learning | Teal   | Deliberate reading, watching, courses, exploratory research |

Click the menu bar item, pick a category to start. Pick another to switch (finalizes the previous session to markdown). Pick **Stop Tracker** to pause. App starts paused at launch. **Start Tracker (X)** at the top resumes whatever you tracked most recently.

Sessions under 30 seconds are ignored to filter accidental category switches — except when finalized via the idle prompt, which always commits.

## Storage

- Completed sessions append to `Daily/TimeTracking/YYYY-MM-DD.md` inside your Second Brain vault.
- Default vault path: `~/Library/Mobile Documents/iCloud~com~octarine~notes/Documents/Second Brain` (iCloud Octarine).
- Change via Configure → Output directory… (opens a folder picker).
- Each file has `## Sessions` (one line per session) and `## Totals` (rewritten from sessions on each write).
- Today / This week / This month totals appear in the menu, computed by reading the markdown back. The currently-active session is folded into the displayed totals in real time.

## Idle detection

Two independent inactivity thresholds:

**Idle threshold** (default 5 min) — only while tracking. When you stop touching the keyboard/mouse for this long, a notification appears with three actions:
- **Stop at HH:MM** — finalize the session at the time activity actually stopped.
- **Continue tracking** — you were working (reading, on a call); session continues uninterrupted.
- **Stop and resume now** — finalize at idle-start, start a fresh session of the same category at the current time.

**Break threshold** (default 10 min) — runs at all times. When inactivity passes this, the standup timer silently resets — you've effectively taken a break, so the count starts fresh.

The two are separate by design: idle is for tracking accuracy ("was that 30 minutes really me working?"), break is for standup-count accuracy ("did I really sit for 30 minutes straight?"). Both fire from the same poll.

### macOS notification setup

For the idle prompt to stay visible until you click an action, set **System Settings → Notifications → Pip → Alert style → Persistent** (Banners auto-dismiss after a few seconds; Persistent stays). Pip also sets the notification's interruption level to `.timeSensitive` so Focus modes don't suppress it.

## Click model

Left or right click — both open the menu. There are no other primary actions: Reset Timer lives in the menu under Actions.

## Sleep / wake / quit

- **Wake** → standup timer resets.
- **Sleep** → if you're tracking, the session is finalized at sleep time (no 12-hour ghost sessions when you close the lid).
- **Quit** → finalizes the active session cleanly.
- **Hard kill** (`kill -9`) → leaks the active session. On next launch the app discards any orphan and starts paused (no retroactive guessing).

## Build & run

Requirements: macOS 13 Ventura+, Xcode 15+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
open Pip.xcodeproj
```

Then ⌘R in Xcode. No Dock icon — look in the menu bar.

## Signing for personal local use

Defaults to ad-hoc signing so you can build without an Apple Developer account. If Gatekeeper objects to a copy in `/Applications`, either right-click → Open the first time, or sign with a personal Apple ID via Xcode → Signing & Capabilities → Automatically manage signing.

## Launch at Login

Uses `SMAppService.mainApp` (macOS 13+). For this to survive reboots reliably, move `Pip.app` to `/Applications` before toggling Launch at Login on. Confirm under System Settings → General → Login Items.

## Menu bar managers (Bartender, Barbee, Ice, etc.)

Menu bar managers enumerate status items at their own startup, so they only see items running when they launched. If you use one and Pip doesn't appear in its list:

1. Quit the menu bar manager.
2. Make sure Pip is running.
3. Relaunch the manager.

Long-term, enable Launch at Login on Pip so it's always up before the manager starts.

## Files

```
project.yml                                 XcodeGen spec
Sources/
  main.swift                                entry point
  AppDelegate.swift                         lifecycle, display update, menu actions
  AppDelegate+Menu.swift                    menu construction (all the buildMenu plumbing)
  AppDelegate+IdleNotifications.swift       UNUserNotificationCenter setup + delegate
  StatusItemRenderer.swift                  ring/dot drawing + SF Symbol loader
  TimerController.swift                     standup elapsed, color logic, interval
  TimeTracker.swift                         active session, persistence, markdown writer
  TimeAggregator.swift                      parse markdown, sum per category
  IdleWatcher.swift                         polls HIDIdleTime, fires idle + break callbacks
  Category.swift                            WorkCategory enum + color/icon per category
  Defaults.swift                            UserDefaults key constants
  Info.plist                                LSUIElement=true
```

Total Swift: ~1000 lines.
