import Foundation
import Combine

/// Persists reusable multi-output sessions to Application Support.
final class SessionStore: ObservableObject {
    @Published private(set) var sessions: [AudioSession] = []

    private let fileURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let dir = support.appendingPathComponent("MultiAudio", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent("sessions.json")
        }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            sessions = []
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            sessions = try decoder.decode([AudioSession].self, from: data)
                .sorted { lhs, rhs in
                    if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite && !rhs.isFavorite }
                    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
        } catch {
            sessions = []
        }
    }

    func save() {
        do {
            let data = try encoder.encode(sessions)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            // Persistence failure is non-fatal for runtime audio.
        }
    }

    @discardableResult
    func create(
        name: String,
        deviceUIDs: [String],
        masterDeviceUID: String? = nil,
        enableDriftCorrection: Bool = true
    ) -> AudioSession {
        let session = AudioSession(
            name: name,
            deviceUIDs: deviceUIDs,
            masterDeviceUID: masterDeviceUID,
            enableDriftCorrection: enableDriftCorrection,
            sortOrder: (sessions.map(\.sortOrder).max() ?? -1) + 1
        )
        sessions.append(session)
        save()
        return session
    }

    func update(_ session: AudioSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        var updated = session
        updated.updatedAt = Date()
        sessions[index] = updated
        save()
    }

    func delete(_ id: UUID) {
        sessions.removeAll { $0.id == id }
        save()
    }

    func duplicate(_ id: UUID) -> AudioSession? {
        guard let original = sessions.first(where: { $0.id == id }) else { return nil }
        let copy = AudioSession(
            name: "\(original.name) Copy",
            deviceUIDs: original.deviceUIDs,
            masterDeviceUID: original.masterDeviceUID,
            isFavorite: false,
            autoReconnect: original.autoReconnect,
            enableDriftCorrection: original.enableDriftCorrection,
            sortOrder: (sessions.map(\.sortOrder).max() ?? -1) + 1
        )
        sessions.append(copy)
        save()
        return copy
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        sessions[index].updatedAt = Date()
        save()
    }

    func toggleFavorite(_ id: UUID) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[index].isFavorite.toggle()
        sessions[index].updatedAt = Date()
        save()
    }

    func session(id: UUID) -> AudioSession? {
        sessions.first { $0.id == id }
    }
}
