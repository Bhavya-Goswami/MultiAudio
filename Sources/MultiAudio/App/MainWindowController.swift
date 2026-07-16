import AppKit

/// Main management window: device selection, sessions, start/stop.
final class MainWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let devices: AudioDeviceService
    private let sessions: SessionStore
    private let settings: SettingsStore
    private let controller: SessionController
    private let onChange: () -> Void

    private var tableView: NSTableView!
    private var sessionTable: NSTableView!
    private var statusLabel: NSTextField!
    private var startStopButton: NSButton!
    private var saveButton: NSButton!
    private var reconnectButton: NSButton!
    private var driftCheckbox: NSButton!
    private var restoreCheckbox: NSButton!

    private var displayedDevices: [AudioDeviceInfo] = []
    private var displayedSessions: [AudioSession] = []

    init(
        devices: AudioDeviceService,
        sessions: SessionStore,
        settings: SettingsStore,
        controller: SessionController,
        onChange: @escaping () -> Void
    ) {
        self.devices = devices
        self.sessions = sessions
        self.settings = settings
        self.controller = controller
        self.onChange = onChange

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MultiAudio"
        window.minSize = NSSize(width: 640, height: 420)
        window.center()
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor

        super.init(window: window)
        window.contentView = buildContent()
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reload() {
        displayedDevices = devices.selectableDevices
        displayedSessions = sessions.sessions
        tableView?.reloadData()
        sessionTable?.reloadData()
        updateChrome()
    }

    // MARK: - UI construction

    private func buildContent() -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 520))

        // Header
        let title = makeLabel("Share audio to multiple devices", font: .systemFont(ofSize: 20, weight: .semibold))
        let subtitle = makeLabel(
            "Select two or more outputs, then start. Works with Netflix, Spotify, Safari, VLC, and more.",
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        subtitle.maximumNumberOfLines = 2

        statusLabel = makeLabel("Ready", font: .systemFont(ofSize: 12, weight: .medium))

        startStopButton = NSButton(title: "Start Multi-Output", target: self, action: #selector(toggleSession))
        startStopButton.bezelStyle = .rounded
        startStopButton.keyEquivalent = "\r"

        reconnectButton = NSButton(title: "Reconnect", target: self, action: #selector(reconnect))
        reconnectButton.bezelStyle = .rounded

        saveButton = NSButton(title: "Save Session…", target: self, action: #selector(saveSession))
        saveButton.bezelStyle = .rounded

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        refreshButton.bezelStyle = .rounded

        // Device table
        tableView = makeTable(columns: [
            ("check", "", 28),
            ("name", "Device", 220),
            ("type", "Type", 110),
            ("rate", "Sample Rate", 100),
            ("channels", "Ch", 40)
        ])
        tableView.dataSource = self
        tableView.delegate = self
        tableView.doubleAction = #selector(doubleClickDevice)
        tableView.target = self

        let deviceScroll = NSScrollView()
        deviceScroll.hasVerticalScroller = true
        deviceScroll.borderType = .bezelBorder
        deviceScroll.documentView = tableView
        deviceScroll.drawsBackground = true

        // Session table
        sessionTable = makeTable(columns: [
            ("fav", "", 28),
            ("name", "Session", 200),
            ("devices", "Devices", 280),
            ("action", "", 70)
        ])
        sessionTable.dataSource = self
        sessionTable.delegate = self
        sessionTable.doubleAction = #selector(doubleClickSession)
        sessionTable.target = self

        let sessionScroll = NSScrollView()
        sessionScroll.hasVerticalScroller = true
        sessionScroll.borderType = .bezelBorder
        sessionScroll.documentView = sessionTable

        // Settings strip
        driftCheckbox = NSButton(
            checkboxWithTitle: "Drift correction (recommended for Bluetooth)",
            target: self,
            action: #selector(toggleDrift)
        )
        driftCheckbox.state = settings.enableDriftCorrectionByDefault ? .on : .off

        restoreCheckbox = NSButton(
            checkboxWithTitle: "Restore previous output when stopping",
            target: self,
            action: #selector(toggleRestore)
        )
        restoreCheckbox.state = settings.restoreOutputOnStop ? .on : .off

        let deviceLabel = makeLabel("OUTPUT DEVICES", font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor)
        let sessionLabel = makeLabel("SAVED SESSIONS", font: .systemFont(ofSize: 11, weight: .semibold), color: .secondaryLabelColor)
        let systemLabel = makeLabel("", font: .systemFont(ofSize: 11), color: .tertiaryLabelColor)
        systemLabel.identifier = NSUserInterfaceItemIdentifier("systemOutput")

        let allViews: [NSView] = [
            title, subtitle, statusLabel, startStopButton, reconnectButton, saveButton,
            refreshButton, deviceLabel, deviceScroll, sessionLabel, sessionScroll,
            driftCheckbox, restoreCheckbox
        ]
        for view in allViews {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),

            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 4),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            startStopButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            startStopButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            reconnectButton.centerYAnchor.constraint(equalTo: startStopButton.centerYAnchor),
            reconnectButton.trailingAnchor.constraint(equalTo: startStopButton.leadingAnchor, constant: -8),

            saveButton.centerYAnchor.constraint(equalTo: startStopButton.centerYAnchor),
            saveButton.trailingAnchor.constraint(equalTo: reconnectButton.leadingAnchor, constant: -8),

            refreshButton.centerYAnchor.constraint(equalTo: startStopButton.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: saveButton.leadingAnchor, constant: -8),

            statusLabel.topAnchor.constraint(equalTo: subtitle.bottomAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),

            deviceLabel.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 16),
            deviceLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            deviceScroll.topAnchor.constraint(equalTo: deviceLabel.bottomAnchor, constant: 6),
            deviceScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            deviceScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            deviceScroll.heightAnchor.constraint(equalToConstant: 180),

            sessionLabel.topAnchor.constraint(equalTo: deviceScroll.bottomAnchor, constant: 16),
            sessionLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),

            sessionScroll.topAnchor.constraint(equalTo: sessionLabel.bottomAnchor, constant: 6),
            sessionScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 20),
            sessionScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -20),
            sessionScroll.bottomAnchor.constraint(equalTo: driftCheckbox.topAnchor, constant: -16),

            driftCheckbox.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            driftCheckbox.bottomAnchor.constraint(equalTo: restoreCheckbox.topAnchor, constant: -6),

            restoreCheckbox.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            restoreCheckbox.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16)
        ])

        return root
    }

    private func makeLabel(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = color
        label.lineBreakMode = .byWordWrapping
        return label
    }

    private func makeTable(columns: [(id: String, title: String, width: CGFloat)]) -> NSTableView {
        let table = NSTableView()
        table.headerView = NSTableHeaderView()
        table.rowHeight = 28
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = false
        table.style = .inset
        for col in columns {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.id))
            column.title = col.title
            column.width = col.width
            column.minWidth = col.width * 0.6
            table.addTableColumn(column)
        }
        return table
    }

    private func updateChrome() {
        if controller.isActive {
            startStopButton.title = "Stop"
            startStopButton.contentTintColor = .systemRed
            reconnectButton.isEnabled = true
            saveButton.isEnabled = false
            statusLabel.stringValue = "● \(controller.statusMessage)  ·  System output: \(devices.defaultOutputName)"
            statusLabel.textColor = .systemGreen
        } else {
            startStopButton.title = "Start Multi-Output"
            startStopButton.contentTintColor = nil
            startStopButton.isEnabled = controller.selectedDeviceUIDs.count >= 2
            reconnectButton.isEnabled = false
            saveButton.isEnabled = controller.selectedDeviceUIDs.count >= 2
            if let error = controller.lastError {
                statusLabel.stringValue = "⚠ \(error.localizedDescription)"
                statusLabel.textColor = .systemRed
            } else {
                let count = controller.selectedDeviceUIDs.count
                statusLabel.stringValue = count == 0
                    ? "Select at least two devices to begin.  Current output: \(devices.defaultOutputName)"
                    : "\(count) device(s) selected.  Current output: \(devices.defaultOutputName)"
                statusLabel.textColor = .secondaryLabelColor
            }
        }
    }

    // MARK: - Actions

    @objc private func toggleSession() {
        if controller.isActive {
            controller.stop()
        } else {
            controller.startQuickSession()
        }
        reload()
        onChange()
    }

    @objc private func reconnect() {
        controller.reconnect()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.reload()
            self?.onChange()
        }
    }

    @objc private func saveSession() {
        let alert = NSAlert()
        alert.messageText = "Save Session"
        alert.informativeText = "Give this multi-output setup a name."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        let names = controller.selectedDeviceUIDs.compactMap { devices.device(uid: $0)?.name }
        field.stringValue = names.count >= 2 ? "\(names[0]) + \(names[1])" : "Movie Night"
        alert.accessoryView = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                _ = controller.saveCurrentSelectionAsSession(name: name)
                reload()
                onChange()
            }
        }
    }

    @objc private func refresh() {
        devices.refresh()
        reload()
        onChange()
    }

    @objc private func toggleDrift() {
        settings.enableDriftCorrectionByDefault = driftCheckbox.state == .on
    }

    @objc private func toggleRestore() {
        settings.restoreOutputOnStop = restoreCheckbox.state == .on
    }

    @objc private func doubleClickDevice() {
        let row = tableView.clickedRow
        guard row >= 0, row < displayedDevices.count, !controller.isActive else { return }
        controller.toggleSelection(displayedDevices[row].uid)
        reload()
        onChange()
    }

    @objc private func doubleClickSession() {
        let row = sessionTable.clickedRow
        guard row >= 0, row < displayedSessions.count else { return }
        let session = displayedSessions[row]
        if controller.isActive { controller.stop() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.controller.start(session: session)
            self?.reload()
            self?.onChange()
        }
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === self.tableView {
            return displayedDevices.count
        }
        return displayedSessions.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = tableColumn?.identifier.rawValue ?? ""

        if tableView === self.tableView {
            guard row < displayedDevices.count else { return nil }
            let device = displayedDevices[row]
            let text: String
            switch id {
            case "check":
                text = controller.isSelected(device.uid) ? "✓" : ""
            case "name":
                text = device.name
            case "type":
                text = device.transport.displayName
            case "rate":
                text = device.sampleRate > 0 ? "\(Int(device.sampleRate)) Hz" : "—"
            case "channels":
                text = "\(device.channelCount)"
            default:
                text = ""
            }
            return cell(text, bold: id == "name" && controller.isSelected(device.uid))
        } else {
            guard row < displayedSessions.count else { return nil }
            let session = displayedSessions[row]
            let text: String
            switch id {
            case "fav":
                text = session.isFavorite ? "★" : ""
            case "name":
                text = session.name
            case "devices":
                text = session.deviceUIDs.compactMap { devices.device(uid: $0)?.name }.joined(separator: " · ")
            case "action":
                text = controller.activeState?.sessionID == session.id ? "Active" : "Start"
            default:
                text = ""
            }
            return cell(text, bold: id == "name")
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard let table = notification.object as? NSTableView else { return }
        if table === tableView, !controller.isActive {
            let row = table.selectedRow
            guard row >= 0, row < displayedDevices.count else { return }
            controller.toggleSelection(displayedDevices[row].uid)
            table.deselectAll(nil)
            reload()
            onChange()
        } else if table === sessionTable {
            let row = table.selectedRow
            guard row >= 0, row < displayedSessions.count else { return }
            // Single-click starts only via double-click or explicit; selection just highlights.
        }
    }

    private func cell(_ text: String, bold: Bool = false) -> NSTableCellView {
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: text)
        field.font = bold ? .systemFont(ofSize: 12, weight: .medium) : .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }
}
