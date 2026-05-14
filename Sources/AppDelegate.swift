import AppKit
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    let standup = TimerController()
    let tracker = TimeTracker()
    let idleWatcher = IdleWatcher()
    var tick: Timer?
    var menu = NSMenu()
    var idleAtTime: Date?
    var idleNotificationVisible = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "RutTimerStatusItem"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menu.delegate = self
        buildMenu()

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)

        setupNotifications()
        idleWatcher.onIdleCrossed = { [weak self] idle in self?.presentIdleNotification(idleSeconds: idle) }
        // Intentionally no onIdleCleared handler — when the user comes back, the
        // notification needs to STAY VISIBLE so they can decide what to do about
        // the elapsed idle time. The IdleWatcher resets its own latch internally,
        // and we guard against duplicate notifications via idleNotificationVisible.
        idleWatcher.onBreakCrossed = { [weak self] idle in self?.handleBreakDetected(idleSeconds: idle) }
        idleWatcher.start()

        tick = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateDisplay() }
        RunLoop.main.add(tick!, forMode: .common)
        updateDisplay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        tracker.stop()
        idleWatcher.stop()
    }

    @objc private func handleClick(_ sender: Any?) {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func handleWake() {
        standup.reset()
        updateDisplay()
    }

    @objc private func handleSleep() {
        tracker.stop()
        updateDisplay()
    }

    private func handleBreakDetected(idleSeconds: TimeInterval) {
        standup.reset()
        updateDisplay()
    }

    func updateDisplay() {
        guard let button = statusItem.button else { return }
        let standupColor = standup.colorState.color
        let categoryColor = tracker.active?.category.color
        button.image = StatusItemRenderer.ringOutlineImage(standup: standupColor, category: categoryColor)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.setAccessibilityLabel("Rut Timer")
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        if let active = tracker.active {
            let elapsed = Date().timeIntervalSince(active.startTime)
            button.title = " " + TimerController.formatElapsed(elapsed)
            button.toolTip = "Tracking \(active.category.displayName)"
        } else {
            button.title = " " + TimerController.formatElapsed(standup.elapsed)
            button.toolTip = "Rut Timer — open menu to track or reset"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }

    // MARK: - Menu actions

    @objc func menuResetStandup() {
        standup.reset()
        updateDisplay()
    }

    @objc func menuPickInterval(_ sender: NSMenuItem) {
        standup.intervalSeconds = sender.tag
        updateDisplay()
    }

    @objc func menuPickIdleThreshold(_ sender: NSMenuItem) {
        idleWatcher.setThreshold(sender.tag)
        idleWatcher.stop()
        idleWatcher.start()
    }

    @objc func menuPickBreakThreshold(_ sender: NSMenuItem) {
        idleWatcher.setBreakThreshold(sender.tag)
    }

    @objc func menuStartTracking(_ sender: NSMenuItem) {
        let category = WorkCategory.allCases[sender.tag]
        tracker.start(category)
        updateDisplay()
    }

    @objc func menuStartLastCategory() {
        guard tracker.lastCategory != nil else { return }
        tracker.startLastCategory()
        updateDisplay()
    }

    @objc func menuStopTracking() {
        tracker.stop()
        dismissIdleNotification()
        updateDisplay()
    }

    @objc func menuOpenLog() {
        let url = tracker.fileURL(for: Date())
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let header = "# Time Tracking — \(TimeTracker.dayString(Date()))\n\n## Sessions\n\n## Totals\n\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    @objc func menuPickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: TimeTracker.vaultRoot)
        panel.message = "Choose the folder where time tracking files will be saved. The app will write to Daily/TimeTracking/ inside it."
        if panel.runModal() == .OK, let url = panel.url {
            TimeTracker.setVaultRoot(url.path)
        }
    }

    @objc func menuToggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc func menuAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleName"] as? String ?? "Rut Timer"
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let alert = NSAlert()
        alert.messageText = name
        alert.informativeText = "Version \(version)\n\nAmbient standup reminder + simple time tracking across Maker / Manager / Reactive / Learning."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc func menuQuit() {
        NSApp.terminate(nil)
    }
}
