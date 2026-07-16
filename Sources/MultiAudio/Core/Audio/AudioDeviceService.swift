import Foundation
import CoreAudio
import Combine

/// Enumerates Core Audio devices and observes hardware changes.
final class AudioDeviceService: ObservableObject {
    @Published private(set) var devices: [AudioDeviceInfo] = []
    @Published private(set) var defaultOutputUID: String?
    @Published private(set) var defaultOutputName: String = "—"

    private var hardwareListenerBlock: AudioObjectPropertyListenerBlock?
    private var defaultOutputListenerBlock: AudioObjectPropertyListenerBlock?

    /// Output-capable devices that are not MultiAudio-managed aggregates.
    var selectableDevices: [AudioDeviceInfo] {
        devices.filter { device in
            device.channelCount > 0
                && device.isAlive
                && !device.uid.hasPrefix(MultiOutputDeviceService.uidPrefix)
                && !device.name.hasPrefix(MultiOutputDeviceService.namePrefix)
        }
    }

    var bluetoothDevices: [AudioDeviceInfo] {
        selectableDevices.filter(\.isBluetooth)
    }

    init() {
        refresh()
        startListening()
    }

    func refresh() {
        do {
            devices = try Self.fetchAllOutputDevices()
            if let defaultID = try? Self.defaultOutputDeviceID() {
                defaultOutputUID = try? CoreAudioHelpers.getString(
                    objectID: defaultID,
                    selector: kAudioDevicePropertyDeviceUID
                )
                defaultOutputName = (try? CoreAudioHelpers.getString(
                    objectID: defaultID,
                    selector: kAudioObjectPropertyName
                )) ?? "—"
            } else {
                defaultOutputUID = nil
                defaultOutputName = "—"
            }
        } catch {
            devices = []
        }
    }

    func device(uid: String) -> AudioDeviceInfo? {
        devices.first { $0.uid == uid }
    }

    func deviceID(forUID uid: String) throws -> AudioObjectID {
        if let match = devices.first(where: { $0.uid == uid }) {
            return match.id
        }
        // Refresh once in case the device just connected.
        refresh()
        if let match = devices.first(where: { $0.uid == uid }) {
            return match.id
        }
        throw MultiAudioError.deviceNotFound(uid)
    }

    // MARK: - Listening

    private func startListening() {
        let hardwareBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        let defaultBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        hardwareListenerBlock = hardwareBlock
        defaultOutputListenerBlock = defaultBlock

        var devicesAddr = CoreAudioHelpers.address(kAudioHardwarePropertyDevices)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddr,
            DispatchQueue.main,
            hardwareBlock
        )

