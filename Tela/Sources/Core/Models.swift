import Foundation

/// The period that is currently being timed.
public enum TimerPhase: String, Codable, CaseIterable, Sendable {
    case focus
    case shortBreak
    case longBreak

    public var isFocus: Bool { self == .focus }
    public var isBreak: Bool { !isFocus }
}

/// The lifecycle state of a timer period.
public enum TimerState: String, Codable, CaseIterable, Sendable {
    case idle
    case running
    case paused
}

/// Durable lifecycle of one timed period. `TimerState` remains deliberately
/// small for the existing UI; this record carries the richer history state.
public enum TimerSessionStatus: String, Codable, CaseIterable, Sendable {
    case running
    case paused
    case suspended
    case completed
    case abandoned

    public var isActive: Bool {
        switch self {
        case .running, .paused: true
        case .suspended, .completed, .abandoned: false
        }
    }

    public var isResumable: Bool { self == .paused || self == .suspended }
    public var isTerminal: Bool { self == .completed || self == .abandoned }

    /// Compatibility spelling for clients that called a user-cancelled period
    /// "cancelled" before the durable history model was introduced.
    public static var cancelled: Self { .abandoned }
}

/// Alias kept intentionally broad so callers can use the shorter domain name.
public typealias SessionStatus = TimerSessionStatus

/// One stable, resumable timed period. A record is updated in place across
/// pause/suspend/resume; its id never changes, which makes history merge-safe.
public struct TimerSessionRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let cycleID: UUID
    public let phase: TimerPhase
    public let artworkID: UUID?
    /// Stable journey identifier for one artwork run. It survives selecting a
    /// different artwork and lets late routine completion find its record.
    public let artworkJourneyID: UUID?
    public var artworkSnapshot: Artwork?
    public var artworkProgressSnapshot: ArtworkProgress?
    public var status: TimerSessionStatus
    public var startedAt: Date?
    public var endedAt: Date?
    public var plannedDuration: TimeInterval
    public var elapsed: TimeInterval
    public var remaining: TimeInterval

    public init(
        id: UUID = UUID(),
        cycleID: UUID = UUID(),
        phase: TimerPhase = .focus,
        status: TimerSessionStatus = .running,
        artworkID: UUID? = nil,
        artworkJourneyID: UUID? = nil,
        artworkSnapshot: Artwork? = nil,
        artworkProgressSnapshot: ArtworkProgress? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        plannedDuration: TimeInterval = 0,
        elapsed: TimeInterval = 0,
        remaining: TimeInterval = 0
    ) {
        self.id = id
        self.cycleID = cycleID
        self.phase = phase
        self.artworkID = artworkID
        self.artworkJourneyID = artworkJourneyID
        self.artworkSnapshot = artworkSnapshot
        self.artworkProgressSnapshot = artworkProgressSnapshot
        self.status = status
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.plannedDuration = max(0, plannedDuration)
        self.elapsed = max(0, elapsed)
        self.remaining = max(0, remaining)
    }

    /// Convenience label used by older integrations.
    public init(
        id: UUID = UUID(),
        cycleID: UUID = UUID(),
        phase: TimerPhase = .focus,
        state: TimerSessionStatus,
        artworkID: UUID? = nil,
        artworkJourneyID: UUID? = nil,
        artworkSnapshot: Artwork? = nil,
        artworkProgressSnapshot: ArtworkProgress? = nil,
        startedAt: Date? = nil,
        endedAt: Date? = nil,
        duration: TimeInterval = 0,
        elapsed: TimeInterval = 0,
        remaining: TimeInterval = 0
    ) {
        self.init(
            id: id,
            cycleID: cycleID,
            phase: phase,
            status: state,
            artworkID: artworkID,
            artworkJourneyID: artworkJourneyID,
            artworkSnapshot: artworkSnapshot,
            artworkProgressSnapshot: artworkProgressSnapshot,
            startedAt: startedAt,
            endedAt: endedAt,
            plannedDuration: duration,
            elapsed: elapsed,
            remaining: remaining
        )
    }

    public var state: TimerSessionStatus {
        get { status }
        set { status = newValue }
    }

    public var duration: TimeInterval {
        get { plannedDuration }
        set { plannedDuration = max(0, newValue) }
    }

    public var isActive: Bool { status.isActive }
    public var isCompleted: Bool { status == .completed }
    public var isAbandoned: Bool { status == .abandoned }

    /// Applies a terminal or resumable transition without creating a second
    /// record. Repeated transitions to the same state are idempotent.
    @discardableResult
    public mutating func transition(
        to nextStatus: TimerSessionStatus,
        at date: Date? = nil,
        elapsed: TimeInterval? = nil,
        remaining: TimeInterval? = nil
    ) -> Bool {
        let changed = status != nextStatus
            || elapsed.map { abs(self.elapsed - max(0, $0)) > 0.000_001 } == true
            || remaining.map { abs(self.remaining - max(0, $0)) > 0.000_001 } == true
        status = nextStatus
        if let elapsed { self.elapsed = max(0, elapsed) }
        if let remaining { self.remaining = max(0, remaining) }
        if nextStatus.isTerminal, let date {
            endedAt = date
        }
        return changed
    }
}

