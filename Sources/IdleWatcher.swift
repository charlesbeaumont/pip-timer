import Foundation
import IOKit

final class IdleWatcher {
    static let idleOptions: [Int] = [10, 180, 300, 600, 900]
    static let breakOptions: [Int] = [300, 600, 900, 1200, 1800]
    static let defaultIdleSeconds = 300
    static let defaultBreakSeconds = 600

    var onIdleCrossed: ((TimeInterval) -> Void)?
    var onIdleCleared: (() -> Void)?
    var onBreakCrossed: ((TimeInterval) -> Void)?

    private var poll: Timer?
    private var isIdle = false
    private var isBreak = false

    var thresholdSeconds: Int {
        let stored = UserDefaults.standard.integer(forKey: Defaults.idleThresholdSeconds)
        return stored > 0 ? stored : Self.defaultIdleSeconds
    }

    var breakThresholdSeconds: Int {
        let stored = UserDefaults.standard.integer(forKey: Defaults.breakThresholdSeconds)
        return stored > 0 ? stored : Self.defaultBreakSeconds
    }

    func setThreshold(_ seconds: Int) {
        UserDefaults.standard.set(seconds, forKey: Defaults.idleThresholdSeconds)
    }

    func setBreakThreshold(_ seconds: Int) {
        UserDefaults.standard.set(seconds, forKey: Defaults.breakThresholdSeconds)
    }

    static func thresholdLabel(forSeconds s: Int) -> String {
        if s < 60 { return "\(s) seconds" }
        return "\(s / 60) minutes"
    }

    func start() {
        guard poll == nil else { return }
        let interval: TimeInterval = thresholdSeconds < 60 ? 2 : 5
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(timer, forMode: .common)
        poll = timer
        check()
    }

    func stop() {
        poll?.invalidate()
        poll = nil
        isIdle = false
        isBreak = false
    }

    func resetLatch() { isIdle = false }

    private func check() {
        guard let idleSeconds = Self.systemIdleTime() else {
            NSLog("[Pip.idle] could not read HIDIdleTime")
            return
        }
        let idleThreshold = TimeInterval(thresholdSeconds)
        let breakThreshold = TimeInterval(breakThresholdSeconds)
        if !isIdle, idleSeconds >= idleThreshold {
            isIdle = true
            onIdleCrossed?(idleSeconds)
        } else if isIdle, idleSeconds < idleThreshold {
            isIdle = false
            onIdleCleared?()
        }
        if !isBreak, idleSeconds >= breakThreshold {
            isBreak = true
            onBreakCrossed?(idleSeconds)
        } else if isBreak, idleSeconds < breakThreshold {
            isBreak = false
        }
    }

    static func systemIdleTime() -> TimeInterval? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        let entry: io_registry_entry_t = IOIteratorNext(iterator)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }
        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanagedDict, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return nil }
        guard let dict = unmanagedDict?.takeRetainedValue() as? [String: Any] else { return nil }
        guard let nanos = dict["HIDIdleTime"] as? Int64 else { return nil }
        return TimeInterval(nanos) / TimeInterval(NSEC_PER_SEC)
    }
}
