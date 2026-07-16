import Foundation
import CoreAudio

/// A reusable multi-output configuration the user can start with one click.
struct AudioSession: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var deviceUIDs: [String]
    /// Preferred clock master (first device by default).
    var masterDeviceUID: String?
    var isFavorite: Bool
    var autoReconnect: Bool
    var enableDriftCorrection: Bool
    var createdAt: Date
    var updatedAt: Date
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        deviceUIDs: [String],
        masterDeviceUID: String? = nil,
        isFavorite: Bool = false,
        autoReconnect: Bool = true,
        enableDriftCorrection: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.deviceUIDs = deviceUIDs
        self.masterDeviceUID = masterDeviceUID ?? deviceUIDs.first
        self.isFavorite = isFavorite
        self.autoReconnect = autoReconnect
        self.enableDriftCorrection = enableDriftCorrection
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortOrder = sortOrder
    }

    var isValid: Bool {
        deviceUIDs.count >= 2
    }
}

/// Runtime state of an active multi-output session.
struct ActiveSessionState: Sendable, Equatable {
    let sessionID: UUID?
    let sessionName: String
    let multiOutputDeviceID: AudioObjectID
    let multiOutputUID: String
    let deviceUIDs: [String]
    let previousDefaultOutputUID: String?
    let startedAt: Date
}
