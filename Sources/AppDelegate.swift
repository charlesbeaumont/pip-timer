import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let timer = TimerController()
    private var tick: Timer?
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "RutTimerStatusItem"
        statusItem.isVisible = true
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        buildMenu()
        menu.delegate = self

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )

        tick = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.updateDisplay() }
        RunLoop.main.add(tick!, forMode: .common)
        updateDisplay()
    }

    @objc private func handleClick(_ sender: Any?) {
        guard let event = NSApp.currentEvent else { return }
        if event.type == .rightMouseUp {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            timer.reset()
            updateDisplay()
        }
    }

    @objc private func handleWake() {
        timer.reset()
        updateDisplay()
    }

    private func updateDisplay() {
        guard let button = statusItem.button else { return }
        let state = timer.colorState
        let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .black)
            .applying(.init(paletteColors: [state.color]))
        let image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Rut Timer")?
            .withSymbolConfiguration(config)
        image?.isTemplate = false
        button.image = image
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.toolTip = "Rut Timer — click to reset"
        button.setAccessibilityLabel("Rut Timer")
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.title = " " + TimerController.formatElapsed(timer.elapsed)
    }

    // MARK: - Menu

    private func buildMenu() {
        menu.removeAllItems()
        menu.addItem(withTitle: "Reset", action: #selector(menuReset), keyEquivalent: "").target = self

        let intervalItem = NSMenuItem(title: "Interval", action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu(title: "Interval")
        for minutes in TimerController.intervalOptions {
            let item = NSMenuItem(
                title: "\(minutes) minutes",
                action: #selector(menuPickInterval(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = minutes
            item.state = (minutes == timer.intervalMinutes) ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        let launchItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(menuToggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchItem.target = self
        launchItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "About Rut Timer", action: #selector(menuAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit", action: #selector(menuQuit), keyEquivalent: "q").target = self
    }

    func menuWillOpen(_ menu: NSMenu) {
        buildMenu()
    }

    @objc private func menuReset() {
        timer.reset()
        updateDisplay()
    }

    @objc private func menuPickInterval(_ sender: NSMenuItem) {
        timer.intervalMinutes = sender.tag
        updateDisplay()
    }

    @objc private func menuToggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
        }
    }

    @objc private func menuAbout() {
        let info = Bundle.main.infoDictionary ?? [:]
        let name = info["CFBundleName"] as? String ?? "Rut Timer"
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let alert = NSAlert()
        alert.messageText = name
        alert.informativeText = "Version \(version)\n\nAn ambient stand-up reminder for the menu bar."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }
}
