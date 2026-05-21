import AppKit
import UserNotifications

extension AppDelegate {
    static let idleCategoryId = "PIP_IDLE"
    static let sleepCategoryId = "PIP_SLEEP"
    static let crashCategoryId = "PIP_CRASH"
    static let notificationRequestId = "PIP_RECOVERY"
    static let actionStopAtGap = "STOP_AT_GAP"
    static let actionContinue = "CONTINUE"
    static let actionStopAndResume = "STOP_AND_RESUME"

    func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error { NSLog("[Pip] notification authorization error: \(error)") }
            if !granted { NSLog("[Pip] notifications not granted — recovery prompts will not appear until enabled in System Settings") }
        }
        center.getNotificationSettings { settings in
            NSLog("[Pip] notification auth status at launch: \(Self.authStatusName(settings.authorizationStatus))")
        }
        let cont = UNNotificationAction(identifier: Self.actionContinue, title: "Continue tracking", options: [])
        let resume = UNNotificationAction(identifier: Self.actionStopAndResume, title: "Stop and resume now", options: [])
        let idle = UNNotificationCategory(
            identifier: Self.idleCategoryId,
            actions: [
                UNNotificationAction(identifier: Self.actionStopAtGap, title: "Stop at inactivity time", options: []),
                cont, resume,
            ],
            intentIdentifiers: [], options: [.customDismissAction]
        )
        let sleep = UNNotificationCategory(
            identifier: Self.sleepCategoryId,
            actions: [
                UNNotificationAction(identifier: Self.actionStopAtGap, title: "Stop at sleep time", options: []),
                cont, resume,
            ],
            intentIdentifiers: [], options: [.customDismissAction]
        )
        let crash = UNNotificationCategory(
            identifier: Self.crashCategoryId,
            actions: [
                UNNotificationAction(identifier: Self.actionStopAtGap, title: "Stop at last activity", options: []),
                cont, resume,
            ],
            intentIdentifiers: [], options: [.customDismissAction]
        )
        center.setNotificationCategories([idle, sleep, crash])
    }

    private static func authStatusName(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "notDetermined"
        case .denied: return "denied"
        case .authorized: return "authorized"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    // MARK: - Public entry points (one per gap source)

    func presentIdleNotification(idleSeconds: TimeInterval) {
        guard let active = tracker.active else { return }
        let idleStart = Date().addingTimeInterval(-idleSeconds)
        let units = idleSeconds >= 60 ? "\(Int(idleSeconds / 60)) min" : "\(Int(idleSeconds)) sec"
        present(
            kind: .idle,
            category: active.category,
            gapStart: idleStart,
            title: "Inactive for \(units)",
            body: "Tracking \(active.category.displayName) — inactive since \(TimeTracker.timeString(idleStart)). What would you like to do?"
        )
    }

    func presentSleepRecovery(category: WorkCategory, sleepStart: Date) {
        let gap = Date().timeIntervalSince(sleepStart)
        let units = gap >= 3600 ? String(format: "%.1f h", gap / 3600) : "\(Int(gap / 60)) min"
        dismissIdleNotification()
        present(
            kind: .sleep,
            category: category,
            gapStart: sleepStart,
            title: "Asleep for \(units)",
            body: "Tracking \(category.displayName) — closed lid at \(TimeTracker.timeString(sleepStart)). What would you like to do?"
        )
    }

    func presentCrashRecovery() {
        guard let r = tracker.pendingRecovery else { return }
        let gap = Date().timeIntervalSince(r.lastAliveAt)
        let ago: String
        if gap >= 86400 {
            ago = String(format: "%.1f d ago", gap / 86400)
        } else if gap >= 3600 {
            ago = String(format: "%.1f h ago", gap / 3600)
        } else {
            ago = "\(Int(gap / 60)) min ago"
        }
        present(
            kind: .crash,
            category: r.category,
            gapStart: r.lastAliveAt,
            title: "Pip didn't quit cleanly",
            body: "Tracking \(r.category.displayName) from \(TimeTracker.timeString(r.startTime)) — last seen at \(TimeTracker.timeString(r.lastAliveAt)) (\(ago)). What should I do with the time?"
        )
    }

    // MARK: - Shared presenter

    private func present(kind: RecoveryKind, category: WorkCategory, gapStart: Date, title: String, body: String) {
        if idleNotificationVisible { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        switch kind {
        case .idle:  content.categoryIdentifier = Self.idleCategoryId
        case .sleep: content.categoryIdentifier = Self.sleepCategoryId
        case .crash: content.categoryIdentifier = Self.crashCategoryId
        }
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: Self.notificationRequestId, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            let status = settings.authorizationStatus
            if status == .notDetermined {
                NSLog("[Pip] auth status is notDetermined — requesting now")
                center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                    if let error = error { NSLog("[Pip] auth request error: \(error)") }
                    if granted {
                        DispatchQueue.main.async {
                            self?.present(kind: kind, category: category, gapStart: gapStart, title: title, body: body)
                        }
                    } else {
                        NSLog("[Pip] auth denied or dismissed by user — recovery prompt skipped")
                    }
                }
                return
            }
            guard status == .authorized || status == .provisional else {
                NSLog("[Pip] recovery prompt skipped — auth status is \(Self.authStatusName(status)). Enable in System Settings → Notifications → Pip.")
                return
            }
            DispatchQueue.main.async {
                self.gapStartTime = gapStart
                self.recoveryKind = kind
                self.idleNotificationVisible = true
                center.add(request) { error in
                    if let error = error {
                        NSLog("[Pip] notification add error: \(error)")
                        DispatchQueue.main.async { self.idleNotificationVisible = false }
                    }
                }
            }
        }
    }

    func dismissIdleNotification() {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationRequestId])
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationRequestId])
        idleNotificationVisible = false
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let kind = recoveryKind ?? .idle
        let gap = gapStartTime ?? Date()
        let action = response.actionIdentifier

        switch (kind, action) {
        case (.idle, Self.actionStopAtGap), (.sleep, Self.actionStopAtGap):
            tracker.stop(at: gap, force: true)
        case (.idle, Self.actionStopAndResume), (.sleep, Self.actionStopAndResume):
            tracker.stopAndResume(at: gap)
        case (.idle, Self.actionContinue), (.sleep, Self.actionContinue):
            break

        case (.crash, Self.actionStopAtGap):
            tracker.finalizeRecovery(at: gap)
        case (.crash, Self.actionContinue):
            tracker.resumeRecovery()
        case (.crash, Self.actionStopAndResume):
            let cat = tracker.pendingRecovery?.category
            tracker.finalizeRecovery(at: gap)
            if let cat = cat { tracker.start(cat) }

        default:
            // Dismissed without choosing. For idle/sleep that's "continue" (no-op).
            // For crash we'd otherwise re-prompt forever on every launch — treat
            // dismissal as "resume" so the orphan becomes an actual active
            // session that can be stopped manually later.
            if kind == .crash { tracker.resumeRecovery() }
        }

        idleWatcher.resetLatch()
        gapStartTime = nil
        recoveryKind = nil
        idleNotificationVisible = false
        DispatchQueue.main.async { [weak self] in self?.updateDisplay() }
        completionHandler()
    }
}
