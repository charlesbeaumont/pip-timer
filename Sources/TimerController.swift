import Foundation
import AppKit

enum ColorState {
    case green, amber, red

    var color: NSColor {
        switch self {
        case .green: return .systemGreen
        case .amber: return .systemOrange
        case .red:   return .systemRed
        }
    }
}

final class TimerController {
    static let defaultIntervalSeconds = 1800
    static let intervalOptions: [Int] = [10, 900, 1200, 1500, 1800, 2700, 3600]

    private(set) var startTime: Date {
        didSet { UserDefaults.standard.set(startTime, forKey: Defaults.startTime) }
    }

    var intervalSeconds: Int {
        didSet { UserDefaults.standard.set(intervalSeconds, forKey: Defaults.intervalSeconds) }
    }

    init() {
        let defaults = UserDefaults.standard
        self.startTime = defaults.object(forKey: Defaults.startTime) as? Date ?? Date()
        let stored = defaults.integer(forKey: Defaults.intervalSeconds)
        self.intervalSeconds = stored > 0 ? stored : Self.defaultIntervalSeconds
    }

    var elapsed: TimeInterval { Date().timeIntervalSince(startTime) }

    var colorState: ColorState {
        let t = TimeInterval(intervalSeconds)
        if elapsed < t { return .green }
        if elapsed < 2 * t { return .amber }
        return .red
    }

    func reset() { startTime = Date() }

    static func formatElapsed(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%02d:%02d", h, m)
    }

    static func intervalLabel(forSeconds s: Int) -> String {
        if s < 60 { return "\(s) seconds" }
        let m = s / 60
        return "\(m) minutes"
    }
}
