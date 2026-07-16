import Foundation
import CoreAudio

/// Snapshot of a Core Audio output device suitable for UI and session storage.
struct AudioDeviceInfo: Identifiable, Hashable, Sendable {
    let id: AudioObjectID
    let uid: String
    let name: String
    let transport: TransportType
    let sampleRate: Double
    let channelCount: UInt32
    let isAlive: Bool
    let manufacturer: String
    let volume: Float?
    let isMuted: Bool?

    var isBluetooth: Bool {
        transport == .bluetooth || transport == .bluetoothLE
    }

    var isAggregate: Bool {
        transport == .aggregate
    }

    var isBuiltIn: Bool {
        transport == .builtIn
    }

    var sfSymbolName: String {
        switch transport {
        case .bluetooth, .bluetoothLE:
            return "headphones"
        case .builtIn:
            return "laptopcomputer"
        case .usb:
            return "cable.connector"
        case .hdmi, .displayPort:
            return "tv"
        case .airPlay:
            return "airplayaudio"
        case .aggregate, .virtual:
            return "rectangle.3.group"
        default:
            return "hifispeaker"
        }
    }

    enum TransportType: String, Hashable, Sendable, Codable {
        case unknown
        case builtIn
        case aggregate
        case virtual
        case pci
        case usb
        case fireWire
        case bluetooth
        case bluetoothLE
        case hdmi
        case displayPort
        case airPlay
        case avb
        case thunderbolt
        case other

        var displayName: String {
            switch self {
            case .unknown: return "Unknown"
            case .builtIn: return "Built-in"
            case .aggregate: return "Aggregate"
            case .virtual: return "Virtual"
            case .pci: return "PCI"
            case .usb: return "USB"
            case .fireWire: return "FireWire"
            case .bluetooth: return "Bluetooth"
            case .bluetoothLE: return "Bluetooth LE"
            case .hdmi: return "HDMI"
            case .displayPort: return "DisplayPort"
            case .airPlay: return "AirPlay"
            case .avb: return "AVB"
            case .thunderbolt: return "Thunderbolt"
            case .other: return "Other"
            }
        }

        static func from(fourCC: UInt32) -> TransportType {
            switch fourCC {
            case kAudioDeviceTransportTypeBuiltIn: return .builtIn
            case kAudioDeviceTransportTypeAggregate: return .aggregate
            case kAudioDeviceTransportTypeVirtual: return .virtual
            case kAudioDeviceTransportTypePCI: return .pci
            case kAudioDeviceTransportTypeUSB: return .usb
            case kAudioDeviceTransportTypeFireWire: return .fireWire
            case kAudioDeviceTransportTypeBluetooth: return .bluetooth
            case kAudioDeviceTransportTypeBluetoothLE: return .bluetoothLE
            case kAudioDeviceTransportTypeHDMI: return .hdmi
            case kAudioDeviceTransportTypeDisplayPort: return .displayPort
            case kAudioDeviceTransportTypeAirPlay: return .airPlay
            case kAudioDeviceTransportTypeAVB: return .avb
            case kAudioDeviceTransportTypeThunderbolt: return .thunderbolt
            case kAudioDeviceTransportTypeUnknown: return .unknown
            default: return .other
            }
        }
    }
}
