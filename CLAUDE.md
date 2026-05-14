# Rut Timer — agent notes

## What this is

Single-user macOS menu-bar app, two features sharing one menu bar item:

1. **Standup signal** — colored dot (green → amber → red) + elapsed time since last reset. Ambient nudge to stand up.
2. **Time tracker** — four fixed categories (Maker / Manager / Reactive / Learning). Click the menu bar item, pick a category, it starts tracking. Pick another to switch. Pick "Stop tracking" to pause. Sessions are written as plain markdown to `Daily/TimeTracking/YYYY-MM-DD.md` inside Charles's Second Brain (iCloud Octarine vault).

The point is **ambient**: it never interrupts, never notifies, never modals. If you find yourself adding any kind of alert or popup, you've drifted out of scope.

## Category definitions (source of truth)

When in doubt about which category a session is, fall back to these definitions. They're meaningful, not arbitrary — the whole point of having categories is to expose where time leaks (Reactive is usually 2–3× what people guess).

- **Maker** — building, writing, designing, sketching, deep solo work that produces an artifact. Strategy docs, code, decks, mockups, drafting messages that take real thought.
- **Manager** — 1:1s, team meetings, coaching, reviews, hiring, planning sessions with others.
- **Reactive** — Slack catch-up, email triage, ad-hoc threads, async reviews, quick replies. The "inbox" bucket.
- **Learning** — deliberate reading, watching, courses, exploratory research with intent to grow. Not Slack-as-reading.

## Project layout

```
project.yml                  XcodeGen spec — single source of truth for the Xcode project
Sources/
  main.swift                 entry point
  AppDelegate.swift          status item, menu, click routing, sleep/wake, image rendering, idle notifications
  TimerController.swift      standup state — elapsed time, persistence, color logic
  Category.swift             WorkCategory enum: maker/manager/reactive/learning + color per category
  TimeTracker.swift          active session, persistence, sleep/quit finalization, markdown writer, 30s min, configurable vault, last-category memory
  TimeAggregator.swift       parse Daily/TimeTracking/*.md, sum per category for day/week/month
  IdleWatcher.swift          polls CGEventSource.secondsSinceLastEventType every 30s while tracking; fires onIdleCrossed/onIdleCleared callbacks
  Info.plist                 LSUIElement=true, bundle metadata
README.md                    user-facing build/run instructions
```

The `.xcodeproj` is **generated** by XcodeGen, so it is gitignored. Regenerate after editing `project.yml`:

```bash
xcodegen generate
```

## Build / verify

- Syntax + type check from CLI (no full Xcode needed):
  ```bash
  xcrun -sdk macosx swiftc -typecheck Sources/*.swift
  ```
- Full build: `xcodegen generate && xcodebuild -project RutTimer.xcodeproj -scheme RutTimer build`, or open the project in Xcode and ⌘R.
- After adding/removing source files, **regenerate the project with `xcodegen generate`** — the `.xcodeproj` is gitignored.
- There are no tests. Behavior is verified by running the app and watching the menu bar (and the markdown log file).

## Hard constraints

- **macOS 13+ only.** Free to use `SMAppService`, `NSWorkspace.didWakeNotification`, modern AppKit.
- **AppKit `NSStatusItem`**, not SwiftUI `MenuBarExtra` — `MenuBarExtra` can't cleanly distinguish left vs right click.
- **No external dependencies at runtime.** Foundation + AppKit + ServiceManagement only. XcodeGen is a build-time tool, not shipped.
- **Universal binary** (`ARCHS_STANDARD`, `ONLY_ACTIVE_ARCH = NO`).
- **No Dock icon, no main window.** `LSUIElement = true` in Info.plist; `NSApp.setActivationPolicy(.accessory)` in `main.swift`.
- **~850–900 lines of Swift total.** Currently ~874. v1 (standup-only) was 213; v2 (basic tracker) was ~550; v2.1–v2.3 (idle, menu reorg, dot rendering) bumped it. If you're heading past 1100 something's wrong. AppDelegate is the heavy file at ~465 — if it grows much more, split out display rendering (`StatusItemRenderer.swift`) or notification handling (`IdlePromptCoordinator.swift`).

## Out of scope — do not add

- Notifications, sounds, alerts, banners of any kind
- Activity / idle detection
- Statistics, history, CSV export
- Pomodoro modes, work hours, DND integration
- Multiple presets, keyboard shortcuts, URL schemes
- Onboarding, tooltips, welcome dialogs
- Any persistent window

The app is invisible except for the menu bar item. Keep it that way.

## Architectural notes worth remembering

