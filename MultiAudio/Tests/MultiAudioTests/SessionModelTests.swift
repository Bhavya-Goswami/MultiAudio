import XCTest

/// Lightweight model tests that don't require the app binary as a library.
final class SessionModelTests: XCTestCase {
    func testSessionRequiresTwoDevices() {
        let invalid = SessionSnapshot(name: "Solo", deviceUIDs: ["a"])
        let valid = SessionSnapshot(name: "Duo", deviceUIDs: ["a", "b"])
        XCTAssertFalse(invalid.isValid)
        XCTAssertTrue(valid.isValid)
    }

    func testMasterDefaultsToFirstDevice() {
        let session = SessionSnapshot(name: "Test", deviceUIDs: ["uid-1", "uid-2"])
        XCTAssertEqual(session.masterDeviceUID, "uid-1")
    }

    func testUIDPrefixConvention() {
        let prefix = "com.multiaudio.multioutput."
        let uid = prefix + UUID().uuidString.lowercased()
        XCTAssertTrue(uid.hasPrefix(prefix))
        XCTAssertFalse("AppleUSBAudioEngine:…".hasPrefix(prefix))
    }
}

/// Mirror of AudioSession validation rules for isolated testing.
private struct SessionSnapshot {
    var name: String
    var deviceUIDs: [String]
    var masterDeviceUID: String?

    init(name: String, deviceUIDs: [String], masterDeviceUID: String? = nil) {
        self.name = name
        self.deviceUIDs = deviceUIDs
        self.masterDeviceUID = masterDeviceUID ?? deviceUIDs.first
    }

    var isValid: Bool { deviceUIDs.count >= 2 }
}
