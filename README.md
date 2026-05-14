# Rut Timer

A tiny macOS menu-bar app that counts up since your last reset and shows a colored dot — green, amber, red — so you notice when it's time to stand up and move.

It never interrupts you. There are no notifications, no full-screen reminders, no statistics. Just an ambient signal.

## Behavior

- Menu bar shows a small colored dot followed by `MM:SS` (or `H:MM:SS` past one hour).
- **Green** while elapsed < interval. **Amber** between 1× and 2× interval. **Red** past 2× interval.
- **Left-click** → reset to `00:00`.
- **Right-click** → menu: Reset, Interval (15 / 20 / 25 / 30 / 45 / 60 min), Launch at Login, About, Quit.
- **Sleep / wake** → timer resets automatically when the Mac wakes.
- **Quit / relaunch** → timer keeps counting from where it was. `UserDefaults` persists the start timestamp.

Default interval is 30 minutes.

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
- `Sources/AppDelegate.swift` — status item, menu, wake handling, launch-at-login
- `Sources/TimerController.swift` — elapsed-time state, persistence, color logic
- `Sources/Info.plist` — `LSUIElement = true`, bundle metadata

Total Swift: ~210 lines.
