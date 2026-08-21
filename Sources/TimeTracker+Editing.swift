import Foundation

extension TimeTracker {
    struct Entry: Equatable {
        var category: WorkCategory
        var startMinutes: Int   // 0...1439
        var endMinutes: Int     // 0...1440; 1440 formats as "00:00" (end of day)
    }

    func entries(for date: Date) -> (entries: [Entry], rejects: [String]) {
        guard let url = fileURL(for: date),
              let contents = try? String(contentsOf: url, encoding: .utf8) else { return ([], []) }
        var entries: [Entry] = []
        var rejects: [String] = []
        var inSessions = false
        for raw in contents.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("## Sessions") { inSessions = true; continue }
            if line.hasPrefix("## ") { inSessions = false; continue }
            guard inSessions, line.hasPrefix("- ") else { continue }
            if let parsed = TimeAggregator.parseEntryLine(line) {
                entries.append(Entry(category: parsed.category, startMinutes: parsed.startMinutes, endMinutes: parsed.endMinutes))
            } else {
                rejects.append(line)
            }
        }
        return (entries, rejects)
    }

    func replaceSessions(for date: Date, entries: [Entry], rejects: [String]) {
        guard let url = fileURL(for: date) else {
            NSLog("[Pip] Output directory not configured; edit not saved")
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            guard writeHeader(at: url, for: date) else {
                NSLog("[Pip] Could not write tracking file at \(url.path)")
                return
            }
        }
        guard let contents = try? String(contentsOf: url, encoding: .utf8) else {
            NSLog("[Pip] Could not read tracking file at \(url.path)")
            return
        }

        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: date)
        func time(_ minutes: Int) -> Date {
            if minutes >= 24 * 60 { return cal.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart }
            return cal.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: dayStart) ?? dayStart
        }
        var body = rejects
        for e in entries.sorted(by: { $0.startMinutes < $1.startMinutes }) {
            body.append(formatSession(category: e.category, start: time(e.startMinutes), end: time(e.endMinutes)))
        }
        var block = ["## Sessions", ""]
        if !body.isEmpty { block += body + [""] }

        var lines = contents.components(separatedBy: "\n")
        if let sectionIdx = lines.firstIndex(where: { $0.hasPrefix("## Sessions") }) {
            var endIdx = sectionIdx + 1
            while endIdx < lines.count, !lines[endIdx].hasPrefix("## ") { endIdx += 1 }
            lines.replaceSubrange(sectionIdx..<endIdx, with: block)
        } else if let totalsIdx = lines.firstIndex(where: { $0.hasPrefix("## Totals") }) {
            lines.insert(contentsOf: block, at: totalsIdx)
        } else {
            lines.append(contentsOf: block)
        }
        let rewritten = rewriteTotals(in: lines.joined(separator: "\n"))
        try? rewritten.write(to: url, atomically: true, encoding: .utf8)
        onFileWritten?()
    }
}
