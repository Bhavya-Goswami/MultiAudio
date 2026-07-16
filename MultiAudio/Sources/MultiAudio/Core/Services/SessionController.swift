import Foundation
import CoreAudio
import Combine

/// Orchestrates start/stop of multi-output sessions and system default routing.
final class SessionController: ObservableObject {
    @Published private(set) var activeState: ActiveSessionState?
    @Published private(set) var lastError: MultiAudioError?
    @Published private(set) var statusMessage: String = "Ready"
    @Published var selectedDeviceUIDs: Set<String> = []

    var isActive: Bool { activeState != nil }

    private let multiOutput = MultiOutputDeviceService()
    private let devices: AudioDeviceService
    private let sessions: SessionStore
    private let settings: SettingsStore

    init(
        devices: AudioDeviceService,
        sessions: SessionStore,
        settings: SettingsStore
    ) {
        self.devices = devices
        self.sessions = sessions
        self.settings = settings
        multiOutput.cleanupOrphanedDevices()
    }

    // MARK: - Selection

    func toggleSelection(_ uid: String) {
        if selectedDeviceUIDs.contains(uid) {
            selectedDeviceUIDs.remove(uid)
        } else {
            selectedDeviceUIDs.insert(uid)
        }
    }

    func isSelected(_ uid: String) -> Bool {
        selectedDeviceUIDs.contains(uid)
    }

    // MARK: - Start / Stop

    func startQuickSession() {
        let uids = Array(selectedDeviceUIDs)
        start(
            name: Self.defaultName(for: uids, devices: devices),
            deviceUIDs: uids,
            sessionID: nil,
            enableDrift: settings.enableDriftCorrectionByDefault
        )
    }

    func start(session: AudioSession) {
        start(
            name: session.name,
            deviceUIDs: session.deviceUIDs,
            sessionID: session.id,
            masterUID: session.masterDeviceUID,
            enableDrift: session.enableDriftCorrection
        )
    }

    func start(
        name: String,
        deviceUIDs: [String],
        sessionID: UUID?,
        masterUID: String? = nil,
        enableDrift: Bool = true
    ) {
        lastError = nil

        guard !isActive else {
            lastError = .alreadyActive
            statusMessage = lastError?.localizedDescription ?? ""
            return
        }

        guard deviceUIDs.count >= 2 else {
            lastError = .needAtLeastTwoDevices
            statusMessage = lastError?.localizedDescription ?? ""
            return
        }

        // Resolve devices — fail early if any are missing.
        for uid in deviceUIDs {
            if devices.device(uid: uid) == nil {
                devices.refresh()
                if devices.device(uid: uid) == nil {
                    lastError = .deviceNotFound(uid)
                    statusMessage = lastError?.localizedDescription ?? ""
                    return
                }
            }
        }

        do {
            let previousDefaultUID = devices.defaultOutputUID

            let created = try multiOutput.create(
                .init(
                    name: name,
                    deviceUIDs: deviceUIDs,
                    masterDeviceUID: masterUID,
                    enableDriftCorrection: enableDrift,
                    isPrivate: false
                )
            )

            // Route all system audio through the multi-output device.
            try AudioDeviceService.setDefaultOutputDeviceID(created.deviceID)

            activeState = ActiveSessionState(
                sessionID: sessionID,
                sessionName: name,
                multiOutputDeviceID: created.deviceID,
                multiOutputUID: created.uid,
                deviceUIDs: deviceUIDs,
                previousDefaultOutputUID: previousDefaultUID,
                startedAt: Date()
            )
            selectedDeviceUIDs = Set(deviceUIDs)
            statusMessage = "Sharing to \(deviceUIDs.count) devices"
            devices.refresh()
        } catch let error as MultiAudioError {
            lastError = error
            statusMessage = error.localizedDescription
            // Best-effort cleanup if aggregate was half-created.
            multiOutput.cleanupOrphanedDevices()
        } catch {
            lastError = .createAggregateFailed(-1)
            statusMessage = error.localizedDescription
            multiOutput.cleanupOrphanedDevices()
        }
    }

    func stop() {
        lastError = nil
        guard let state = activeState else {
            lastError = .notActive
            return
        }

        // Restore previous default first so audio never goes silent longer than necessary.
        if settings.restoreOutputOnStop, let previous = state.previousDefaultOutputUID {
            try? AudioDeviceService.setDefaultOutput(uid: previous)
        } else if let fallback = devices.selectableDevices.first {
            try? AudioDeviceService.setDefaultOutputDeviceID(fallback.id)
        }

        do {
            try multiOutput.destroy(deviceID: state.multiOutputDeviceID)
        } catch {
            // Try by UID if ID is stale after sleep/wake.
            try? multiOutput.destroy(uid: state.multiOutputUID)
        }

        activeState = nil
        statusMessage = "Stopped"
        devices.refresh()
    }

    func toggleQuickSession() {
        if isActive {
            stop()
        } else {
            startQuickSession()
        }
    }

    /// Save current selection as a named session.
    @discardableResult
    func saveCurrentSelectionAsSession(name: String) -> AudioSession? {
        let uids = Array(selectedDeviceUIDs)
        guard uids.count >= 2 else {
            lastError = .needAtLeastTwoDevices
            return nil
        }
        return sessions.create(
            name: name,
            deviceUIDs: uids,
            enableDriftCorrection: settings.enableDriftCorrectionByDefault
        )
    }

    /// Reconnect: stop and restart with the same configuration (handles device dropouts).
    func reconnect() {
        guard let state = activeState else { return }
        let name = state.sessionName
        let uids = state.deviceUIDs
        let sessionID = state.sessionID
        let enableDrift = sessionID.flatMap { sessions.session(id: $0)?.enableDriftCorrection }
            ?? settings.enableDriftCorrectionByDefault

        stop()
        // Brief delay for HAL cleanup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.start(
                name: name,
                deviceUIDs: uids,
                sessionID: sessionID,
                enableDrift: enableDrift
            )
        }
    }

    func setVolume(forDeviceUID uid: String, scalar: Float) {
        guard let device = devices.device(uid: uid) else { return }
        do {
            try AudioDeviceService.setVolume(for: device.id, scalar: scalar)
            devices.refresh()
        } catch let error as MultiAudioError {
            lastError = error
        } catch {
            lastError = .devicePropertyFailed("volume", -1)
        }
    }

    func clearError() {
        lastError = nil
    }

    /// Tear down on quit.
    func shutdown() {
        if isActive {
            stop()
        }
        multiOutput.cleanupOrphanedDevices()
    }

    private static func defaultName(for uids: [String], devices: AudioDeviceService) -> String {
        let names = uids.compactMap { devices.device(uid: $0)?.name }
        if names.count == 2 {
            return "\(names[0]) + \(names[1])"
        }
        if names.count > 2 {
            return "\(names[0]) + \(names.count - 1) more"
        }
        return "Quick Session"
    }
}