- **Click routing**: left or right click both open the menu (v2 change — switching work modes is the primary action, so it has to be one click away). Uses `button.sendAction(on: [.leftMouseUp, .rightMouseUp])` + the `statusItem.menu = menu; performClick(nil); statusItem.menu = nil` dance so we control when the menu shows. Don't replace with an embedded custom `NSView` (baseline alignment in the status bar gets weird).
- **Dot rendering** uses `NSImage(systemSymbolName: "circle.fill", ...)` with `NSImage.SymbolConfiguration(paletteColors: [state.color])` for tinting. `image.isTemplate = false` so the palette color survives. The image is placed via `button.imagePosition = .imageLeading` + `button.imageHugsTitle = true`, with the time in `button.title`. We previously tried a "●" character in an `NSAttributedString` — works, but the SF Symbol approach is more conventional and Barbee/Bartender/Ice play nicer with it.
- **Time rendering** uses `NSFont.monospacedDigitSystemFont(...)` assigned to `button.font`. Without it the digits jitter horizontally each second.
- **Tick timer** must be added to `RunLoop.main` in `.common` mode — otherwise the display freezes while a menu is open.
- **Persistence (standup)**: we store `startTime` (a `Date`) in `UserDefaults`, not elapsed seconds. That way the timer naturally keeps counting across quit/relaunch. The wake-from-sleep handler explicitly resets `startTime` to now.
- **Persistence (tracker)**: active session is in `UserDefaults` for crash safety, but on launch we **always discard** it and start paused. Reconstructing what happened during downtime would mean guessing — better to lose the orphan session than fabricate one. Completed sessions are the markdown file; that's the source of truth.
- **Sleep behavior for tracker**: `NSWorkspace.willSleepNotification` calls `tracker.stop()`. Closing the lid finalizes the active session at sleep time. Without this, sleeping with Maker active would leave a 12-hour ghost entry.
- **Quit behavior**: `applicationWillTerminate` also calls `tracker.stop()` so menu → Quit cleanly finalizes. `kill -9` will leak the active session (discarded on next launch — see above).
- **Midnight rollover**: `TimeTracker.finalize` recursively splits a session that crosses midnight, writing the start portion to today's file and the rest to tomorrow's. Rare but correct.
- **Launch at Login**: `SMAppService.mainApp` (macOS 13+). Stateless API — `register()` / `unregister()` / read `.status`. For the registration to survive reboots reliably, the app needs to be in `/Applications`. README documents this.
- **Menu bar manager compatibility**: the status item sets `autosaveName = "RutTimerStatusItem"` (unique key — avoids colliding with the generic `Item-0` slot that macOS Tahoe's Control Center caches as hidden), `isVisible = true` explicitly, plus an accessibility label, tooltip, and SF-Symbol `accessibilityDescription` of "Rut Timer" so managers like Barbee can identify the item. **None of these are decorative — drop them and the item gets parked off-screen at x≈-8578 in the system's hidden zone.**
- **Markdown format**: the file has `## Sessions` (append-only line per session) and `## Totals` (rewritten from sessions on every write). `TimeAggregator.parseSessions` is the parser; both `TimeTracker.rewriteTotals` and `TimeAggregator.totalsFor*` use it. Keep that contract stable — if you change the line format, update the parser at the same time and test against an existing day's file.
- **Vault path**: defaults to the iCloud Octarine path but configurable via Configure → Output directory… (`NSOpenPanel`). `TimeTracker.vaultRoot` reads from UserDefaults key `vaultRoot` with the iCloud path as fallback. Both `TimeTracker` (writer) and `TimeAggregator` (reader) consult the same source of truth.
- **30-second minimum session**: `TimeTracker.finalize` drops sessions shorter than `minimumSessionSeconds = 30`. Accidental category clicks shouldn't pollute the log. Don't make this configurable — 30s is short enough not to lose real work and long enough to catch mis-clicks.
- **Display style**: `DisplayStyle.current` reads from UserDefaults (`displayStyle` key), defaults to `ringDot`. The two renderers (`twoDotsImage`, `ringDotImage`) are static on `AppDelegate`. They draw filled circles via `NSBezierPath` into an `NSImage(size:)` with `lockFocus`/`unlockFocus`. Don't `setTemplate(true)` — palette colors won't render if it's a template image.
- **Category colors**: `WorkCategory.color` returns `systemBlue/Purple/Pink/Teal`. Chosen to be distinct from the standup palette (green/amber/red) — if you change one, check it doesn't collide.
- **Idle detection**: `IdleWatcher` polls every 30s while a session is active. Uses `CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)` — `UInt32.max` is `kCGAnyInputEventType` and means "any input". AppDelegate wires `onIdleCrossed`/`onIdleCleared` callbacks to send/dismiss a `UNUserNotification` with three action buttons. The user must set System Settings → Notifications → Rut Timer → **Alerts** for the popup to persist (banner style auto-dismisses). Banner style is harmless but the user might miss it.
- **Notification category & actions**: `categoryIdentifier = "RUT_IDLE"`, three actions `STOP_AT_IDLE` / `CONTINUE` / `STOP_AND_RESUME`. `customDismissAction` is set on the category so explicit dismissals fire the delegate too (we treat as Continue).
- **Last-used category**: `TimeTracker.lastCategory` is read from UserDefaults (`lastCategory` key). Written on every successful `start(_:)`. Used by the "Start Tracker (X)" Actions menu item. Discarded sessions (30s rule) still update it — that's intentional, since you genuinely intended that category.
- **Menu shape**: four sections in order — **Actions** (Start/Stop, Reset Timer), **Tracking** (categories + totals + open log), **Configure** (Launch at Login, idle threshold, display style, output dir, About), and a bottom row (Interval submenu, Quit). Section headers are disabled `NSMenuItem`s with small-caps secondary-color attributedTitle. The standup interval is intentionally at the very bottom — it's rarely touched.

## When making changes

- Prefer editing existing files. There are only three Swift files; new ones are almost certainly unnecessary.
- After editing `project.yml`, regenerate the `.xcodeproj`.
- After non-trivial Swift edits, run the typecheck command above before claiming done — it's free and catches API drift.
- Don't add comments explaining what the code does. The identifiers are clear. Comments only for genuinely surprising "why" (a couple of those notes live above — keep them, don't multiply them).