        var defaultAddr = CoreAudioHelpers.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddr,
            DispatchQueue.main,
            defaultBlock
        )
    }

    // MARK: - Static queries

    nonisolated static func defaultOutputDeviceID() throws -> AudioObjectID {
        var addr = CoreAudioHelpers.address(kAudioHardwarePropertyDefaultOutputDevice)
        return try CoreAudioHelpers.getProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: &addr
        )
    }

    nonisolated static func setDefaultOutputDeviceID(_ deviceID: AudioObjectID) throws {
        var addr = CoreAudioHelpers.address(kAudioHardwarePropertyDefaultOutputDevice)
        try CoreAudioHelpers.setProperty(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: &addr,
            value: deviceID
        )
    }

    nonisolated static func setDefaultOutput(uid: String) throws {
        let devices = try fetchAllOutputDevices()
        guard let device = devices.first(where: { $0.uid == uid }) else {
            throw MultiAudioError.deviceNotFound(uid)
        }
        try setDefaultOutputDeviceID(device.id)
    }

    nonisolated static func fetchAllOutputDevices() throws -> [AudioDeviceInfo] {
        var addr = CoreAudioHelpers.address(kAudioHardwarePropertyDevices)
        let size = try CoreAudioHelpers.propertyDataSize(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: &addr
        )
        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }

        var ids = [AudioObjectID](repeating: 0, count: count)
        var mutableSize = size
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &addr,
            0,
            nil,
            &mutableSize,
            &ids
        )
        guard status == noErr else {
            throw MultiAudioError.devicePropertyFailed("devices", status)
        }

        return ids.compactMap { id in
            try? describeDevice(id)
        }.filter { $0.channelCount > 0 }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func describeDevice(_ id: AudioObjectID) throws -> AudioDeviceInfo {
        let uid = try CoreAudioHelpers.getString(objectID: id, selector: kAudioDevicePropertyDeviceUID)
        let name = try CoreAudioHelpers.getString(objectID: id, selector: kAudioObjectPropertyName)
        let manufacturer = (try? CoreAudioHelpers.getString(
            objectID: id,
            selector: kAudioObjectPropertyManufacturer
        )) ?? ""

        var transportAddr = CoreAudioHelpers.address(kAudioDevicePropertyTransportType)
        let transportRaw: UInt32 = (try? CoreAudioHelpers.getProperty(
            objectID: id,
            address: &transportAddr
        )) ?? kAudioDeviceTransportTypeUnknown

        var rateAddr = CoreAudioHelpers.address(kAudioDevicePropertyNominalSampleRate)
        let sampleRate: Float64 = (try? CoreAudioHelpers.getProperty(
            objectID: id,
            address: &rateAddr
        )) ?? 0

        let channels = outputChannelCount(for: id)
        let alive = isDeviceAlive(id)
        let volume = readVolume(for: id)
        let muted = readMute(for: id)

        return AudioDeviceInfo(
            id: id,
            uid: uid,
            name: name,
            transport: .from(fourCC: transportRaw),
            sampleRate: sampleRate,
            channelCount: channels,
            isAlive: alive,
            manufacturer: manufacturer,
            volume: volume,
            isMuted: muted
        )
    }

    nonisolated static func outputChannelCount(for id: AudioObjectID) -> UInt32 {
        var addr = CoreAudioHelpers.address(
            kAudioDevicePropertyStreamConfiguration,
            scope: kAudioObjectPropertyScopeOutput
        )
        guard CoreAudioHelpers.hasProperty(objectID: id, address: &addr) else { return 0 }
        guard let size = try? CoreAudioHelpers.propertyDataSize(objectID: id, address: &addr),
              size > 0 else { return 0 }

        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        var mutableSize = size
        let status = AudioObjectGetPropertyData(id, &addr, 0, nil, &mutableSize, raw)
        guard status == noErr else { return 0 }

        let bufferList = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        var total: UInt32 = 0
        for buffer in buffers {
            total += buffer.mNumberChannels
        }
        return total
    }

    nonisolated static func isDeviceAlive(_ id: AudioObjectID) -> Bool {
        var addr = CoreAudioHelpers.address(kAudioDevicePropertyDeviceIsAlive)
        guard CoreAudioHelpers.hasProperty(objectID: id, address: &addr) else { return true }
        let alive: UInt32 = (try? CoreAudioHelpers.getProperty(objectID: id, address: &addr)) ?? 1
        return alive != 0
    }

    nonisolated static func readVolume(for id: AudioObjectID) -> Float? {
        // Prefer master element; fall back to channel 1.
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var addr = CoreAudioHelpers.address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
            if CoreAudioHelpers.hasProperty(objectID: id, address: &addr),
               let value: Float32 = try? CoreAudioHelpers.getProperty(objectID: id, address: &addr) {
                return value
            }
        }
        return nil
    }

    nonisolated static func setVolume(for id: AudioObjectID, scalar: Float) throws {
        let clamped = max(0, min(1, scalar))
        var setAny = false
        for element: AudioObjectPropertyElement in [kAudioObjectPropertyElementMain, 1, 2] {
            var addr = CoreAudioHelpers.address(
                kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
            if CoreAudioHelpers.hasProperty(objectID: id, address: &addr),
               CoreAudioHelpers.isPropertySettable(objectID: id, address: &addr) {
                try CoreAudioHelpers.setProperty(objectID: id, address: &addr, value: Float32(clamped))
                setAny = true
            }
        }
        if !setAny {
            throw MultiAudioError.unsupportedConfiguration("Device does not expose volume control.")
        }
    }

    nonisolated static func readMute(for id: AudioObjectID) -> Bool? {
        var addr = CoreAudioHelpers.address(
            kAudioDevicePropertyMute,
            scope: kAudioObjectPropertyScopeOutput
        )
        guard CoreAudioHelpers.hasProperty(objectID: id, address: &addr),
              let value: UInt32 = try? CoreAudioHelpers.getProperty(objectID: id, address: &addr) else {
            return nil
        }
        return value != 0
    }
}
