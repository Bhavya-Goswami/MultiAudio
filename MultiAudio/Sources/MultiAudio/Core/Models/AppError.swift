import Foundation

enum MultiAudioError: LocalizedError, Equatable {
    case noDevicesSelected
    case needAtLeastTwoDevices
    case deviceNotFound(String)
    case createAggregateFailed(OSStatus)
    case destroyAggregateFailed(OSStatus)
    case setDefaultOutputFailed(OSStatus)
    case devicePropertyFailed(String, OSStatus)
    case sessionNotFound
    case alreadyActive
    case notActive
    case permissionDenied
    case unsupportedConfiguration(String)

    var errorDescription: String? {
        switch self {
        case .noDevicesSelected:
            return "Select at least one audio device."
        case .needAtLeastTwoDevices:
            return "Multi-output requires at least two devices."
        case .deviceNotFound(let name):
            return "Device not found: \(name). Make sure it is connected."
        case .createAggregateFailed(let status):
            return "Failed to create multi-output device (error \(status))."
        case .destroyAggregateFailed(let status):
            return "Failed to remove multi-output device (error \(status))."
        case .setDefaultOutputFailed(let status):
            return "Failed to set system audio output (error \(status))."
        case .devicePropertyFailed(let property, let status):
            return "Audio property ‘\(property)’ failed (error \(status))."
        case .sessionNotFound:
            return "Session not found."
        case .alreadyActive:
            return "A multi-output session is already active."
        case .notActive:
            return "No multi-output session is active."
        case .permissionDenied:
            return "Permission denied. MultiAudio needs access to control audio devices."
        case .unsupportedConfiguration(let reason):
            return "Unsupported configuration: \(reason)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .needAtLeastTwoDevices:
            return "Connect another pair of headphones or speakers, then try again."
        case .deviceNotFound:
            return "Open System Settings → Bluetooth and reconnect the device."
        case .createAggregateFailed, .setDefaultOutputFailed:
            return "Open Audio MIDI Setup and verify devices appear. Then retry."
        case .alreadyActive:
            return "Stop the current session before starting a new one."
        default:
            return nil
        }
    }
}