/// A Pomodoro cycle groups one focus period and its following break period.
/// The individual session records remain authoritative for timing/history.
public struct TimerCycleRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var focusSessionID: UUID?
    public var breakSessionID: UUID?
    public var artworkID: UUID?
    public var artworkJourneyID: UUID?
    public var status: TimerSessionStatus
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        focusSessionID: UUID? = nil,
        breakSessionID: UUID? = nil,
        artworkID: UUID? = nil,
        artworkJourneyID: UUID? = nil,
        status: TimerSessionStatus = .running,
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.focusSessionID = focusSessionID
        self.breakSessionID = breakSessionID
        self.artworkID = artworkID
        self.artworkJourneyID = artworkJourneyID
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public var isActive: Bool { status.isActive }
    public var isComplete: Bool { status == .completed }
}

public typealias TimerCycle = TimerCycleRecord
public typealias CycleStatus = TimerSessionStatus

/// User-adjustable Pomodoro durations.
public struct TimerConfiguration: Codable, Equatable, Sendable {
    public var focusDuration: TimeInterval
    public var shortBreakDuration: TimeInterval
    public var longBreakDuration: TimeInterval
    public var sessionsBeforeLongBreak: Int

    public static let `default` = TimerConfiguration()

    public init(
        focusDuration: TimeInterval = 25 * 60,
        shortBreakDuration: TimeInterval = 5 * 60,
        longBreakDuration: TimeInterval = 15 * 60,
        sessionsBeforeLongBreak: Int = 4
    ) {
        self.focusDuration = max(0, focusDuration)
        self.shortBreakDuration = max(0, shortBreakDuration)
        self.longBreakDuration = max(0, longBreakDuration)
        self.sessionsBeforeLongBreak = max(1, sessionsBeforeLongBreak)
    }

    public init(
        focus: TimeInterval,
        shortBreak: TimeInterval,
        longBreak: TimeInterval,
        sessionsBeforeLongBreak: Int = 4
    ) {
        self.init(
            focusDuration: focus,
            shortBreakDuration: shortBreak,
            longBreakDuration: longBreak,
            sessionsBeforeLongBreak: sessionsBeforeLongBreak
        )
    }

    public init(
        focusSeconds: Int,
        shortBreakSeconds: Int,
        longBreakSeconds: Int,
        longBreakEvery: Int = 4
    ) {
        self.init(
            focusDuration: TimeInterval(focusSeconds),
            shortBreakDuration: TimeInterval(shortBreakSeconds),
            longBreakDuration: TimeInterval(longBreakSeconds),
            sessionsBeforeLongBreak: longBreakEvery
        )
    }

    // Short aliases make the model convenient in SwiftUI and preserve the
    // terminology used by older saved documents.
    public var focus: TimeInterval {
        get { focusDuration }
        set { focusDuration = max(0, newValue) }
    }

    public var shortBreak: TimeInterval {
        get { shortBreakDuration }
        set { shortBreakDuration = max(0, newValue) }
    }

    public var longBreak: TimeInterval {
        get { longBreakDuration }
        set { longBreakDuration = max(0, newValue) }
    }

    public var focusSeconds: Int { Int(focusDuration.rounded()) }
    public var shortBreakSeconds: Int { Int(shortBreakDuration.rounded()) }
    public var longBreakSeconds: Int { Int(longBreakDuration.rounded()) }

    private enum CodingKeys: String, CodingKey {
        case focusDuration
        case shortBreakDuration
        case longBreakDuration
        case sessionsBeforeLongBreak
        case focusSeconds
        case shortBreakSeconds
        case longBreakSeconds
        case longBreakEvery
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        func decodeDuration(_ primary: CodingKeys, _ seconds: CodingKeys) -> TimeInterval? {
            if let value = try? container.decode(TimeInterval.self, forKey: primary) {
                return value
            }
            if let value = try? container.decode(TimeInterval.self, forKey: seconds) {
                return value
            }
            return nil
        }

