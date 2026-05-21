import AppKit

final class AddEntryWindow: NSWindowController {
    var onAdd: ((WorkCategory, Date, Date) -> Void)?

    private let datePicker = NSDatePicker()
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
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 200),
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
        datePicker.dateValue = now
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
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.dateValue = Date()

        categorySegmented.segmentStyle = .rounded

        endTimePicker.datePickerStyle = .textFieldAndStepper
        endTimePicker.datePickerElements = [.hourMinute]
        endTimePicker.dateValue = Date()
        endTimePicker.target = self
        endTimePicker.action = #selector(controlChanged)

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

        let minLabel = NSTextField(labelWithString: "min")
        minLabel.textColor = .secondaryLabelColor
        let durationRow = NSStackView(views: [durationField, durationStepper, minLabel])
        durationRow.orientation = .horizontal
        durationRow.alignment = .firstBaseline
        durationRow.spacing = 4

        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "Date"),     datePicker],
            [NSTextField(labelWithString: "Category"), categorySegmented],
            [NSTextField(labelWithString: "End time"), endTimePicker],
            [NSTextField(labelWithString: "Duration"), durationRow],
        ])
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.columnSpacing = 12
        grid.rowSpacing = 10

        let buttonRow = NSStackView(views: [NSView(), cancelButton, addButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.distribution = .fill

        let main = NSStackView(views: [grid, buttonRow])
        main.orientation = .vertical
        main.spacing = 18
        main.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        main.translatesAutoresizingMaskIntoConstraints = false

        let host = NSView()
        host.addSubview(main)
        NSLayoutConstraint.activate([
            main.topAnchor.constraint(equalTo: host.topAnchor),
            main.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            main.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            main.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        window?.contentView = host
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
        let minutes = durationField.integerValue
        addButton.isEnabled = minutes > 0
    }

    @objc private func addTapped() {
        let categories = WorkCategory.allCases
        let segIndex = categorySegmented.selectedSegment
        guard segIndex >= 0, segIndex < categories.count else { return }
        let category = categories[segIndex]

        let cal = Calendar.current
        let date = datePicker.dateValue
        let endTimeOfDay = endTimePicker.dateValue
        var combined = cal.dateComponents([.year, .month, .day], from: date)
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
