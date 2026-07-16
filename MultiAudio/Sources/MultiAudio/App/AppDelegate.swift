import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var cancellables = Set<AnyCancellable>()

    let devices = AudioDeviceService()
    let sessions = SessionStore()
    let settings = SettingsStore()
    lazy var controller = SessionController(
        devices: devices,
        sessions: sessions,
        settings: settings
    )

    private var mainWindow: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        bindStatusUpdates()
        rebuildMenu()

        // Open main window on first launch so the user understands the app.
        showMainWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    // MARK: - Status item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "waveform.circle",
                accessibilityDescription: "MultiAudio"
            )
            button.image?.isTemplate = true
            button.toolTip = "MultiAudio"
        }
        statusItem.menu = NSMenu()
    }

    private func bindStatusUpdates() {
        controller.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.updateStatusIcon()
            }
            .store(in: &cancellables)

        devices.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        sessions.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)
    }

    private func updateStatusIcon() {
        let name = controller.isActive ? "waveform.circle.fill" : "waveform.circle"
        statusItem.button?.image = NSImage(
            systemSymbolName: name,
            accessibilityDescription: controller.isActive ? "MultiAudio active" : "MultiAudio"
        )
        statusItem.button?.image?.isTemplate = true
    }

    // MARK: - Menu

    func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Header
        let header = NSMenuItem(
            title: controller.isActive
                ? "● \(controller.statusMessage)"
                : "MultiAudio — \(controller.statusMessage)",
            action: nil,
            keyEquivalent: ""
        )
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())

        if controller.isActive {
            if let state = controller.activeState {
                let active = NSMenuItem(
                    title: "Active: \(state.sessionName)",
                    action: nil,
                    keyEquivalent: ""
                )
                active.isEnabled = false
                menu.addItem(active)
            }

            let reconnect = NSMenuItem(
                title: "Reconnect",
                action: #selector(reconnectSession),
                keyEquivalent: "r"
            )
            reconnect.keyEquivalentModifierMask = [.command, .shift]
            reconnect.target = self
            menu.addItem(reconnect)

            let stop = NSMenuItem(
                title: "Stop Session",
                action: #selector(stopSession),
                keyEquivalent: "s"
            )
            stop.keyEquivalentModifierMask = [.command, .shift]
            stop.target = self
            menu.addItem(stop)
            menu.addItem(.separator())
        }

        // Devices
        let devicesHeader = NSMenuItem(title: "Devices", action: nil, keyEquivalent: "")
        devicesHeader.isEnabled = false
        menu.addItem(devicesHeader)

        let selectable = devices.selectableDevices
        if selectable.isEmpty {
            let empty = NSMenuItem(title: "  No output devices found", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        } else {
            for device in selectable {
                let item = NSMenuItem(
                    title: "  \(device.name)",
                    action: #selector(toggleDevice(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = device.uid
                item.state = controller.isSelected(device.uid) ? .on : .off
                item.isEnabled = !controller.isActive
                item.toolTip = "\(device.transport.displayName) · \(Int(device.sampleRate)) Hz"
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        if !controller.isActive {
            let start = NSMenuItem(
                title: "Start Multi-Output",
                action: #selector(startSession),
                keyEquivalent: "s"
            )
            start.keyEquivalentModifierMask = [.command, .shift]
            start.target = self
            start.isEnabled = controller.selectedDeviceUIDs.count >= 2
            menu.addItem(start)

            let save = NSMenuItem(
                title: "Save Selection as Session…",
                action: #selector(saveSession),
                keyEquivalent: ""
            )
            save.target = self
            save.isEnabled = controller.selectedDeviceUIDs.count >= 2
            menu.addItem(save)
            menu.addItem(.separator())
        }

        // Sessions
        if !sessions.sessions.isEmpty {
            let sessionsHeader = NSMenuItem(title: "Sessions", action: nil, keyEquivalent: "")
            sessionsHeader.isEnabled = false
            menu.addItem(sessionsHeader)

            for session in sessions.sessions.prefix(8) {
                let item = NSMenuItem(
                    title: "  \(session.isFavorite ? "★ " : "")\(session.name)",
                    action: #selector(startSavedSession(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = session.id.uuidString
                item.isEnabled = session.isValid
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }

        if let error = controller.lastError {
            let err = NSMenuItem(title: "⚠ \(error.localizedDescription)", action: #selector(clearError), keyEquivalent: "")
            err.target = self
            menu.addItem(err)
            menu.addItem(.separator())
        }

        let open = NSMenuItem(title: "Open MultiAudio…", action: #selector(showMainWindow), keyEquivalent: "o")
        open.keyEquivalentModifierMask = [.command]
        open.target = self
        menu.addItem(open)

        let refresh = NSMenuItem(title: "Refresh Devices", action: #selector(refreshDevices), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit MultiAudio", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        mainWindow?.reload()
    }

    // MARK: - Actions

    @objc private func toggleDevice(_ sender: NSMenuItem) {
        guard let uid = sender.representedObject as? String else { return }
        controller.toggleSelection(uid)
        rebuildMenu()
    }

    @objc private func startSession() {
        controller.startQuickSession()
        rebuildMenu()
        updateStatusIcon()
    }

    @objc private func stopSession() {
        controller.stop()
        rebuildMenu()
        updateStatusIcon()
    }

    @objc private func reconnectSession() {
        controller.reconnect()
        rebuildMenu()
    }

    @objc private func startSavedSession(_ sender: NSMenuItem) {
        guard let idString = sender.representedObject as? String,
              let id = UUID(uuidString: idString),
              let session = sessions.session(id: id) else { return }

        if controller.isActive {
            controller.stop()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.controller.start(session: session)
            self?.rebuildMenu()
            self?.updateStatusIcon()
        }
    }

    @objc private func saveSession() {
        let alert = NSAlert()
        alert.messageText = "Save Session"
        alert.informativeText = "Name this multi-output setup for one-click reuse."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        let names = controller.selectedDeviceUIDs.compactMap { devices.device(uid: $0)?.name }
        field.stringValue = names.count >= 2 ? "\(names[0]) + \(names[1])" : "Movie Night"
        alert.accessoryView = field

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                _ = controller.saveCurrentSelectionAsSession(name: name)
                rebuildMenu()
            }
        }
    }

    @objc private func refreshDevices() {
        devices.refresh()
        rebuildMenu()
    }

    @objc private func clearError() {
        controller.clearError()
        rebuildMenu()
    }

    @objc func showMainWindow() {
        if mainWindow == nil {
            mainWindow = MainWindowController(
                devices: devices,
                sessions: sessions,
                settings: settings,
                controller: controller,
                onChange: { [weak self] in
                    self?.rebuildMenu()
                    self?.updateStatusIcon()
                }
            )
        }
        mainWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Temporarily show in Dock while window is open
        NSApp.setActivationPolicy(.regular)
    }

    @objc private func quitApp() {
        controller.shutdown()
        NSApp.terminate(nil)
    }
}