        self.init(
            focusDuration: decodeDuration(.focusDuration, .focusSeconds) ?? 25 * 60,
            shortBreakDuration: decodeDuration(.shortBreakDuration, .shortBreakSeconds) ?? 5 * 60,
            longBreakDuration: decodeDuration(.longBreakDuration, .longBreakSeconds) ?? 15 * 60,
            sessionsBeforeLongBreak: (try? container.decode(Int.self, forKey: .sessionsBeforeLongBreak))
                ?? (try? container.decode(Int.self, forKey: .longBreakEvery))
                ?? 4
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(focusDuration, forKey: .focusDuration)
        try container.encode(shortBreakDuration, forKey: .shortBreakDuration)
        try container.encode(longBreakDuration, forKey: .longBreakDuration)
        try container.encode(sessionsBeforeLongBreak, forKey: .sessionsBeforeLongBreak)
    }
}

/// A persisted view of the timer.  All values required to resume after an app
/// restart are kept here; `deadline` is the authoritative running-clock value.
public struct TimerSnapshot: Codable, Equatable, Sendable {
    public var phase: TimerPhase
    public var state: TimerState
    public var startedAt: Date?
    public var deadline: Date?
    public var remaining: TimeInterval
    public var completedFocusSessions: Int
    public var configuration: TimerConfiguration?
    public var artwork: Artwork?
    public var artworkJourneyID: UUID?
    public var artworkProgress: ArtworkProgress?
    public var completedArtworks: [CompletedArtwork]
    /// Durable period history. Empty means a legacy snapshot has not yet been
    /// migrated or no period has been started in this installation.
    public var sessionHistory: [TimerSessionRecord]
    /// Focus+break cycle history. Period records remain the source of timing.
    public var cycles: [TimerCycleRecord]
    public var activeSessionID: UUID?
    public var activeCycleID: UUID?

    public init(
        phase: TimerPhase = .focus,
        state: TimerState = .idle,
        startedAt: Date? = nil,
        deadline: Date? = nil,
        remaining: TimeInterval = 0,
        completedFocusSessions: Int = 0,
        configuration: TimerConfiguration? = nil,
        artwork: Artwork? = nil,
        artworkJourneyID: UUID? = nil,
        artworkProgress: ArtworkProgress? = nil,
        completedArtworks: [CompletedArtwork] = [],
        sessionHistory: [TimerSessionRecord] = [],
        cycles: [TimerCycleRecord] = [],
        activeSessionID: UUID? = nil,
        activeCycleID: UUID? = nil
    ) {
        self.phase = phase
        self.state = state
        self.startedAt = startedAt
        self.deadline = deadline
        self.remaining = max(0, remaining)
        self.completedFocusSessions = max(0, completedFocusSessions)
        self.configuration = configuration
        self.artwork = artwork
        self.artworkJourneyID = artworkJourneyID
        self.artworkProgress = artworkProgress
        self.completedArtworks = completedArtworks
        self.sessionHistory = sessionHistory
        self.cycles = cycles
        self.activeSessionID = activeSessionID
        self.activeCycleID = activeCycleID
    }

    public var focusSessionsCompleted: Int {
        get { completedFocusSessions }
        set { completedFocusSessions = max(0, newValue) }
    }

    public var isRunning: Bool { state == .running }
    public var isPaused: Bool { state == .paused }

    /// Compatibility aliases for consumers that call this collection
    /// `sessions` or `cycleHistory`.
    public var sessions: [TimerSessionRecord] {
        get { sessionHistory }
        set { sessionHistory = newValue }
    }

    public var cycleHistory: [TimerCycleRecord] {
        get { cycles }
        set { cycles = newValue }
    }

    public var activeSession: TimerSessionRecord? {
        guard let activeSessionID else { return nil }
        return sessionHistory.first(where: { $0.id == activeSessionID })
    }

    public var activeCycle: TimerCycleRecord? {
        guard let activeCycleID else { return nil }
        return cycles.first(where: { $0.id == activeCycleID })
    }

    public init(
        phase: TimerPhase = .focus,
        isRunning: Bool,
        deadline: Date? = nil,
        remaining: TimeInterval = 0,
        completedFocusSessions: Int = 0,
        artwork: Artwork? = nil,
        artworkJourneyID: UUID? = nil,
        artworkProgress: ArtworkProgress? = nil,
        completedArtworks: [CompletedArtwork] = [],
        sessionHistory: [TimerSessionRecord] = [],
        cycles: [TimerCycleRecord] = [],
        activeSessionID: UUID? = nil,
        activeCycleID: UUID? = nil
    ) {
        self.init(
            phase: phase,
            state: isRunning ? .running : .idle,
            deadline: deadline,
            remaining: remaining,
            completedFocusSessions: completedFocusSessions,
            artwork: artwork,
            artworkJourneyID: artworkJourneyID,
            artworkProgress: artworkProgress,
            completedArtworks: completedArtworks,
            sessionHistory: sessionHistory,
            cycles: cycles,
            activeSessionID: activeSessionID,
            activeCycleID: activeCycleID
        )
    }

