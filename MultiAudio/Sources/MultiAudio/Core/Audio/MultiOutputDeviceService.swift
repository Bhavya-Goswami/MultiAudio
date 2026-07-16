import Foundation
import CoreAudio

/// Creates and destroys Core Audio multi-output devices (stacked aggregate devices).
///
/// Multi-output devices mirror the same stereo mix to every sub-device — the same
/// mechanism Audio MIDI Setup uses under "Create Multi-Output Device".
///
/// Public API used:
/// - `AudioHardwareCreateAggregateDevice` (macOS 10.9+)
/// - `kAudioAggregateDeviceIsStackedKey` → multi-output (mirrored) vs channel-aggregate
/// - `kAudioSubDeviceDriftCompensationKey` → clock drift correction for non-master devices
final class MultiOutputDeviceService: Sendable {
    static let uidPrefix = "com.multiaudio.multioutput."
    static let namePrefix = "MultiAudio"

    struct CreateRequest: Sendable {
        var name: String
        var deviceUIDs: [String]
        var masterDeviceUID: String?
        var enableDriftCorrection: Bool
        var isPrivate: Bool

        init(
            name: String,
            deviceUIDs: [String],
            masterDeviceUID: String? = nil,
            enableDriftCorrection: Bool = true,
            isPrivate: Bool = false
        ) {
            self.name = name
            self.deviceUIDs = deviceUIDs
            self.masterDeviceUID = masterDeviceUID
            self.enableDriftCorrection = enableDriftCorrection
            self.isPrivate = isPrivate
        }
    }

    struct CreatedDevice: Sendable {
        let deviceID: AudioObjectID
        let uid: String
        let name: String
    }

    /// Creates a system multi-output (stacked aggregate) device.
    func create(_ request: CreateRequest) throws -> CreatedDevice {
        guard request.deviceUIDs.count >= 2 else {
            throw MultiAudioError.needAtLeastTwoDevices
        }

        var seen = Set<String>()
        let uniqueUIDs = request.deviceUIDs.filter { seen.insert($0).inserted }
        guard uniqueUIDs.count >= 2 else {
            throw MultiAudioError.needAtLeastTwoDevices
        }

        let masterUID = request.masterDeviceUID.flatMap { uniqueUIDs.contains($0) ? $0 : nil }
            ?? uniqueUIDs[0]

        // Prefer a more stable clock as master when possible (built-in / wired first).
        let orderedUIDs = Self.orderUIDsForClockStability(uniqueUIDs, preferredMaster: masterUID)
        let resolvedMaster = orderedUIDs[0]

        let uid = Self.uidPrefix + UUID().uuidString.lowercased()
        let displayName = request.name.isEmpty
            ? "\(Self.namePrefix) Output"
            : "\(Self.namePrefix) — \(request.name)"

        var subDevices: [[String: Any]] = []
        for deviceUID in orderedUIDs {
            var entry: [String: Any] = [
                kAudioSubDeviceUIDKey: deviceUID
            ]
            // Enable drift compensation on every non-master sub-device.
            // Essential for Bluetooth devices with independent clocks.
            if request.enableDriftCorrection && deviceUID != resolvedMaster {
                entry[kAudioSubDeviceDriftCompensationKey] = 1
                entry[kAudioSubDeviceDriftCompensationQualityKey] =
                    kAudioAggregateDriftCompensationMaxQuality
            }
            subDevices.append(entry)
        }

        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: displayName,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceSubDeviceListKey: subDevices,
            kAudioAggregateDeviceMainSubDeviceKey: resolvedMaster,
            // stacked == multi-output (mirror same channels to all devices)
            kAudioAggregateDeviceIsStackedKey: 1,
            // Public so the system default output can route to it app-wide
            // (Netflix, Spotify, Safari, VLC, etc.)
            kAudioAggregateDeviceIsPrivateKey: request.isPrivate ? 1 : 0
        ]

        var aggregateID = AudioObjectID(0)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != 0 else {
            throw MultiAudioError.createAggregateFailed(status)
        }

        // Give the HAL a moment to finish registering the device.
        CoreAudioHelpers.settleHAL(seconds: 0.2)

        // Verify the device is queryable.
        do {
            _ = try CoreAudioHelpers.getString(
                objectID: aggregateID,
                selector: kAudioDevicePropertyDeviceUID
            )
        } catch {
            // Retry settle once — known HAL race after aggregate creation.
            CoreAudioHelpers.settleHAL(seconds: 0.3)
        }

        return CreatedDevice(deviceID: aggregateID, uid: uid, name: displayName)
    }

    func destroy(deviceID: AudioObjectID) throws {
        guard deviceID != 0 else { return }
        let status = AudioHardwareDestroyAggregateDevice(deviceID)
        guard status == noErr else {
            throw MultiAudioError.destroyAggregateFailed(status)
        }
        CoreAudioHelpers.settleHAL(seconds: 0.1)
    }

    func destroy(uid: String) throws {
        let devices = try AudioDeviceService.fetchAllOutputDevices()
        guard let device = devices.first(where: { $0.uid == uid }) else {
            // Already gone — treat as success.
            return
        }
        try destroy(deviceID: device.id)
    }

    /// Removes any leftover MultiAudio multi-output devices (e.g. after a crash).
    func cleanupOrphanedDevices() {
        guard let devices = try? AudioDeviceService.fetchAllOutputDevices() else { return }
        for device in devices where device.uid.hasPrefix(Self.uidPrefix) {
            try? destroy(deviceID: device.id)
        }
    }

    /// Prefer wired / built-in as clock master; keep preferred master first when present.
    nonisolated static func orderUIDsForClockStability(
        _ uids: [String],
        preferredMaster: String
    ) -> [String] {
        var ordered = uids
        if let idx = ordered.firstIndex(of: preferredMaster), idx != 0 {
            ordered.remove(at: idx)
            ordered.insert(preferredMaster, at: 0)
        }
        return ordered
    }
}
