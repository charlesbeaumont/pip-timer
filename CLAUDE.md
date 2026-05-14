# Rut Timer — agent notes

## What this is

Single-user macOS menu-bar app. Counts up elapsed time since the last reset. Shows a colored dot (green → amber → red) so the user notices when it's been a while and should stand up. Left-click resets; right-click opens a small settings menu. That's the whole product.

The point is **ambient**: it never interrupts, never notifies, never modals. If you find yourself adding any kind of alert or popup, you've drifted out of scope.

## Project layout

```
project.yml                  XcodeGen spec — single source of truth for the Xcode project
Sources/
  main.swift                 entry point
  AppDelegate.swift          status item, menu, wake handler, launch-at-login, display rendering
  TimerController.swift      elapsed time, persistence, color logic
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
  xcrun -sdk macosx swiftc -typecheck Sources/main.swift Sources/AppDelegate.swift Sources/TimerController.swift
  ```
- Full build: `open RutTimer.xcodeproj` in Xcode, ⌘R.
- There are no tests. Behavior is verified by running the app and watching the menu bar.

## Hard constraints

- **macOS 13+ only.** Free to use `SMAppService`, `NSWorkspace.didWakeNotification`, modern AppKit.
- **AppKit `NSStatusItem`**, not SwiftUI `MenuBarExtra` — `MenuBarExtra` can't cleanly distinguish left vs right click.
- **No external dependencies at runtime.** Foundation + AppKit + ServiceManagement only. XcodeGen is a build-time tool, not shipped.
- **Universal binary** (`ARCHS_STANDARD`, `ONLY_ACTIVE_ARCH = NO`).
- **No Dock icon, no main window.** `LSUIElement = true` in Info.plist; `NSApp.setActivationPolicy(.accessory)` in `main.swift`.
- **~150–250 lines of Swift.** Currently around 210. If you're heading well past 250 you've overdesigned something; step back.

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

- **Click routing** uses `button.sendAction(on: [.leftMouseUp, .rightMouseUp])` + inspecting `NSApp.currentEvent`. On right-click we temporarily assign `statusItem.menu = menu`, call `performClick(nil)`, then clear `statusItem.menu` so the menu only appears on right-click. Tried-and-tested pattern; don't replace with an embedded custom `NSView` (baseline alignment in the status bar gets weird).
- **Dot rendering** uses `NSImage(systemSymbolName: "circle.fill", ...)` with `NSImage.SymbolConfiguration(paletteColors: [state.color])` for tinting. `image.isTemplate = false` so the palette color survives. The image is placed via `button.imagePosition = .imageLeading` + `button.imageHugsTitle = true`, with the time in `button.title`. We previously tried a "●" character in an `NSAttributedString` — works, but the SF Symbol approach is more conventional and Barbee/Bartender/Ice play nicer with it.
- **Time rendering** uses `NSFont.monospacedDigitSystemFont(...)` assigned to `button.font`. Without it the digits jitter horizontally each second.
- **Tick timer** must be added to `RunLoop.main` in `.common` mode — otherwise the display freezes while a menu is open.
- **Persistence**: we store `startTime` (a `Date`) in `UserDefaults`, not elapsed seconds. That way the timer naturally keeps counting across quit/relaunch. The wake-from-sleep handler explicitly resets `startTime` to now.
- **Launch at Login**: `SMAppService.mainApp` (macOS 13+). Stateless API — `register()` / `unregister()` / read `.status`. For the registration to survive reboots reliably, the app needs to be in `/Applications`. README documents this.
- **Menu bar manager compatibility**: the status item sets `autosaveName = "RutTimerStatusItem"` (unique key — avoids colliding with the generic `Item-0` slot that macOS Tahoe's Control Center caches as hidden), `isVisible = true` explicitly, plus an accessibility label, tooltip, and SF-Symbol `accessibilityDescription` of "Rut Timer" so managers like Barbee can identify the item. **None of these are decorative — drop them and the item gets parked off-screen at x≈-8578 in the system's hidden zone.**

## When making changes

- Prefer editing existing files. There are only three Swift files; new ones are almost certainly unnecessary.
- After editing `project.yml`, regenerate the `.xcodeproj`.
- After non-trivial Swift edits, run the typecheck command above before claiming done — it's free and catches API drift.
- Don't add comments explaining what the code does. The identifiers are clear. Comments only for genuinely surprising "why" (a couple of those notes live above — keep them, don't multiply them).