    private enum CodingKeys: String, CodingKey {
        case phase
        case state
        case startedAt
        case deadline
        case remaining
        case completedFocusSessions
        case focusSessionsCompleted
        case configuration
        case artwork
        case artworkJourneyID
        case journeyID
        case artworkProgress
        case completedArtworks
        case sessionHistory
        case sessions
        case cycles
        case cycleHistory
        case activeSessionID
        case activeSessionId
        case activeCycleID
        case activeCycleId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.phase = try c.decodeIfPresent(TimerPhase.self, forKey: .phase) ?? .focus
        self.state = try c.decodeIfPresent(TimerState.self, forKey: .state) ?? .idle
        self.startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        self.deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        self.remaining = max(0, try c.decodeIfPresent(TimeInterval.self, forKey: .remaining) ?? 0)
        let completedPrimary = try c.decodeIfPresent(Int.self, forKey: .completedFocusSessions)
        let completedAlias = try c.decodeIfPresent(Int.self, forKey: .focusSessionsCompleted)
        let completed = completedPrimary ?? completedAlias ?? 0
        self.completedFocusSessions = max(0, completed)
        self.configuration = try c.decodeIfPresent(TimerConfiguration.self, forKey: .configuration)
        self.artwork = try c.decodeIfPresent(Artwork.self, forKey: .artwork)
        self.artworkJourneyID = try c.decodeIfPresent(UUID.self, forKey: .artworkJourneyID)
            ?? c.decodeIfPresent(UUID.self, forKey: .journeyID)
        self.artworkProgress = try c.decodeIfPresent(ArtworkProgress.self, forKey: .artworkProgress)
        self.completedArtworks = try c.decodeIfPresent([CompletedArtwork].self, forKey: .completedArtworks) ?? []
        self.sessionHistory = try c.decodeIfPresent([TimerSessionRecord].self, forKey: .sessionHistory)
            ?? c.decodeIfPresent([TimerSessionRecord].self, forKey: .sessions)
            ?? []
        self.cycles = try c.decodeIfPresent([TimerCycleRecord].self, forKey: .cycles)
            ?? c.decodeIfPresent([TimerCycleRecord].self, forKey: .cycleHistory)
            ?? []
        self.activeSessionID = try c.decodeIfPresent(UUID.self, forKey: .activeSessionID)
            ?? c.decodeIfPresent(UUID.self, forKey: .activeSessionId)
        self.activeCycleID = try c.decodeIfPresent(UUID.self, forKey: .activeCycleID)
            ?? c.decodeIfPresent(UUID.self, forKey: .activeCycleId)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(phase, forKey: .phase)
        try c.encode(state, forKey: .state)
        try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(deadline, forKey: .deadline)
        try c.encode(remaining, forKey: .remaining)
        try c.encode(completedFocusSessions, forKey: .completedFocusSessions)
        try c.encodeIfPresent(configuration, forKey: .configuration)
        try c.encodeIfPresent(artwork, forKey: .artwork)
        try c.encodeIfPresent(artworkJourneyID, forKey: .artworkJourneyID)
        try c.encodeIfPresent(artworkProgress, forKey: .artworkProgress)
        try c.encode(completedArtworks, forKey: .completedArtworks)
        try c.encode(sessionHistory, forKey: .sessionHistory)
        try c.encode(cycles, forKey: .cycles)
        try c.encodeIfPresent(activeSessionID, forKey: .activeSessionID)
        try c.encodeIfPresent(activeCycleID, forKey: .activeCycleID)
    }

    /// Migrates the v1 single-snapshot representation. Only a genuinely
    /// running/paused period is synthesized; idle snapshots do not acquire
    /// fabricated historical records. Calling this repeatedly is idempotent.
    public mutating func migrateSessionHistory(at date: Date = Date()) {
        var history = sessionHistory
        var cycleHistory = cycles

        let activeIndices = history.indices.filter { history[$0].status.isActive }
        if let requested = activeSessionID,
           let requestedIndex = history.firstIndex(where: { $0.id == requested }),
           history[requestedIndex].status.isActive {
            for index in activeIndices where index != requestedIndex {
                history[index].transition(to: .abandoned, at: date)
            }
        } else if activeIndices.count > 1 {
            let keeper = activeIndices.last!
            for index in activeIndices where index != keeper {
                history[index].transition(to: .abandoned, at: date)
            }
            activeSessionID = history[keeper].id
        } else if let only = activeIndices.first {
            activeSessionID = history[only].id
        }

        if activeSessionID == nil, (state == .running || state == .paused) {
            let cycleID = UUID()
            let id = UUID()
            let record = TimerSessionRecord(
                id: id,
                cycleID: cycleID,
                phase: phase,
                status: state == .running ? .running : .paused,
                artworkID: artwork?.id,
                artworkJourneyID: artworkJourneyID,
                startedAt: startedAt,
                plannedDuration: configuration.map { Self.duration(for: phase, configuration: $0) } ?? remaining,
                elapsed: 0,
                remaining: remaining
            )
            history.append(record)
            activeSessionID = id
            cycleHistory.append(
                TimerCycleRecord(
                    id: cycleID,
                    focusSessionID: phase == .focus ? id : nil,
                    breakSessionID: phase.isBreak ? id : nil,
                    artworkID: artwork?.id,
                    artworkJourneyID: artworkJourneyID,
                    status: state == .running ? .running : .paused,
                    startedAt: startedAt
                )
            )
            activeCycleID = cycleID
        } else if let activeSessionID,
                  let active = history.first(where: { $0.id == activeSessionID }) {
            if activeCycleID == nil { activeCycleID = active.cycleID }
        }

        sessionHistory = history
        cycles = cycleHistory
        normalizeActiveIDs(at: date)
    }

