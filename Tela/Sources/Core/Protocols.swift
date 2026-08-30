import Foundation

/// A small date source that makes all timer transitions deterministic in tests.
public protocol Clock {
    var now: Date { get }
}

public extension Clock {
    func currentDate() -> Date { now }
}

public struct SystemClock: Clock, Sendable {
    public init() {}
    public var now: Date { Date() }
}

/// A mutable clock useful to clients and unit tests.
public final class MutableClock: Clock, @unchecked Sendable {
    public var now: Date
    public init(now: Date = Date()) { self.now = now }
}

/// The persisted unit used by `TimerStore`.
public protocol Persistence {
    func load() throws -> TimerSnapshot?
    func save(_ snapshot: TimerSnapshot) throws
}

public extension Persistence {
    func load() throws -> TimerSnapshot? { nil }
    func save(_ snapshot: TimerSnapshot) throws {}
    func loadSnapshot() throws -> TimerSnapshot? { try load() }
    func saveSnapshot(_ snapshot: TimerSnapshot) throws { try save(snapshot) }
}

public struct NullPersistence: Persistence, Sendable {
    public init() {}
}

/// In-memory persistence is intentionally part of the core API: it is useful
/// for previews and tests without touching the user's Application Support.
public final class InMemoryPersistence: Persistence, @unchecked Sendable {
    public private(set) var snapshot: TimerSnapshot?
    public var saveCount: Int = 0

    public init(snapshot: TimerSnapshot? = nil) {
        self.snapshot = snapshot
    }

    public func load() throws -> TimerSnapshot? { snapshot }

    public func save(_ snapshot: TimerSnapshot) throws {
        self.snapshot = snapshot
        saveCount += 1
    }
}

public enum TimerNotification: Equatable, Sendable {
    case scheduled(phase: TimerPhase, deadline: Date)
    case cancelled
    case completed(phase: TimerPhase)

    public var phase: TimerPhase? {
        switch self {
        case let .scheduled(phase, _), let .completed(phase): return phase
        case .cancelled: return nil
        }
    }
}

/// Notification side effects are kept behind this protocol so the timer core
/// remains usable in a command-line process and in deterministic tests.
public protocol Notifications {
    func schedule(deadline: Date, phase: TimerPhase)
    func cancel()
    func notify(_ notification: TimerNotification)
}

public extension Notifications {
    func schedule(deadline: Date, phase: TimerPhase) {}
    func schedule(at deadline: Date, phase: TimerPhase) { schedule(deadline: deadline, phase: phase) }
    func cancel() {}
    func cancelScheduledNotifications() { cancel() }
    func notify(_ notification: TimerNotification) {}
}

public struct NullNotifications: Notifications, Sendable {
    public init() {}
}

public final class RecordingNotifications: Notifications, @unchecked Sendable {
    public private(set) var events: [TimerNotification] = []
    public init() {}

    public func schedule(deadline: Date, phase: TimerPhase) {
        events.append(.scheduled(phase: phase, deadline: deadline))
    }

    public func cancel() {
        events.append(.cancelled)
    }

    public func notify(_ notification: TimerNotification) {
        events.append(notification)
    }
}
