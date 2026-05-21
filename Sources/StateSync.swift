import Foundation

/// Cross-process state synchronization. Two Pips with the same bundle ID share
/// the same UserDefaults file but each cache values in memory, so a write in
/// one process isn't seen by the other until it re-reads.
///
/// `StateSync.broadcast()` posts a distributed notification when any process
/// writes a state-changing UserDefault. Listeners refresh their in-memory
/// state from disk. PID filtering prevents self-receipt; the `isApplyingSync`
/// flag prevents re-broadcasting during a refresh (which would loop).
enum StateSync {
    static let notificationName = Notification.Name("com.charlesbeaumont.Pip.stateChanged")
    private static let pidKey = "pid"
    private static let myPID = ProcessInfo.processInfo.processIdentifier

    /// True while applying an incoming sync. didSet handlers check this to
    /// suppress redundant broadcasts on values written from a sync handler.
    static var isApplyingSync = false

    static func broadcast() {
        guard !isApplyingSync else { return }
        DistributedNotificationCenter.default().postNotificationName(
            notificationName,
            object: nil,
            userInfo: [pidKey: NSNumber(value: myPID)],
            deliverImmediately: true
        )
    }

    static func observe(handler: @escaping () -> Void) {
        DistributedNotificationCenter.default().addObserver(
            forName: notificationName,
            object: nil,
            queue: .main
        ) { note in
            let senderPID = (note.userInfo?[pidKey] as? NSNumber)?.int32Value
            if senderPID == myPID { return }
            isApplyingSync = true
            handler()
            isApplyingSync = false
        }
    }
}