    public mutating func migrateFromV1(at date: Date = Date()) {
        migrateSessionHistory(at: date)
    }

    private mutating func normalizeActiveIDs(at date: Date) {
        let active = sessionHistory.filter { $0.status.isActive }
        if active.isEmpty {
            activeSessionID = nil
            activeCycleID = nil
            return
        }
        let keeperID = activeSessionID.flatMap { id in active.contains(where: { $0.id == id }) ? id : nil }
            ?? active.last!.id
        for index in sessionHistory.indices where sessionHistory[index].status.isActive && sessionHistory[index].id != keeperID {
            sessionHistory[index].transition(to: .abandoned, at: date)
        }
        activeSessionID = keeperID
        activeCycleID = activeCycleID.flatMap { id in cycles.contains(where: { $0.id == id }) ? id : nil }
            ?? sessionHistory.first(where: { $0.id == keeperID })?.cycleID
    }

    private static func duration(for phase: TimerPhase, configuration: TimerConfiguration) -> TimeInterval {
        switch phase {
        case .focus: configuration.focusDuration
        case .shortBreak: configuration.shortBreakDuration
        case .longBreak: configuration.longBreakDuration
        }
    }
}

/// An image imported into Tela.  The image itself remains on disk; only its
/// local URL and dimensions are persisted in the app state.
public struct Artwork: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var fileURL: URL?
    /// Name of an image bundled with the app.  It is deliberately separate
    /// from `fileURL`, so bundled open-access works remain portable.
    public var assetName: String?
    public var artist: String?
    public var source: String?
    public var credit: String?
    public var catalogueIdentifier: String?
    public var year: String?
    /// Curated shelves an artwork belongs to. Optional for backward-compatible
    /// decoding of snapshots created before collections were introduced.
    public var collections: [String]?
    public var width: Int
    public var height: Int
    public var tileCount: Int
    public var seed: UInt64

    public init(
        id: UUID = UUID(),
        name: String,
        fileURL: URL? = nil,
        assetName: String? = nil,
        artist: String? = nil,
        source: String? = nil,
        credit: String? = nil,
        catalogueIdentifier: String? = nil,
        year: String? = nil,
        collections: [String]? = nil,
        width: Int = 0,
        height: Int = 0,
        tileCount: Int = 12,
        seed: UInt64? = nil
    ) {
        self.id = id
        self.name = name
        self.fileURL = fileURL
        self.assetName = assetName
        self.artist = artist
        self.source = source
        self.credit = credit
        self.catalogueIdentifier = catalogueIdentifier
        self.year = year
        self.collections = collections
        self.width = max(0, width)
        self.height = max(0, height)
        self.tileCount = max(1, tileCount)
        self.seed = seed ?? Artwork.seed(for: id)
    }

    public init(
        id: UUID = UUID(),
        title: String,
        url: URL? = nil,
        assetName: String? = nil,
        artist: String? = nil,
        source: String? = nil,
        credit: String? = nil,
        catalogueIdentifier: String? = nil,
        year: String? = nil,
        collections: [String]? = nil,
        pixelWidth: Int = 0,
        pixelHeight: Int = 0,
        tileCount: Int = 12,
        seed: UInt64? = nil
    ) {
        self.init(
            id: id,
            name: title,
            fileURL: url,
            assetName: assetName,
            artist: artist,
            source: source,
            credit: credit,
            catalogueIdentifier: catalogueIdentifier,
            year: year,
            collections: collections,
            width: pixelWidth,
            height: pixelHeight,
            tileCount: tileCount,
            seed: seed
        )
    }

    public var title: String {
        get { name }
        set { name = newValue }
    }

    public var url: URL? {
        get { fileURL }
        set { fileURL = newValue }
    }

    public var imageURL: URL? {
        get { fileURL }
        set { fileURL = newValue }
    }

    public var catalogueID: String? {
        get { catalogueIdentifier }
        set { catalogueIdentifier = newValue }
    }

    public var objectID: String? {
        get { catalogueIdentifier }
        set { catalogueIdentifier = newValue }
    }

    public var pixelWidth: Int {
        get { width }
        set { width = max(0, newValue) }
    }

    public var pixelHeight: Int {
        get { height }
        set { height = max(0, newValue) }
    }

