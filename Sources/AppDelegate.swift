import AppKit
import ServiceManagement
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, UNUserNotificationCenterDelegate {
    private var statusItem: NSStatusItem!
    private let standup = TimerController()
    private let tracker = TimeTracker()
    private let idleWatcher = IdleWatcher()
    private var tick: Timer?
    private var menu = NSMenu()
    private var idleAtTime: Date?

    private let idleCategoryId = "RUT_IDLE"
    private let actionStopAtIdle = "STOP_AT_IDLE"
    private let actionContinue = "CONTINUE"
    private let actionStopAndResume = "STOP_AND_RESUME"
    private var idleNotificationVisible = false

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
        NSLog("[RutTimer] break detected (idle=%.1fs) — resetting standup timer", idleSeconds)
        standup.reset()
        updateDisplay()
    }

    // MARK: - Display

    private func updateDisplay() {
        guard let button = statusItem.button else { return }
        let standupColor = standup.colorState.color
        let categoryColor = tracker.active?.category.color
        let image = Self.ringOutlineImage(standup: standupColor, category: categoryColor)
        button.image = image
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

    private static func ringOutlineImage(standup: NSColor, category: NSColor?) -> NSImage {
        let outer: CGFloat = 14
        let stroke: CGFloat = 2
        let gap: CGFloat = 1.5
        let inner: CGFloat = outer - 2 * stroke - 2 * gap
        let h: CGFloat = 18
        let image = NSImage(size: NSSize(width: outer, height: h))
        image.lockFocus()
        let y = (h - outer) / 2
        if category == nil {
            standup.setFill()
            NSBezierPath(ovalIn: NSRect(x: 0, y: y, width: outer, height: outer)).fill()
        } else {
            let strokeRect = NSRect(x: stroke / 2, y: y + stroke / 2, width: outer - stroke, height: outer - stroke)
            let ring = NSBezierPath(ovalIn: strokeRect)
            ring.lineWidth = stroke
            standup.setStroke()
            ring.stroke()
            let ix = (outer - inner) / 2
            let iy = y + (outer - inner) / 2
            category!.setFill()
            NSBezierPath(ovalIn: NSRect(x: ix, y: iy, width: inner, height: inner)).fill()
        }
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.removeAllItems()
        addActionsItems()
        menu.addItem(.separator())
        addCategoryItems()
        menu.addItem(.separator())
        addTotalsSubmenu()
        addConfigureSubmenu()
        menu.addItem(.separator())
        addBottomItems()
    }

    private func addCategoryItems() {
        for (index, category) in WorkCategory.allCases.enumerated() {
            let item = NSMenuItem(title: category.displayName, action: #selector(menuStartTracking(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = Self.symbol(category.symbolName)
            if tracker.active?.category == category { item.state = .on }
            menu.addItem(item)
        }
    }

    private func addTotalsSubmenu() {
        let totalsItem = NSMenuItem(title: "Totals", action: nil, keyEquivalent: "")
        totalsItem.image = Self.symbol("chart.bar")
        let totalsMenu = NSMenu(title: "Totals")
        let saved = self.menu
        self.menu = totalsMenu

        let cal = Calendar.current
        let now = Date()
        let todayStart = cal.startOfDay(for: now)
        let weekStart = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? todayStart
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? todayStart
        let todayTotals = mergedTotals(TimeAggregator.totalsForToday(), rangeStart: todayStart)
        let weekTotals = mergedTotals(TimeAggregator.totalsForWeek(), rangeStart: weekStart)
        let monthTotals = mergedTotals(TimeAggregator.totalsForMonth(), rangeStart: monthStart)

        addTotalsSection(title: "Today", totals: todayTotals, showGrandTotal: true)
        let weekItem = NSMenuItem(title: "This week:  " + inlineTotals(weekTotals), action: nil, keyEquivalent: "")
        weekItem.isEnabled = false
        totalsMenu.addItem(weekItem)
        let monthItem = NSMenuItem(title: "This month: " + inlineTotals(monthTotals), action: nil, keyEquivalent: "")
        monthItem.isEnabled = false
        totalsMenu.addItem(monthItem)
        totalsMenu.addItem(.separator())
        let openLog = NSMenuItem(title: "Open today's tracking log", action: #selector(menuOpenLog), keyEquivalent: "")
        openLog.target = self
        openLog.image = Self.symbol("doc.text")
        totalsMenu.addItem(openLog)

        self.menu = saved
        totalsItem.submenu = totalsMenu
        menu.addItem(totalsItem)
    }

    private func addConfigureSubmenu() {
        let item = NSMenuItem(title: "Configure", action: nil, keyEquivalent: "")
        item.image = Self.symbol("gearshape")
        let submenu = NSMenu(title: "Configure")
        let saved = self.menu
        self.menu = submenu
        addConfigureItems()
        self.menu = saved
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addActionsItems() {
        if tracker.isTracking {
            let item = NSMenuItem(title: "Stop Tracker", action: #selector(menuStopTracking), keyEquivalent: "")
            item.target = self
            item.image = Self.symbol("stop.fill")
            menu.addItem(item)
        } else if let last = tracker.lastCategory {
            let item = NSMenuItem(title: "Start Tracker (\(last.displayName))", action: #selector(menuStartLastCategory), keyEquivalent: "")
            item.target = self
            item.image = Self.symbol("play.fill")
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Start Tracker", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = Self.symbol("play.fill")
            menu.addItem(item)
        }
        let reset = NSMenuItem(title: "Reset Timer", action: #selector(menuResetStandup), keyEquivalent: "")
        reset.target = self
        reset.image = Self.symbol("arrow.counterclockwise")
        menu.addItem(reset)
    }

    private func mergedTotals(_ base: [WorkCategory: TimeInterval], rangeStart: Date) -> [WorkCategory: TimeInterval] {
        guard let active = tracker.active else { return base }
        let effectiveStart = max(active.startTime, rangeStart)
        let elapsed = Date().timeIntervalSince(effectiveStart)
        guard elapsed > 0 else { return base }
        var merged = base
        merged[active.category, default: 0] += elapsed
        return merged
    }

    private func addConfigureItems() {
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(menuToggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        launchItem.image = Self.symbol("arrow.up.right.circle")
        menu.addItem(launchItem)

        let idleItem = NSMenuItem(title: "Idle threshold", action: nil, keyEquivalent: "")
        idleItem.image = Self.symbol("moon.zzz")
        let idleMenu = NSMenu(title: "Idle threshold")
        for seconds in IdleWatcher.idleOptions {
            let item = NSMenuItem(title: IdleWatcher.thresholdLabel(forSeconds: seconds), action: #selector(menuPickIdleThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = (seconds == idleWatcher.thresholdSeconds) ? .on : .off
            idleMenu.addItem(item)
        }
        idleItem.submenu = idleMenu
        menu.addItem(idleItem)

        let breakItem = NSMenuItem(title: "Break threshold", action: nil, keyEquivalent: "")
        breakItem.image = Self.symbol("cup.and.saucer")
        let breakMenu = NSMenu(title: "Break threshold")
        for seconds in IdleWatcher.breakOptions {
            let item = NSMenuItem(title: IdleWatcher.thresholdLabel(forSeconds: seconds), action: #selector(menuPickBreakThreshold(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = (seconds == idleWatcher.breakThresholdSeconds) ? .on : .off
            breakMenu.addItem(item)
        }
        breakItem.submenu = breakMenu
        menu.addItem(breakItem)

        let intervalItem = NSMenuItem(title: "Interval threshold", action: nil, keyEquivalent: "")
        intervalItem.image = Self.symbol("timer")
        let intervalMenu = NSMenu(title: "Interval threshold")
        for seconds in TimerController.intervalOptions {
            let item = NSMenuItem(title: TimerController.intervalLabel(forSeconds: seconds), action: #selector(menuPickInterval(_:)), keyEquivalent: "")
            item.target = self
            item.tag = seconds
            item.state = (seconds == standup.intervalSeconds) ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        let dirItem = NSMenuItem(title: "Output directory…", action: #selector(menuPickOutputDirectory), keyEquivalent: "")
        dirItem.target = self
        dirItem.image = Self.symbol("folder")
        menu.addItem(dirItem)

        let about = NSMenuItem(title: "About Rut Timer", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        about.image = Self.symbol("info.circle")
        menu.addItem(about)
    }

    private func addBottomItems() {
        let quit = NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        quit.image = Self.symbol("power")
        menu.addItem(quit)
    }

    // MARK: - Symbol helpers

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    private func addTotalsSection(title: String, totals: [WorkCategory: TimeInterval], showGrandTotal: Bool) {
        let label = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        label.isEnabled = false
        label.attributedTitle = NSAttributedString(string: title.uppercased(), attributes: [
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize - 1, weight: .semibold),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        menu.addItem(label)

        for category in WorkCategory.allCases {
            let duration = totals[category] ?? 0
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = Self.symbol(category.symbolName)
            item.attributedTitle = Self.tabularRow(name: category.displayName, value: TimeTracker.durationString(duration), bold: false)
            menu.addItem(item)
        }
        if showGrandTotal {
            let grand = totals.values.reduce(0, +)
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = Self.symbol("sum")
            item.attributedTitle = Self.tabularRow(name: "Total", value: TimeTracker.durationString(grand), bold: true)
            menu.addItem(item)
        }
    }

    private static func tabularRow(name: String, value: String, bold: Bool) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 170)]
        let nameFont: NSFont = bold
            ? NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
            : NSFont.menuFont(ofSize: 0)
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize - 1, weight: bold ? .semibold : .regular)
        let result = NSMutableAttributedString()
        result.append(NSAttributedString(string: name, attributes: [
            .font: nameFont,
            .paragraphStyle: paragraph
        ]))
        result.append(NSAttributedString(string: "\t" + value, attributes: [
            .font: valueFont,
            .foregroundColor: bold ? NSColor.labelColor : NSColor.secondaryLabelColor,
            .paragraphStyle: paragraph
        ]))
        return result
    }

    private func inlineTotals(_ totals: [WorkCategory: TimeInterval]) -> String {
        WorkCategory.allCases.map { c in "\(c.displayName) \(TimeTracker.durationString(totals[c] ?? 0))" }.joined(separator: " · ")
    }

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }

    // MARK: - Menu actions

    @objc private func menuResetStandup() {
        standup.reset()
        updateDisplay()
    }

    @objc private func menuPickInterval(_ sender: NSMenuItem) {
        standup.intervalSeconds = sender.tag
        updateDisplay()
    }

    @objc private func menuPickIdleThreshold(_ sender: NSMenuItem) {
        idleWatcher.setThreshold(sender.tag)
        idleWatcher.stop()
        idleWatcher.start()
    }

    @objc private func menuPickBreakThreshold(_ sender: NSMenuItem) {
        idleWatcher.setBreakThreshold(sender.tag)
    }

    @objc private func menuStartTracking(_ sender: NSMenuItem) {
        let category = WorkCategory.allCases[sender.tag]
        tracker.start(category)
        updateDisplay()
    }

    @objc private func menuStartLastCategory() {
        guard tracker.lastCategory != nil else { return }
        tracker.startLastCategory()
        updateDisplay()
    }

    @objc private func menuStopTracking() {
        tracker.stop()
        dismissIdleNotification()
        updateDisplay()
    }

    @objc private func menuOpenLog() {
        let url = tracker.fileURL(for: Date())
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let header = "# Time Tracking — \(TimeTracker.dayString(Date()))\n\n## Sessions\n\n## Totals\n\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(url)
    }

    @objc private func menuPickOutputDirectory() {
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

    @objc private func menuToggleLaunchAtLogin() {
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

    @objc private func menuAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleName"] as? String ?? "Rut Timer"
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let alert = NSAlert()
        alert.messageText = name
        alert.informativeText = "Version \(version)\n\nAmbient standup reminder + simple time tracking across Maker / Manager / Reactive / Learning."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    // MARK: - Idle notification (native)

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error { NSLog("[RutTimer] notification authorization error: \(error)") }
            if !granted { NSLog("[RutTimer] notifications not granted — idle prompts will not appear until enabled in System Settings") }
        }
        let stopAtIdle = UNNotificationAction(identifier: actionStopAtIdle, title: "Stop at inactivity time", options: [])
        let cont = UNNotificationAction(identifier: actionContinue, title: "Continue tracking", options: [])
        let stopAndResume = UNNotificationAction(identifier: actionStopAndResume, title: "Stop and resume now", options: [])
        let category = UNNotificationCategory(identifier: idleCategoryId, actions: [stopAtIdle, cont, stopAndResume], intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories([category])
    }

    private func presentIdleNotification(idleSeconds: TimeInterval) {
        guard let active = tracker.active else {
            NSLog("[RutTimer] presentIdleNotification: not tracking, skipping")
            return
        }
        if idleNotificationVisible {
            NSLog("[RutTimer] notification already visible, not adding another")
            return
        }
        let idleStart = Date().addingTimeInterval(-idleSeconds)
        idleAtTime = idleStart
        let content = UNMutableNotificationContent()
        let minutes = Int(idleSeconds / 60)
        let units = minutes > 0 ? "\(minutes) min" : "\(Int(idleSeconds)) sec"
        content.title = "Inactive for \(units)"
        content.body = "Tracking \(active.category.displayName) — inactive since \(TimeTracker.timeString(idleStart)). What would you like to do?"
        content.categoryIdentifier = idleCategoryId
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: idleCategoryId, content: content, trigger: nil)
        idleNotificationVisible = true
        NSLog("[RutTimer] adding notification request idleSec=%.1f", idleSeconds)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                NSLog("[RutTimer] notification add error: \(error)")
                DispatchQueue.main.async { self?.idleNotificationVisible = false }
            } else {
                NSLog("[RutTimer] notification added OK")
            }
        }
    }

    private func dismissIdleNotification() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [idleCategoryId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [idleCategoryId])
        idleNotificationVisible = false
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let idleStart = idleAtTime ?? Date()
        NSLog("[RutTimer] notification action: \(response.actionIdentifier)")
        switch response.actionIdentifier {
        case actionStopAtIdle:
            tracker.stop(at: idleStart, force: true)
        case actionStopAndResume:
            tracker.stopAndResume(at: idleStart)
        case actionContinue:
            break
        default:
            break
        }
        idleWatcher.resetLatch()
        idleAtTime = nil
        idleNotificationVisible = false
        DispatchQueue.main.async { [weak self] in self?.updateDisplay() }
        completionHandler()
    }
}
