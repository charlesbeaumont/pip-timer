import AppKit
import ServiceManagement
import UserNotifications

enum RecoveryKind {
    case idle, sleep, crash
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    var statusItem: NSStatusItem!
    let standup = TimerController()
    let tracker = TimeTracker()
    let idleWatcher = IdleWatcher()
    var tick: Timer?
    var menu = NSMenu()
    var gapStartTime: Date?
    var recoveryKind: RecoveryKind?
    var idleNotificationVisible = false
    var sleepStartedAt: Date?
    lazy var addEntryWindow: AddEntryWindow = {
        let w = AddEntryWindow()
        w.onAdd = { [weak self] category, start, end in
            self?.tracker.addEntry(category: category, start: start, end: end)
            self?.updateDisplay()
        }
        return w
    }()
    var editEntriesWindow: EditEntriesWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "PipStatusItem"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menu.delegate = self
        buildMenu()

        tracker.onFileWritten = { [weak self] in self?.editEntriesWindow?.reloadIfVisible() }

        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleWake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(handleSleep), name: NSWorkspace.willSleepNotification, object: nil)

        setupNotifications()
        idleWatcher.onIdleCrossed = { [weak self] idle in self?.presentIdleNotification(idleSeconds: idle) }
        // Intentionally no onIdleCleared handler — when the user comes back, the
        // notification needs to STAY VISIBLE so they can decide what to do about
        // the elapsed idle time. The IdleWatcher resets its own latch internally,
        // and we guard against duplicate notifications via idleNotificationVisible.
        idleWatcher.onBreakCrossed = { [weak self] idle in self?.handleBreakDetected(idleSeconds: idle) }
        idleWatcher.onBreakCleared = { [weak self] idle in self?.handleBreakCleared(idleSeconds: idle) }
        idleWatcher.start()

        tick = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateDisplay() }
        RunLoop.main.add(tick!, forMode: .common)
        updateDisplay()

        // Cross-process state sync: when another Pip instance changes state,
        // refresh our in-memory caches and redraw.
        StateSync.observe { [weak self] in
            guard let self = self else { return }
            self.standup.refreshFromDefaults()
            self.tracker.refreshFromDefaults()
            // Idle watcher's poll interval is derived from thresholdSeconds at
            // start time; if another process changed it, restart so we pick up
            // the new interval. The thresholds themselves are read live so no
            // in-memory cache to refresh.
            self.idleWatcher.stop()
            self.idleWatcher.start()
            self.updateDisplay()
        }

        // If we found an orphan active session at launch (unclean previous exit),
        // surface a recovery prompt. Defer slightly so notification authorization
        // has a chance to settle.
        if tracker.pendingRecovery != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.presentCrashRecovery()
            }
        }
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
        NSLog("[Pip.wake] handleWake fired; priorSleep=\(sleepStartedAt?.description ?? "nil")")
        let priorSleep = sleepStartedAt
        sleepStartedAt = nil
        standup.reset()
        if let sleepStart = priorSleep, let active = tracker.active {
            let gap = Date().timeIntervalSince(sleepStart)
            let threshold = TimeInterval(idleWatcher.thresholdSeconds)
            if gap >= threshold {
                presentSleepRecovery(category: active.category, sleepStart: sleepStart)
            }
            // gap < threshold → silently resume; tracker.active was never cleared.
        }
        updateDisplay()
    }

    @objc private func handleSleep() {
        // Don't stop the tracker here — that's the old behavior that lost time
        // on lid-close. Just record when sleep started; handleWake decides
        // whether to silently resume or prompt the user.
        NSLog("[Pip.sleep] handleSleep fired at \(Date())")
        sleepStartedAt = Date()
        updateDisplay()
    }

    private func handleBreakDetected(idleSeconds: TimeInterval) {
        NSLog("[Pip.break] handleBreakDetected idleSeconds=\(Int(idleSeconds))")
        standup.reset()
        updateDisplay()
    }

    private func handleBreakCleared(idleSeconds: TimeInterval) {
        // User returned after being idle past the break threshold. Reset the
        // standup so the ring reflects the current sitting session, not the
        // moment they walked away. Without this the standup would still read
        // (gap minus break-threshold) when they come back.
        NSLog("[Pip.break] handleBreakCleared (user returned), resetting standup")
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
        button.setAccessibilityLabel("Pip")
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        if let active = tracker.active {
            let elapsed = Date().timeIntervalSince(active.startTime)
            button.title = " " + TimerController.formatElapsed(elapsed)
            button.toolTip = "Tracking \(active.category.displayName)"
        } else {
            button.title = " " + TimerController.formatElapsed(standup.elapsed)
            button.toolTip = "Pip — open menu to track or reset"
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }

    // MARK: - Menu actions

    @objc func menuResetStandup() {
        let elapsedBefore = standup.elapsed
        standup.reset()
        tracker.recordReset(at: Date(), elapsedBefore: elapsedBefore)
        updateDisplay()
    }

    @objc func menuAddEntry() {
        addEntryWindow.presentWithDefaults(lastCategory: tracker.lastCategory)
    }

    @objc func menuEditEntries() {
        guard TimeTracker.vaultRoot != nil else {
            let alert = NSAlert()
            alert.messageText = "No output directory configured"
            alert.informativeText = "Choose one via Configure → Output directory…"
            alert.runModal()
            return
        }
        if editEntriesWindow == nil { editEntriesWindow = EditEntriesWindow(tracker: tracker) }
        editEntriesWindow?.present()
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
        editEntriesWindow?.reloadIfVisible()
    }

    @objc func menuStartLastCategory() {
        guard tracker.lastCategory != nil else { return }
        tracker.startLastCategory()
        updateDisplay()
        editEntriesWindow?.reloadIfVisible()
    }

    @objc func menuStopTracking() {
        tracker.stop()
        dismissIdleNotification()
        updateDisplay()
        editEntriesWindow?.reloadIfVisible()
    }

    @objc func menuOpenLog() {
        guard let url = tracker.fileURL(for: Date()) else {
            let alert = NSAlert()
            alert.messageText = "No output directory configured"
            alert.informativeText = "Choose one via Configure → Output directory…"
            alert.runModal()
            return
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            tracker.writeHeader(at: url, for: Date())
        }
        NSWorkspace.shared.open(url)
    }

    @objc func menuPickOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if let root = TimeTracker.vaultRoot {
            panel.directoryURL = URL(fileURLWithPath: root)
        }
        panel.message = "Choose the folder where time tracking files will be saved. Files are written directly into this folder, one per day."
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
        let name = info["CFBundleName"] as? String ?? "Pip"
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
