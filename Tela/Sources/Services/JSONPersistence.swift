import Foundation

public enum JSONPersistenceError: Error, LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case directoryUnavailable

    public var errorDescription: String? {
        switch self {
        case let .unsupportedVersion(version): return "Unsupported Tela state version \(version)."
        case .directoryUnavailable: return "Tela could not create its Application Support directory."
        }
    }
}

/// Versioned JSON persistence rooted in Application Support/Tela by default.
/// Invalid JSON is moved aside before returning an empty state, so one broken
/// write cannot prevent the app from launching forever.
public final class JSONPersistence: Persistence, @unchecked Sendable {
    public let fileURL: URL
    public let version: Int
    public private(set) var lastQuarantinedURL: URL?
    public let fileManager: FileManager

    private struct Envelope: Codable {
        let version: Int
        let snapshot: TimerSnapshot

        private enum CodingKeys: String, CodingKey {
            case version
            case schemaVersion
            case snapshot
            case state
        }

        init(version: Int, snapshot: TimerSnapshot) {
            self.version = version
            self.snapshot = snapshot
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.version = try c.decodeIfPresent(Int.self, forKey: .version)
                ?? c.decode(Int.self, forKey: .schemaVersion)
            self.snapshot = try c.decodeIfPresent(TimerSnapshot.self, forKey: .snapshot)
                ?? c.decode(TimerSnapshot.self, forKey: .state)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(version, forKey: .version)
            try c.encode(snapshot, forKey: .snapshot)
        }
    }

    public init(
        directory: URL? = nil,
        fileName: String = "timer-state-v1.json",
        version: Int = 2,
        fileManager: FileManager = .default
    ) {
        self.version = max(1, version)
        self.fileManager = fileManager
        let root = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.fileURL = root.appendingPathComponent(fileName, isDirectory: false)
    }

    public convenience init(
        fileURL: URL,
        version: Int = 2,
        fileManager: FileManager = .default
    ) {
        self.init(
            directory: fileURL.deletingLastPathComponent(),
            fileName: fileURL.lastPathComponent,
            version: version,
            fileManager: fileManager
        )
    }

    public func load() throws -> TimerSnapshot? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            do {
                let envelope = try decoder.decode(Envelope.self, from: data)
                guard envelope.version <= version else {
                    _ = try? quarantine()
                    throw JSONPersistenceError.unsupportedVersion(envelope.version)
                }
                var snapshot = envelope.snapshot
                if envelope.version < version {
                    snapshot.migrateSessionHistory()
                    try? save(snapshot)
                }
                return snapshot
            } catch let error as JSONPersistenceError {
                throw error
            } catch {
                // Preserve compatibility with pre-envelope snapshots while
                // still quarantining malformed documents.
                if var snapshot = try? decoder.decode(TimerSnapshot.self, from: data) {
                    snapshot.migrateSessionHistory()
                    try? save(snapshot)
                    return snapshot
                }
                try quarantine()
                return nil
            }
        } catch let error as JSONPersistenceError {
            throw error
        } catch {
            // I/O failures are surfaced; malformed contents are handled above.
            throw error
        }
    }

    public func save(_ snapshot: TimerSnapshot) throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(Envelope(version: version, snapshot: snapshot))
        try data.write(to: fileURL, options: [.atomic])
    }

    @discardableResult
    public func quarantine() throws -> URL? {
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let stamp = String(Int(Date().timeIntervalSince1970))
        var candidate = fileURL
            .deletingPathExtension()
            .appendingPathExtension("corrupt-\(stamp)-\(UUID().uuidString).json")
        // A user-provided path may have no extension. Ensure the destination
        // stays in the same directory and never overwrites another quarantine.
        if fileManager.fileExists(atPath: candidate.path) {
            candidate = fileURL
                .deletingLastPathComponent()
                .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(UUID().uuidString)")
        }
        try fileManager.moveItem(at: fileURL, to: candidate)
        lastQuarantinedURL = candidate
        return candidate
    }

    private static func defaultDirectory(fileManager: FileManager) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Tela", isDirectory: true)
    }
}

public typealias JSONFilePersistence = JSONPersistence
public typealias VersionedJSONPersistence = JSONPersistence
public typealias TimerJSONPersistence = JSONPersistence
