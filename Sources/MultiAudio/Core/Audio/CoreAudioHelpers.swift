import Foundation
import CoreAudio

/// Low-level Core Audio property helpers. Pure functions, no shared state.
enum CoreAudioHelpers {
    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: scope,
            mElement: element
        )
    }

    static func propertyDataSize(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) throws -> UInt32 {
        var size: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(objectID, &address, 0, nil, &size)
        guard status == noErr else {
            throw MultiAudioError.devicePropertyFailed(fourCC(address.mSelector), status)
        }
        return size
    }

    static func getProperty<T>(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) throws -> T {
        var size = UInt32(MemoryLayout<T>.size)
        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: MemoryLayout<T>.size,
            alignment: MemoryLayout<T>.alignment
        )
        defer { raw.deallocate() }
        let status = AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, raw)
        guard status == noErr else {
            throw MultiAudioError.devicePropertyFailed(fourCC(address.mSelector), status)
        }
        return raw.load(as: T.self)
    }

    static func setProperty<T>(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress,
        value: T
    ) throws {
        var mutable = value
        let size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafePointer(to: &mutable) { ptr in
            AudioObjectSetPropertyData(objectID, &address, 0, nil, size, UnsafeMutableRawPointer(mutating: ptr))
        }
        guard status == noErr else {
            throw MultiAudioError.devicePropertyFailed(fourCC(address.mSelector), status)
        }
    }

    static func getCFString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var addr = address(selector)
        var size = try propertyDataSize(objectID: objectID, address: &addr)
        var cfValue: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &cfValue) { ptr in
            AudioObjectGetPropertyData(objectID, &addr, 0, nil, &size, ptr)
        }
        guard status == noErr, let unmanaged = cfValue else {
            throw MultiAudioError.devicePropertyFailed(fourCC(selector), status)
        }
        return unmanaged.takeRetainedValue() as String
    }

    static func getString(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        try getCFString(objectID: objectID, selector: selector)
    }

    static func hasProperty(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> Bool {
        AudioObjectHasProperty(objectID, &address)
    }

    static func isPropertySettable(
        objectID: AudioObjectID,
        address: inout AudioObjectPropertyAddress
    ) -> Bool {
        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(objectID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    static func fourCC(_ value: UInt32) -> String {
        let chars: [UInt8] = [
            UInt8((value >> 24) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF)
        ]
        return String(bytes: chars, encoding: .macOSRoman) ?? "????"
    }

    /// Pause the current run loop briefly so Core Audio can finish aggregate bookkeeping.
    static func settleHAL(seconds: CFTimeInterval = 0.15) {
        CFRunLoopRunInMode(CFRunLoopMode.defaultMode, seconds, false)
    }
}