    private static func seed(for id: UUID) -> UInt64 {
        // UUID bytes are stable once persisted.  Avoid hashing UUID.hashValue,
        // whose seed is intentionally randomized for each process.
        withUnsafeBytes(of: id.uuid) { bytes in
            bytes.reduce(UInt64(0xcbf29ce484222325)) { partial, byte in
                (partial ^ UInt64(byte)) &* 0x100000001b3
            }
        }
    }
}

/// Open-access works shipped by Tela. The asset catalog stays fully offline;
/// this loader combines stable curation metadata with captured file credits.
public enum ArtworkGallery {
    private struct CatalogEntry: Decodable {
        let assetName: String
        let artist: String
        let title: String
        let year: String
        let collections: [String]
    }

    private struct ResolutionEntry: Decodable {
        let assetName: String
        let commonsTitle: String?
        let commonsPage: String?
        let license: String?
    }

    private final class BundleToken {}

    public static let defaults: [Artwork] = originals + curatedCatalog

    private static let originals: [Artwork] = [
        Artwork(
            id: UUID(uuidString: "e11d8f1a-0e16-4f75-9a9c-4f5a4f6e2a01")!,
            name: "Water Lilies",
            assetName: "MonetWaterLilies",
            artist: "Claude Monet",
            source: "Art Institute of Chicago",
            credit: "Open access, Art Institute of Chicago",
            catalogueIdentifier: "16568",
            year: "1906",
            collections: ["Impressionismo"]
        ),
        Artwork(
            id: UUID(uuidString: "e11d8f1a-0e16-4f75-9a9c-4f5a4f6e2a02")!,
            name: "The Bedroom",
            assetName: "VanGoghBedroom",
            artist: "Vincent van Gogh",
            source: "Art Institute of Chicago",
            credit: "Open access, Art Institute of Chicago",
            catalogueIdentifier: "28560",
            year: "1889",
            collections: ["Post-impressionismo"]
        ),
        Artwork(
            id: UUID(uuidString: "e11d8f1a-0e16-4f75-9a9c-4f5a4f6e2a03")!,
            name: "The Great Wave",
            assetName: "HokusaiGreatWave",
            artist: "Katsushika Hokusai",
            source: "The Metropolitan Museum of Art",
            credit: "Open access, The Metropolitan Museum of Art",
            catalogueIdentifier: "56353",
            year: "ca. 1830–32",
            collections: ["Ukiyo-e"]
        )
    ]

    private static let curatedCatalog: [Artwork] = {
        let candidateBundles = [Bundle.main, Bundle(for: BundleToken.self)] + Bundle.allBundles
        guard let url = candidateBundles.lazy.compactMap({
            $0.url(forResource: "public_domain_artworks", withExtension: "json")
        }).first,
        let data = try? Data(contentsOf: url),
        let entries = try? JSONDecoder().decode([CatalogEntry].self, from: data) else {
            return []
        }

        let resolvedByAsset: [String: ResolutionEntry] = {
            guard let reportURL = candidateBundles.lazy.compactMap({
                $0.url(forResource: "ArtworkDownloadReport", withExtension: "json")
            }).first,
            let reportData = try? Data(contentsOf: reportURL),
            let records = try? JSONDecoder().decode([ResolutionEntry].self, from: reportData) else {
                return [:]
            }
            return Dictionary(uniqueKeysWithValues: records.map { ($0.assetName, $0) })
        }()

        return entries.map { entry in
            let resolution = resolvedByAsset[entry.assetName]
            let license = resolution?.license ?? "Licenza aperta verificata"
            return Artwork(
                id: stableID(for: entry.assetName),
                name: entry.title,
                assetName: entry.assetName,
                artist: entry.artist,
                source: resolution?.commonsPage ?? "Wikimedia Commons",
                credit: "\(license) · Wikimedia Commons",
                catalogueIdentifier: resolution?.commonsTitle,
                year: entry.year,
                collections: entry.collections
            )
        }
    }()

