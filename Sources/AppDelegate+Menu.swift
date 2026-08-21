import AppKit
import ServiceManagement

extension AppDelegate {
    func buildMenu() {
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

    private func addActionsItems() {
        if tracker.isTracking {
            let item = NSMenuItem(title: "Stop Tracker", action: #selector(menuStopTracking), keyEquivalent: "")
            item.target = self
            item.image = StatusItemRenderer.symbol("stop.fill")
            menu.addItem(item)
        } else if let last = tracker.lastCategory {
            let item = NSMenuItem(title: "Start Tracker (\(last.displayName))", action: #selector(menuStartLastCategory), keyEquivalent: "")
            item.target = self
            item.image = StatusItemRenderer.symbol("play.fill")
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Start Tracker", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = StatusItemRenderer.symbol("play.fill")
            menu.addItem(item)
        }
        let reset = NSMenuItem(title: "Reset Timer", action: #selector(menuResetStandup), keyEquivalent: "")
        reset.target = self
        reset.image = StatusItemRenderer.symbol("arrow.counterclockwise")
        menu.addItem(reset)
        let add = NSMenuItem(title: "Add entry…", action: #selector(menuAddEntry), keyEquivalent: "")
        add.target = self
        add.image = StatusItemRenderer.symbol("plus")
        menu.addItem(add)
        let edit = NSMenuItem(title: "Edit entries…", action: #selector(menuEditEntries), keyEquivalent: "")
        edit.target = self
        edit.image = StatusItemRenderer.symbol("pencil")
        menu.addItem(edit)
    }

    private func addCategoryItems() {
        for (index, category) in WorkCategory.allCases.enumerated() {
            let item = NSMenuItem(title: category.displayName, action: #selector(menuStartTracking(_:)), keyEquivalent: "")
            item.target = self
            item.tag = index
            item.image = StatusItemRenderer.symbol(category.symbolName)
            if tracker.active?.category == category { item.state = .on }
            menu.addItem(item)
        }
    }

    private func addTotalsSubmenu() {
        let totalsItem = NSMenuItem(title: "Totals", action: nil, keyEquivalent: "")
        totalsItem.image = StatusItemRenderer.symbol("chart.bar")
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
        let weekItem = NSMenuItem(title: "This week (incl. today):  " + inlineTotals(weekTotals), action: nil, keyEquivalent: "")
        weekItem.isEnabled = false
        totalsMenu.addItem(weekItem)
        let monthItem = NSMenuItem(title: "This month (incl. today): " + inlineTotals(monthTotals), action: nil, keyEquivalent: "")
        monthItem.isEnabled = false
        totalsMenu.addItem(monthItem)
        totalsMenu.addItem(.separator())
        let openLog = NSMenuItem(title: "Open today's tracking log", action: #selector(menuOpenLog), keyEquivalent: "")
        openLog.target = self
        openLog.image = StatusItemRenderer.symbol("doc.text")
        totalsMenu.addItem(openLog)

        self.menu = saved
        totalsItem.submenu = totalsMenu
        menu.addItem(totalsItem)
    }

    private func addConfigureSubmenu() {
        let item = NSMenuItem(title: "Configure", action: nil, keyEquivalent: "")
        item.image = StatusItemRenderer.symbol("gearshape")
        let submenu = NSMenu(title: "Configure")
        let saved = self.menu
        self.menu = submenu
        addConfigureItems()
        self.menu = saved
        item.submenu = submenu
        menu.addItem(item)
    }

    private func addConfigureItems() {
        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(menuToggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        launchItem.image = StatusItemRenderer.symbol("arrow.up.right.circle")
        menu.addItem(launchItem)

        let idleItem = NSMenuItem(title: "Idle threshold", action: nil, keyEquivalent: "")
        idleItem.image = StatusItemRenderer.symbol("moon.zzz")
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
        breakItem.image = StatusItemRenderer.symbol("cup.and.saucer")
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
        intervalItem.image = StatusItemRenderer.symbol("timer")
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
        dirItem.image = StatusItemRenderer.symbol("folder")
        menu.addItem(dirItem)

        let about = NSMenuItem(title: "About Pip", action: #selector(menuAbout), keyEquivalent: "")
        about.target = self
        about.image = StatusItemRenderer.symbol("info.circle")
        menu.addItem(about)
    }

    private func addBottomItems() {
        let quit = NSMenuItem(title: "Quit", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        quit.image = StatusItemRenderer.symbol("power")
        menu.addItem(quit)
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
            item.image = StatusItemRenderer.symbol(category.symbolName)
            item.attributedTitle = Self.tabularRow(name: category.displayName, value: TimeTracker.durationString(duration), bold: false)
            menu.addItem(item)
        }
        if showGrandTotal {
            let grand = totals.values.reduce(0, +)
            let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            item.isEnabled = false
            item.image = StatusItemRenderer.symbol("sum")
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

    private func mergedTotals(_ base: [WorkCategory: TimeInterval], rangeStart: Date) -> [WorkCategory: TimeInterval] {
        guard let active = tracker.active else { return base }
        let effectiveStart = max(active.startTime, rangeStart)
        let elapsed = Date().timeIntervalSince(effectiveStart)
        guard elapsed > 0 else { return base }
        var merged = base
        merged[active.category, default: 0] += elapsed
        return merged
    }
}
