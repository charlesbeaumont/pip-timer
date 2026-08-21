import AppKit

final class EditEntriesWindow: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let tracker: TimeTracker

    private let prevButton = NSButton()
    private let nextButton = NSButton()
    private let dateButton = NSButton()
    private let datePopover = NSPopover()
    private let calendarPicker = NSDatePicker()
    private var selectedDate = Date()

    private let tableView = NSTableView()
    private let trackingLabel = NSTextField(labelWithString: "")
    private let categorySegmented: NSSegmentedControl
    private let startPicker = NSDatePicker()
    private let endPicker = NSDatePicker()
    private let durationField = NSTextField(string: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton()
    private let addButton = NSButton()

    private var entries: [TimeTracker.Entry] = []
    private var rejects: [String] = []
    private var pendingSelection: TimeTracker.Entry?
    // File-truth value of the row being edited; live edits locate it by value,
    // so a pending debounce survives re-sorts and selection changes.
    private var editingEntry: TimeTracker.Entry?
    private var applyTimer: Timer?
    private var isApplyingEdit = false

    init(tracker: TimeTracker) {
        self.tracker = tracker
        categorySegmented = NSSegmentedControl(
            labels: WorkCategory.allCases.map { $0.displayName },
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 470, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Edit entries"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        selectedDate = Date()
        dayChanged()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
    }

    func reloadIfVisible() {
        guard window?.isVisible == true else { return }
        reload()
    }

    private func reload() {
        let previous = pendingSelection ?? selectedEntry()
        let result = tracker.entries(for: selectedDate)
        entries = result.entries
        rejects = result.rejects
        pendingSelection = nil
        tableView.reloadData()
        if let prev = previous, let i = entries.firstIndex(of: prev) {
            tableView.selectRowIndexes(IndexSet(integer: rejects.count + i), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
        updateTrackingLabel()
        updateFormState()
    }

    // MARK: - Day navigation

    private func dayChanged() {
        flushPendingEdit()
        dateButton.title = AddEntryWindow.dayLabel(for: selectedDate)
        nextButton.isEnabled = !Calendar.current.isDateInToday(selectedDate)
        pendingSelection = nil
        tableView.deselectAll(nil)
        reload()
    }

    @objc private func prevDay() { step(-1) }
    @objc private func nextDay() { step(1) }

    private func step(_ delta: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: delta, to: selectedDate) ?? selectedDate
        dayChanged()
    }

    @objc private func showDatePopover() {
        calendarPicker.dateValue = selectedDate
        datePopover.show(relativeTo: dateButton.bounds, of: dateButton, preferredEdge: .maxY)
    }

    @objc private func calendarPickerChanged() {
        selectedDate = calendarPicker.dateValue
        dayChanged()
    }

    // MARK: - Live editing

    @objc private func formChanged() {
        updateDerived()
        guard editingEntry != nil else { return }
        applyTimer?.invalidate()
        applyTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.applyEdit(reselectEdited: true)
        }
    }

    @objc private func durationEdited() {
        guard let minutes = parsedDurationMinutes(), minutes > 0 else {
            updateDerived()
            return
        }
        let start = self.minutes(from: startPicker)
        setPicker(endPicker, minutes: min(start + minutes, 24 * 60))
        formChanged()
    }

    private func applyEdit(reselectEdited: Bool) {
        applyTimer?.invalidate()
        guard let original = editingEntry,
              let i = entries.firstIndex(of: original),
              let updated = formEntry(),
              updated != original else { return }
        var newEntries = entries
        newEntries[i] = updated
        editingEntry = updated
        pendingSelection = reselectEdited ? updated : nil
        isApplyingEdit = true
        tracker.replaceSessions(for: selectedDate, entries: newEntries, rejects: rejects)
        isApplyingEdit = false
    }

    private func flushPendingEdit() {
        guard applyTimer?.isValid == true else { return }
        applyEdit(reselectEdited: false)
    }

    @objc private func addTapped() {
        flushPendingEdit()
        let lastEnd = entries.map(\.endMinutes).max() ?? 9 * 60
        let start = min(lastEnd, 24 * 60 - 1)
        let segment = categorySegmented.selectedSegment
        let category = (0..<WorkCategory.allCases.count).contains(segment)
            ? WorkCategory.allCases[segment]
            : (tracker.lastCategory ?? .maker)
        let entry = TimeTracker.Entry(category: category, startMinutes: start, endMinutes: min(start + 30, 24 * 60))
        pendingSelection = entry
        tracker.replaceSessions(for: selectedDate, entries: entries + [entry], rejects: rejects)
        if let e = selectedEntry() { loadForm(e) }
        window?.makeFirstResponder(startPicker)
    }

    @objc private func deleteTapped() {
        applyTimer?.invalidate()
        guard let i = selectedEntryIndex() else { return }
        editingEntry = nil
        var updated = entries
        updated.remove(at: i)
        tracker.replaceSessions(for: selectedDate, entries: updated, rejects: rejects)
    }

    // MARK: - Form <-> Entry

    private func selectedEntryIndex() -> Int? {
        let row = tableView.selectedRow
        guard row >= rejects.count, row - rejects.count < entries.count else { return nil }
        return row - rejects.count
    }

    private func selectedEntry() -> TimeTracker.Entry? { selectedEntryIndex().map { entries[$0] } }

    private func loadForm(_ e: TimeTracker.Entry) {
        editingEntry = e
        categorySegmented.selectedSegment = WorkCategory.allCases.firstIndex(of: e.category) ?? 0
        setPicker(startPicker, minutes: e.startMinutes)
        setPicker(endPicker, minutes: e.endMinutes)
        updateFormState()
    }

    private func formEntry() -> TimeTracker.Entry? {
        let segment = categorySegmented.selectedSegment
        guard (0..<WorkCategory.allCases.count).contains(segment) else { return nil }
        let (start, end) = formMinutes()
        guard end > start else { return nil }
        return TimeTracker.Entry(category: WorkCategory.allCases[segment], startMinutes: start, endMinutes: end)
    }

    private func formMinutes() -> (start: Int, end: Int) {
        let start = minutes(from: startPicker)
        var end = minutes(from: endPicker)
        if end == 0, start > 0 { end = 24 * 60 } // 00:00 = end of day, matching the file format
        return (start, end)
    }

    private func minutes(from picker: NSDatePicker) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func setPicker(_ picker: NSDatePicker, minutes: Int) {
        let cal = Calendar.current
        let base = cal.startOfDay(for: Date())
        let m = minutes % (24 * 60)
        picker.dateValue = cal.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: base) ?? base
    }

    private func parsedDurationMinutes() -> Int? {
        let s = durationField.stringValue.trimmingCharacters(in: .whitespaces)
        if s.contains(":") {
            let parts = s.split(separator: ":")
            guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]), h >= 0, (0...59).contains(m) else { return nil }
            return h * 60 + m
        }
        return Int(s)
    }

    private func updateFormState() {
        let hasSelection = selectedEntryIndex() != nil
        if !hasSelection { editingEntry = nil }
        for control in [categorySegmented, startPicker, endPicker, durationField] as [NSControl] {
            control.isEnabled = hasSelection
        }
        deleteButton.isEnabled = hasSelection
        updateDerived()
    }

    private func updateDerived() {
        let (start, end) = formMinutes()
        let valid = end > start
        if durationField.currentEditor() == nil {
            durationField.stringValue = valid ? TimeTracker.durationString(TimeInterval((end - start) * 60)) : ""
        }
        if editingEntry == nil {
            statusLabel.stringValue = entries.isEmpty && rejects.isEmpty
                ? "No entries — press + to add one"
                : "Select an entry to edit it, changes save as you type"
            statusLabel.textColor = .tertiaryLabelColor
        } else if !valid {
            statusLabel.stringValue = "End must be after start (00:00 = end of day) — not saved"
            statusLabel.textColor = .systemRed
        } else if hasOverlap() {
            statusLabel.stringValue = "Entries overlap"
            statusLabel.textColor = .systemOrange
        } else {
            statusLabel.stringValue = ""
        }
    }

    private func hasOverlap() -> Bool {
        let sorted = entries.sorted { $0.startMinutes < $1.startMinutes }
        for (a, b) in zip(sorted, sorted.dropFirst()) where a.endMinutes > b.startMinutes { return true }
        return false
    }

    private func updateTrackingLabel() {
        if Calendar.current.isDateInToday(selectedDate), let active = tracker.active {
            trackingLabel.stringValue = "Tracking \(active.category.displayName) since \(TimeTracker.timeString(active.startTime)) — stop the tracker to edit it"
            trackingLabel.isHidden = false
        } else {
            trackingLabel.isHidden = true
        }
    }

    private static func timeText(_ m: Int) -> String {
        String(format: "%02d:%02d", (m / 60) % 24, m % 60)
    }

    private static func rowText(_ e: TimeTracker.Entry) -> String {
        let duration = TimeTracker.durationString(TimeInterval((e.endMinutes - e.startMinutes) * 60))
        return "\(timeText(e.startMinutes))–\(timeText(e.endMinutes)) (\(duration)) \(e.category.displayName)"
    }

    // MARK: - Table

    func numberOfRows(in tableView: NSTableView) -> Int { rejects.count + entries.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let isReject = row < rejects.count
        let text = isReject ? rejects[row] : Self.rowText(entries[row - rejects.count])
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        label.textColor = isReject ? .tertiaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { row >= rejects.count }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isApplyingEdit else { return }
        flushPendingEdit()
        if let e = selectedEntry() { loadForm(e) } else { updateFormState() }
    }

    // MARK: - UI setup

    private func setupUI() {
        let navButtons: [(NSButton, String, String, Selector)] = [
            (prevButton, "chevron.left", "Previous day", #selector(prevDay)),
            (nextButton, "chevron.right", "Next day", #selector(nextDay)),
        ]
        for (button, symbol, description, action) in navButtons {
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
            button.bezelStyle = .rounded
            button.target = self
            button.action = action
        }

        dateButton.bezelStyle = .rounded
        dateButton.target = self
        dateButton.action = #selector(showDatePopover)
        dateButton.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)

        calendarPicker.datePickerStyle = .clockAndCalendar
        calendarPicker.datePickerElements = [.yearMonthDay]
        calendarPicker.maxDate = Date()
        calendarPicker.target = self
        calendarPicker.action = #selector(calendarPickerChanged)
        let popoverContainer = NSView()
        popoverContainer.addSubview(calendarPicker)
        calendarPicker.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            calendarPicker.topAnchor.constraint(equalTo: popoverContainer.topAnchor, constant: 12),
            calendarPicker.leadingAnchor.constraint(equalTo: popoverContainer.leadingAnchor, constant: 12),
            calendarPicker.trailingAnchor.constraint(equalTo: popoverContainer.trailingAnchor, constant: -12),
            calendarPicker.bottomAnchor.constraint(equalTo: popoverContainer.bottomAnchor, constant: -12),
        ])
        let popoverVC = NSViewController()
        popoverVC.view = popoverContainer
        datePopover.contentViewController = popoverVC
        datePopover.behavior = .transient

        let navRow = NSStackView(views: [prevButton, dateButton, nextButton])
        navRow.orientation = .horizontal
        navRow.spacing = 8

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("entry"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 20
        tableView.style = .inset
        tableView.dataSource = self
        tableView.delegate = self
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = tableView
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        scroll.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .vertical)

        trackingLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        trackingLabel.textColor = .secondaryLabelColor
        trackingLabel.lineBreakMode = .byTruncatingTail

        categorySegmented.segmentStyle = .rounded
        categorySegmented.target = self
        categorySegmented.action = #selector(formChanged)

        for picker in [startPicker, endPicker] {
            picker.datePickerStyle = .textFieldAndStepper
            picker.datePickerElements = [.hourMinute]
            picker.target = self
            picker.action = #selector(formChanged)
        }
        durationField.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        durationField.alignment = .center
        durationField.placeholderString = "h:mm"
        durationField.target = self
        durationField.action = #selector(durationEdited)
        (durationField.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
        durationField.translatesAutoresizingMaskIntoConstraints = false
        durationField.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let toLabel = NSTextField(labelWithString: "–")
        toLabel.textColor = .secondaryLabelColor
        let equalsLabel = NSTextField(labelWithString: "=")
        equalsLabel.textColor = .secondaryLabelColor
        let timeRow = NSStackView(views: [startPicker, toLabel, endPicker, equalsLabel, durationField])
        timeRow.orientation = .horizontal
        timeRow.spacing = 8

        let grid = NSGridView(views: [
            [formLabel("Category"), categorySegmented],
            [formLabel("Time"),     timeRow],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 70
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 12
        grid.rowSpacing = 10
        grid.setContentHuggingPriority(.required, for: .vertical)

        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.heightAnchor.constraint(equalToConstant: 14).isActive = true

        deleteButton.image = NSImage(systemSymbolName: "minus", accessibilityDescription: "Delete entry")
        deleteButton.target = self
        deleteButton.action = #selector(deleteTapped)
        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add entry")
        addButton.target = self
        addButton.action = #selector(addTapped)
        for button in [deleteButton, addButton] {
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        }

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.addView(addButton, in: .leading)
        buttonRow.addView(deleteButton, in: .leading)

        let main = NSStackView(views: [navRow, scroll, trackingLabel, grid, statusLabel, buttonRow])
        main.orientation = .vertical
        main.spacing = 10
        main.alignment = .leading
        main.edgeInsets = NSEdgeInsets(top: 16, left: 24, bottom: 14, right: 24)
        main.translatesAutoresizingMaskIntoConstraints = false

        let host = NSView()
        host.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: host.topAnchor),
            main.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            main.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            navRow.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 24),
            navRow.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -24),
            scroll.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 24),
            scroll.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -24),
            buttonRow.leadingAnchor.constraint(equalTo: main.leadingAnchor, constant: 24),
        ])
        window?.contentView = host

        let chain: [NSControl] = [prevButton, dateButton, nextButton, categorySegmented, startPicker, endPicker, durationField, addButton, deleteButton]
        chain.forEach { $0.refusesFirstResponder = false }
        for (i, view) in chain.enumerated() {
            view.nextKeyView = chain[(i + 1) % chain.count]
        }
        window?.initialFirstResponder = prevButton
    }

    private func formLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        l.textColor = .secondaryLabelColor
        return l
    }
}
