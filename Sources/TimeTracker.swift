import Foundation

final class TimeTracker {
    static let minimumSessionSeconds: TimeInterval = 30

    private struct ActiveSession: Codable {
        let category: WorkCategory
        let startTime: Date
    }

    private(set) var active: (category: WorkCategory, startTime: Date)?

    init() {
        UserDefaults.standard.removeObject(forKey: Defaults.activeSession)
    }

    var isTracking: Bool { active != nil }

    var currentElapsed: TimeInterval? {
        active.map { Date().timeIntervalSince($0.startTime) }
    }

    var lastCategory: WorkCategory? {
        guard let raw = UserDefaults.standard.string(forKey: Defaults.lastCategory) else { return nil }
        return WorkCategory(rawValue: raw)
    }

    static var vaultRoot: String? {
        UserDefaults.standard.string(forKey: Defaults.vaultRoot)
    }

    static func setVaultRoot(_ path: String) {
        UserDefaults.standard.set(path, forKey: Defaults.vaultRoot)
    }

    func start(_ category: WorkCategory) {
        if let current = active {
            if current.category == category { return }
            finalize(current, endTime: Date())
        }
        let session = ActiveSession(category: category, startTime: Date())
        active = (category, session.startTime)
        persistActive(session)
        UserDefaults.standard.set(category.rawValue, forKey: Defaults.lastCategory)
    }

    func startLastCategory() {
        guard let cat = lastCategory else { return }
        start(cat)
    }

    func stop() { stop(at: Date(), force: false) }

    func stop(at endTime: Date, force: Bool = false) {
        guard let current = active else { return }
        finalize(current, endTime: endTime, force: force)
        active = nil
        UserDefaults.standard.removeObject(forKey: Defaults.activeSession)
    }

    func stopAndResume(at idleStartTime: Date) {
        guard let current = active else { return }
        let category = current.category
        finalize(current, endTime: idleStartTime, force: true)
        let session = ActiveSession(category: category, startTime: Date())
        active = (category, session.startTime)
        persistActive(session)
    }

    private func persistActive(_ session: ActiveSession) {
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: Defaults.activeSession)
        }
    }

    private func finalize(_ session: (category: WorkCategory, startTime: Date), endTime: Date, force: Bool = false) {
        guard endTime > session.startTime else { return }
        let duration = endTime.timeIntervalSince(session.startTime)
        if !force, duration < Self.minimumSessionSeconds { return }

        let cal = Calendar.current
        let startDay = cal.startOfDay(for: session.startTime)
        let endDay = cal.startOfDay(for: endTime)
        if startDay == endDay {
            appendSession(category: session.category, start: session.startTime, end: endTime)
        } else {
            let midnight = cal.date(byAdding: .day, value: 1, to: startDay)!
            appendSession(category: session.category, start: session.startTime, end: midnight)
            finalize((session.category, midnight), endTime: endTime, force: force)
        }
    }

    private func appendSession(category: WorkCategory, start: Date, end: Date) {
        guard let fileURL = fileURL(for: start) else {
            NSLog("[Pip] Output directory not configured; session not saved")
            return
        }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            guard writeHeader(at: fileURL, for: start) else {
                NSLog("[Pip] Could not write tracking file at \(fileURL.path)")
                return
            }
        }
        guard var contents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            NSLog("[Pip] Could not read tracking file at \(fileURL.path)")
            return
        }
        let line = formatSession(category: category, start: start, end: end)
        contents = insertSessionLine(line, into: contents)
        contents = rewriteTotals(in: contents)
        try? contents.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    @discardableResult
    private func writeHeader(at url: URL, for date: Date) -> Bool {
        let header = "# Time Tracking — \(Self.dayString(date))\n\n## Sessions\n\n## Totals\n\n"
        do {
            try header.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    private func formatSession(category: WorkCategory, start: Date, end: Date) -> String {
        let duration = end.timeIntervalSince(start)
        return "- \(Self.timeString(start))–\(Self.timeString(end)) (\(Self.durationString(duration))) \(category.displayName)"
    }

    private func insertSessionLine(_ line: String, into contents: String) -> String {
        var lines = contents.components(separatedBy: "\n")
        guard let sessionsIdx = lines.firstIndex(where: { $0.hasPrefix("## Sessions") }) else {
            return contents + line + "\n"
        }
        var insertAt = sessionsIdx + 1
        while insertAt < lines.count, !lines[insertAt].hasPrefix("## ") {
            insertAt += 1
        }
        while insertAt > sessionsIdx + 1, lines[insertAt - 1].trimmingCharacters(in: .whitespaces).isEmpty {
            insertAt -= 1
        }
        lines.insert(line, at: insertAt)
        return lines.joined(separator: "\n")
    }

    private func rewriteTotals(in contents: String) -> String {
        let sessions = TimeAggregator.parseSessions(from: contents)
        var totals: [WorkCategory: TimeInterval] = [:]
        for s in sessions { totals[s.category, default: 0] += s.duration }
        let grand = totals.values.reduce(0, +)
        var block = "## Totals\n\n"
        for c in WorkCategory.allCases {
            block += "- \(c.displayName.padding(toLength: 9, withPad: " ", startingAt: 0)) \(Self.durationString(totals[c] ?? 0))\n"
        }
        block += "- **Total:    \(Self.durationString(grand))**\n"
        var lines = contents.components(separatedBy: "\n")
        guard let totalsIdx = lines.firstIndex(where: { $0.hasPrefix("## Totals") }) else {
            return contents + "\n" + block
        }
        lines.removeSubrange(totalsIdx..<lines.count)
        var result = lines.joined(separator: "\n")
        if !result.hasSuffix("\n") { result += "\n" }
        return result + block
    }

    func fileURL(for date: Date) -> URL? {
        guard let root = Self.vaultRoot else { return nil }
        return URL(fileURLWithPath: root).appendingPathComponent("\(Self.dayString(date)).md")
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static func dayString(_ date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func timeString(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func durationString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        return String(format: "%d:%02d", h, m)
    }
}
