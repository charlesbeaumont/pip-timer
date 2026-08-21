import AppKit

final class AddEntryWindow: NSWindowController {
    var onAdd: ((WorkCategory, Date, Date) -> Void)?

    private let dateButton = NSButton()
    private let datePopover = NSPopover()
    private let calendarPicker = NSDatePicker()
    private var selectedDate = Date()

    private let categorySegmented: NSSegmentedControl
    private let endTimePicker = NSDatePicker()
    private let durationStepper = NSStepper()
    private let durationField = NSTextField()
    private let addButton = NSButton()
    private let cancelButton = NSButton()

    init() {
        categorySegmented = NSSegmentedControl(
            labels: WorkCategory.allCases.map { $0.displayName },
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add tracking entry"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        setupUI()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func presentWithDefaults(lastCategory: WorkCategory?) {
        let now = Date()
        selectedDate = now
        updateDateButtonLabel()
        calendarPicker.dateValue = now
        endTimePicker.dateValue = now
        durationStepper.integerValue = 60
        durationField.integerValue = 60
        let idx = lastCategory.flatMap { WorkCategory.allCases.firstIndex(of: $0) } ?? 0
        categorySegmented.selectedSegment = idx
        validate()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        showWindow(nil)
        window?.makeFirstResponder(durationField)
    }

    private func setupUI() {
        // Date button — opens a popover with the calendar picker.
        // .roundRect matches the height of NSDatePicker / NSSegmentedControl
        // (~22pt) so the row sits flush with the others.
        dateButton.bezelStyle = .roundRect
        dateButton.title = ""
        dateButton.alignment = .left
        dateButton.target = self
        dateButton.action = #selector(showDatePopover)
        dateButton.translatesAutoresizingMaskIntoConstraints = false
        dateButton.widthAnchor.constraint(equalToConstant: 220).isActive = true

        // Calendar picker (lives inside the popover).
        calendarPicker.datePickerStyle = .clockAndCalendar
        calendarPicker.datePickerElements = [.yearMonthDay]
        calendarPicker.dateValue = Date()
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

        // Category.
        categorySegmented.segmentStyle = .rounded
        categorySegmented.translatesAutoresizingMaskIntoConstraints = false
        categorySegmented.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // End time.
        endTimePicker.datePickerStyle = .textFieldAndStepper
        endTimePicker.datePickerElements = [.hourMinute]
        endTimePicker.dateValue = Date()
        endTimePicker.target = self
        endTimePicker.action = #selector(controlChanged)

        // Duration: stepper + field + "minutes".
        durationStepper.minValue = 5
        durationStepper.maxValue = 720
        durationStepper.increment = 5
        durationStepper.integerValue = 60
        durationStepper.target = self
        durationStepper.action = #selector(stepperChanged)

        let nf = NumberFormatter()
        nf.allowsFloats = false
        nf.minimum = 1
        nf.maximum = 720
        durationField.formatter = nf
        durationField.integerValue = 60
        durationField.alignment = .right
        durationField.target = self
        durationField.action = #selector(fieldChanged)
        durationField.translatesAutoresizingMaskIntoConstraints = false
        durationField.widthAnchor.constraint(equalToConstant: 56).isActive = true

        let minutesLabel = NSTextField(labelWithString: "minutes")
        minutesLabel.textColor = .secondaryLabelColor
        let durationRow = NSStackView(views: [durationField, durationStepper, minutesLabel])
        durationRow.orientation = .horizontal
        durationRow.alignment = .centerY
        durationRow.spacing = 6

        // Buttons.
        addButton.title = "Add entry"
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.target = self
        addButton.action = #selector(addTapped)

        cancelButton.title = "Cancel"
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)

        // Form layout: NSGridView is the cleanest way to align label-control pairs.
        let grid = NSGridView(views: [
            [formLabel("Date"),     dateButton],
            [formLabel("Category"), categorySegmented],
            [formLabel("End time"), endTimePicker],
            [formLabel("Duration"), durationRow],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 80
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 16
        grid.rowSpacing = 20

        // Trailing-aligned button row: Cancel then Add.
        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12
        buttonRow.addView(cancelButton, in: .trailing)
        buttonRow.addView(addButton, in: .trailing)

        // Outer container with generous insets.
        let main = NSStackView(views: [grid, buttonRow])
        main.orientation = .vertical
        main.spacing = 28
        main.alignment = .leading
        main.edgeInsets = NSEdgeInsets(top: 28, left: 36, bottom: 24, right: 36)
        main.translatesAutoresizingMaskIntoConstraints = false

        let host = NSView()
        host.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: host.topAnchor),
            main.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            main.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            buttonRow.trailingAnchor.constraint(equalTo: main.trailingAnchor, constant: -36),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: main.trailingAnchor, constant: -36),
        ])
        window?.contentView = host
        updateDateButtonLabel()

        // Tab chain: macOS skips non-text controls unless we opt them in
        // explicitly. Set refusesFirstResponder=false on each control we
        // want focusable, then wire next/previous as a cycle.
        [dateButton, categorySegmented, endTimePicker, durationField, cancelButton, addButton]
            .forEach { $0.refusesFirstResponder = false }
        let chain: [NSView] = [dateButton, categorySegmented, endTimePicker, durationField, cancelButton, addButton]
        for (i, view) in chain.enumerated() {
            view.nextKeyView = chain[(i + 1) % chain.count]
        }
        window?.initialFirstResponder = dateButton
    }

    private func formLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        l.textColor = .secondaryLabelColor
        return l
    }

    static func dayLabel(for date: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let selected = cal.startOfDay(for: date)
        let daysAgo = cal.dateComponents([.day], from: selected, to: today).day ?? 0
        if daysAgo == 0 { return "Today" }
        if daysAgo == 1 { return "Yesterday" }
        let f = DateFormatter()
        if (2...6).contains(daysAgo) {
            f.dateFormat = "EEEE, MMM d"
        } else {
            f.dateStyle = .long
            f.timeStyle = .none
        }
        return f.string(from: date)
    }

    private func updateDateButtonLabel() {
        dateButton.title = Self.dayLabel(for: selectedDate)
    }

    @objc private func showDatePopover() {
        calendarPicker.dateValue = selectedDate
        datePopover.show(relativeTo: dateButton.bounds, of: dateButton, preferredEdge: .maxY)
    }

    @objc private func calendarPickerChanged() {
        selectedDate = calendarPicker.dateValue
        updateDateButtonLabel()
        validate()
    }

    @objc private func stepperChanged() {
        durationField.integerValue = durationStepper.integerValue
        validate()
    }

    @objc private func fieldChanged() {
        durationStepper.integerValue = durationField.integerValue
        validate()
    }

    @objc private func controlChanged() { validate() }

    private func validate() {
        addButton.isEnabled = durationField.integerValue > 0
    }

    @objc private func addTapped() {
        let categories = WorkCategory.allCases
        let segIndex = categorySegmented.selectedSegment
        guard segIndex >= 0, segIndex < categories.count else { return }
        let category = categories[segIndex]

        let cal = Calendar.current
        let endTimeOfDay = endTimePicker.dateValue
        var combined = cal.dateComponents([.year, .month, .day], from: selectedDate)
        let hm = cal.dateComponents([.hour, .minute], from: endTimeOfDay)
        combined.hour = hm.hour
        combined.minute = hm.minute
        guard let end = cal.date(from: combined) else { return }
        let durationSeconds = TimeInterval(durationField.integerValue * 60)
        let start = end.addingTimeInterval(-durationSeconds)

        onAdd?(category, start, end)
        close()
    }

    @objc private func cancelTapped() {
        close()
    }
}
