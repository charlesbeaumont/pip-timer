import Foundation

struct TimeAggregator {
    struct Session {
        let category: WorkCategory
        let duration: TimeInterval
    }

    static func parseSessions(from contents: String) -> [Session] {
        var sessions: [Session] = []
        var inSessions = false
        for raw in contents.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## Sessions") { inSessions = true; continue }
            if line.hasPrefix("## ") { inSessions = false; continue }
            guard inSessions, line.hasPrefix("- ") else { continue }
            if let s = parseSessionLine(line) { sessions.append(s) }
        }
        return sessions
    }

    private static func parseSessionLine(_ line: String) -> Session? {
        guard let openParen = line.firstIndex(of: "("),
              let closeParen = line.firstIndex(of: ")") else { return nil }
        let durationStr = String(line[line.index(after: openParen)..<closeParen])
        let trailing = line[line.index(after: closeParen)...].trimmingCharacters(in: .whitespaces)
        guard let category = WorkCategory.allCases.first(where: { $0.displayName == trailing }) else { return nil }
        let parts = durationStr.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return Session(category: category, duration: TimeInterval(h * 3600 + m * 60))
    }

    static func totalsForToday() -> [WorkCategory: TimeInterval] {
        totals(for: [Date()])
    }

    static func totalsForWeek() -> [WorkCategory: TimeInterval] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else { return [:] }
        return totals(for: days(from: interval.start, until: interval.end))
    }

    static func totalsForMonth() -> [WorkCategory: TimeInterval] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        guard let interval = cal.dateInterval(of: .month, for: today) else { return [:] }
        return totals(for: days(from: interval.start, until: interval.end))
    }

    private static func days(from start: Date, until end: Date) -> [Date] {
        let cal = Calendar.current
        var result: [Date] = []
        var cursor = start
        while cursor < end {
            result.append(cursor)
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? end
        }
        return result
    }

    private static func totals(for dates: [Date]) -> [WorkCategory: TimeInterval] {
        var totals: [WorkCategory: TimeInterval] = [:]
        for date in dates {
            guard let url = fileURL(for: date) else { continue }
            guard let contents = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for s in parseSessions(from: contents) {
                totals[s.category, default: 0] += s.duration
            }
        }
        return totals
    }

    private static func fileURL(for date: Date) -> URL? {
        guard let root = TimeTracker.vaultRoot else { return nil }
        return URL(fileURLWithPath: root).appendingPathComponent("\(TimeTracker.dayString(date)).md")
    }
}
