import AppKit
import UserNotifications

extension AppDelegate {
    static let idleCategoryId = "PIP_IDLE"
    static let actionStopAtIdle = "STOP_AT_IDLE"
    static let actionContinue = "CONTINUE"
    static let actionStopAndResume = "STOP_AND_RESUME"

    func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error { NSLog("[Pip] notification authorization error: \(error)") }
            if !granted { NSLog("[Pip] notifications not granted — idle prompts will not appear until enabled in System Settings") }
        }
        center.getNotificationSettings { settings in
            NSLog("[Pip] notification auth status at launch: \(Self.authStatusName(settings.authorizationStatus))")
        }
        let stopAtIdle = UNNotificationAction(identifier: Self.actionStopAtIdle, title: "Stop at inactivity time", options: [])
        let cont = UNNotificationAction(identifier: Self.actionContinue, title: "Continue tracking", options: [])
        let stopAndResume = UNNotificationAction(identifier: Self.actionStopAndResume, title: "Stop and resume now", options: [])
        let category = UNNotificationCategory(identifier: Self.idleCategoryId, actions: [stopAtIdle, cont, stopAndResume], intentIdentifiers: [], options: [.customDismissAction])
        center.setNotificationCategories([category])
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

    func presentIdleNotification(idleSeconds: TimeInterval) {
        guard let active = tracker.active else { return }
        if idleNotificationVisible { return }
        let idleStart = Date().addingTimeInterval(-idleSeconds)
        let content = UNMutableNotificationContent()
        let minutes = Int(idleSeconds / 60)
        let units = minutes > 0 ? "\(minutes) min" : "\(Int(idleSeconds)) sec"
        content.title = "Inactive for \(units)"
        content.body = "Tracking \(active.category.displayName) — inactive since \(TimeTracker.timeString(idleStart)). What would you like to do?"
        content.categoryIdentifier = Self.idleCategoryId
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: Self.idleCategoryId, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            guard let self = self else { return }
            let status = settings.authorizationStatus
            if status == .notDetermined {
                NSLog("[Pip] auth status is notDetermined — requesting now")
                center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                    if let error = error { NSLog("[Pip] auth request error: \(error)") }
                    if granted {
                        DispatchQueue.main.async { self?.presentIdleNotification(idleSeconds: idleSeconds) }
                    } else {
                        NSLog("[Pip] auth denied or dismissed by user — idle prompt skipped")
                    }
                }
                return
            }
            guard status == .authorized || status == .provisional else {
                NSLog("[Pip] idle prompt skipped — auth status is \(Self.authStatusName(status)). Enable in System Settings → Notifications → Pip.")
                return
            }
            DispatchQueue.main.async {
                self.idleAtTime = idleStart
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
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.idleCategoryId])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.idleCategoryId])
        idleNotificationVisible = false
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let idleStart = idleAtTime ?? Date()
        switch response.actionIdentifier {
        case Self.actionStopAtIdle:
            tracker.stop(at: idleStart, force: true)
        case Self.actionStopAndResume:
            tracker.stopAndResume(at: idleStart)
        case Self.actionContinue:
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