    private static func stableID(for key: String) -> UUID {
        var first: UInt64 = 0xcbf29ce484222325
        var second: UInt64 = 0x9e3779b97f4a7c15
        for byte in key.utf8 {
            first = (first ^ UInt64(byte)) &* 0x100000001b3
            second = (second &+ UInt64(byte)) &* 0x9e3779b185ebca87
        }
        var bytes = withUnsafeBytes(of: first.bigEndian, Array.init)
        bytes.append(contentsOf: withUnsafeBytes(of: second.bigEndian, Array.init))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// Tiles revealed for an artwork.  The set is persisted as an array by
/// Codable in order to keep JSON deterministic and human-readable.
public struct ArtworkProgress: Codable, Equatable, Sendable {
    public var artworkID: UUID
    public var totalTiles: Int
    public var revealedTiles: Set<Int>

    public init(
        artworkID: UUID,
        totalTiles: Int,
        revealedTiles: Set<Int> = []
    ) {
        self.artworkID = artworkID
        let normalizedTotal = max(1, totalTiles)
        self.totalTiles = normalizedTotal
        self.revealedTiles = Set(revealedTiles.filter { $0 >= 0 && $0 < normalizedTotal })
    }

    public init(artworkID: UUID, tileCount: Int, revealedTileIndices: [Int] = []) {
        self.init(artworkID: artworkID, totalTiles: tileCount, revealedTiles: Set(revealedTileIndices))
    }

    public init(artworkID: UUID, revealedTileIndices: [Int], totalTiles: Int) {
        self.init(artworkID: artworkID, totalTiles: totalTiles, revealedTiles: Set(revealedTileIndices))
    }

    public var revealedTileIndices: [Int] {
        get { revealedTiles.sorted() }
        set { revealedTiles = Set(newValue.filter { $0 >= 0 && $0 < totalTiles }) }
    }

    public var revealedTileCount: Int { revealedTiles.count }
    public var isComplete: Bool { revealedTiles.count >= totalTiles }

    @discardableResult
    public mutating func reveal(tile index: Int) -> Bool {
        guard index >= 0, index < totalTiles else { return false }
        return revealedTiles.insert(index).inserted
    }

    @discardableResult
    public mutating func revealNext(using order: [Int]) -> Int? {
        guard !isComplete else { return nil }
        guard let tile = order.first(where: { !revealedTiles.contains($0) }) else { return nil }
        revealedTiles.insert(tile)
        return tile
    }

    private enum CodingKeys: String, CodingKey {
        case artworkID
        case artworkId
        case totalTiles
        case tileCount
        case revealedTiles
        case revealedTileIndices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let primaryID = try c.decodeIfPresent(UUID.self, forKey: .artworkID)
        let aliasID = try c.decodeIfPresent(UUID.self, forKey: .artworkId)
        let id = primaryID ?? aliasID ?? UUID()
        let primaryCount = try c.decodeIfPresent(Int.self, forKey: .totalTiles)
        let aliasCount = try c.decodeIfPresent(Int.self, forKey: .tileCount)
        let count = primaryCount ?? aliasCount ?? 1
        let primaryTiles = try c.decodeIfPresent(Set<Int>.self, forKey: .revealedTiles)
        let aliasTiles = try c.decodeIfPresent([Int].self, forKey: .revealedTileIndices)
        let tiles = primaryTiles ?? Set(aliasTiles ?? [])
        self.init(artworkID: id, totalTiles: count, revealedTiles: tiles)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(artworkID, forKey: .artworkID)
        try c.encode(totalTiles, forKey: .totalTiles)
        try c.encode(revealedTileIndices, forKey: .revealedTileIndices)
    }
}

/// A durable record that an artwork reached 100% reveal.
public struct CompletedArtwork: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let artworkID: UUID
    public let completedAt: Date
    public let focusSessions: Int
    public let revealedTileCount: Int
    /// True when the artwork reached 100% before its focus+break routine was
    /// fully completed. This record can be upgraded later in place.
    public var partialRoutine: Bool
    /// True once the complete focus+break routine has been completed.
    public var completeRoutine: Bool
    public var artworkJourneyID: UUID?
    public var contributingSessionIDs: [UUID]
    public var expectedCycles: Int
    public var completedCycles: Int
    public var missingPauseSessionIDs: [UUID]

    private enum CodingKeys: String, CodingKey {
        case id
        case artworkID
        case artworkId
        case completedAt
        case focusSessions
        case sessionCount
        case revealedTileCount
        case revealCount
        case partialRoutine
        case completeRoutine
        case artworkJourneyID
        case journeyID
        case contributingSessionIDs
        case sessionIDs
        case expectedCycles
        case completedCycles
        case missingPauseSessionIDs
        case missingPauseIDs
    }

    public init(
        id: UUID = UUID(),
        artworkID: UUID,
        completedAt: Date = Date(),
        focusSessions: Int,
        revealedTileCount: Int,
        partialRoutine: Bool = false,
        completeRoutine: Bool = true,
        artworkJourneyID: UUID? = nil,
        contributingSessionIDs: [UUID] = [],
        expectedCycles: Int = 0,
        completedCycles: Int = 0,
        missingPauseSessionIDs: [UUID] = []
    ) {
        self.id = id
        self.artworkID = artworkID
        self.completedAt = completedAt
        self.focusSessions = max(0, focusSessions)
        self.revealedTileCount = max(0, revealedTileCount)
        self.partialRoutine = partialRoutine
        self.completeRoutine = completeRoutine && !partialRoutine
        self.artworkJourneyID = artworkJourneyID
        self.contributingSessionIDs = contributingSessionIDs
        self.expectedCycles = max(0, expectedCycles)
        self.completedCycles = max(0, completedCycles)
        self.missingPauseSessionIDs = missingPauseSessionIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let artworkID = try c.decodeIfPresent(UUID.self, forKey: .artworkID)
            ?? c.decode(UUID.self, forKey: .artworkId)
        let focusSessions = try c.decodeIfPresent(Int.self, forKey: .focusSessions)
            ?? c.decodeIfPresent(Int.self, forKey: .sessionCount)
            ?? 0
        let revealedTileCount = try c.decodeIfPresent(Int.self, forKey: .revealedTileCount)
            ?? c.decodeIfPresent(Int.self, forKey: .revealCount)
            ?? 0
        let partialRoutine = try c.decodeIfPresent(Bool.self, forKey: .partialRoutine) ?? false
        let completeRoutine = try c.decodeIfPresent(Bool.self, forKey: .completeRoutine)
            ?? !partialRoutine
        self.init(
            id: try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID(),
            artworkID: artworkID,
            completedAt: try c.decodeIfPresent(Date.self, forKey: .completedAt) ?? Date(),
            focusSessions: focusSessions,
            revealedTileCount: revealedTileCount,
            partialRoutine: partialRoutine,
            completeRoutine: completeRoutine,
            artworkJourneyID: try c.decodeIfPresent(UUID.self, forKey: .artworkJourneyID)
                ?? c.decodeIfPresent(UUID.self, forKey: .journeyID),
            contributingSessionIDs: try c.decodeIfPresent([UUID].self, forKey: .contributingSessionIDs)
                ?? c.decodeIfPresent([UUID].self, forKey: .sessionIDs)
                ?? [],
            expectedCycles: try c.decodeIfPresent(Int.self, forKey: .expectedCycles) ?? 0,
            completedCycles: try c.decodeIfPresent(Int.self, forKey: .completedCycles) ?? 0,
            missingPauseSessionIDs: try c.decodeIfPresent([UUID].self, forKey: .missingPauseSessionIDs)
                ?? c.decodeIfPresent([UUID].self, forKey: .missingPauseIDs)
                ?? []
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(artworkID, forKey: .artworkID)
        try c.encode(completedAt, forKey: .completedAt)
        try c.encode(focusSessions, forKey: .focusSessions)
        try c.encode(revealedTileCount, forKey: .revealedTileCount)
        try c.encode(partialRoutine, forKey: .partialRoutine)
        try c.encode(completeRoutine, forKey: .completeRoutine)
        try c.encodeIfPresent(artworkJourneyID, forKey: .artworkJourneyID)
        try c.encode(contributingSessionIDs, forKey: .contributingSessionIDs)
        try c.encode(expectedCycles, forKey: .expectedCycles)
        try c.encode(completedCycles, forKey: .completedCycles)
        try c.encode(missingPauseSessionIDs, forKey: .missingPauseSessionIDs)
    }

    public init(
        id: UUID = UUID(),
        artworkID: UUID,
        completedAt: Date = Date(),
        focusSessions: Int,
        revealCount: Int,
        partialRoutine: Bool = false,
        completeRoutine: Bool = true,
        artworkJourneyID: UUID? = nil,
        contributingSessionIDs: [UUID] = [],
        expectedCycles: Int = 0,
        completedCycles: Int = 0,
        missingPauseSessionIDs: [UUID] = []
    ) {
        self.init(
            id: id,
            artworkID: artworkID,
            completedAt: completedAt,
            focusSessions: focusSessions,
            revealedTileCount: revealCount,
            partialRoutine: partialRoutine,
            completeRoutine: completeRoutine,
            artworkJourneyID: artworkJourneyID,
            contributingSessionIDs: contributingSessionIDs,
            expectedCycles: expectedCycles,
            completedCycles: completedCycles,
            missingPauseSessionIDs: missingPauseSessionIDs
        )
    }

    public var sessionCount: Int { focusSessions }

    /// Marks the routine complete while preserving the original record id and
    /// reveal timestamp. Calling it repeatedly is idempotent.
    @discardableResult
    public mutating func upgradeToCompleteRoutine() -> Bool {
        guard !completeRoutine else { return false }
        completeRoutine = true
        partialRoutine = false
        if expectedCycles > 0 { completedCycles = expectedCycles }
        missingPauseSessionIDs.removeAll()
        return true
    }

    public var routineWasPartial: Bool { partialRoutine }
    public var routineWasComplete: Bool { completeRoutine }
    public var journeyID: UUID {
        get { artworkJourneyID ?? artworkID }
        set { artworkJourneyID = newValue }
    }
    public var contributingIDs: [UUID] {
        get { contributingSessionIDs }
        set { contributingSessionIDs = newValue }
    }
    public var missingPauseIDs: [UUID] {
        get { missingPauseSessionIDs }
        set { missingPauseSessionIDs = newValue }
    }
}
