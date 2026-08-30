#if TELA_DEMO
import Foundation
import Observation
import SwiftUI

/// A single period in the self-contained demo timeline.
///
/// The demo deliberately uses seconds rather than the production timer's
/// minute-oriented settings.  That keeps a complete product walkthrough short
/// enough to record while leaving `TimerStore` and the user's real settings
/// untouched.
public struct DemoSegment: Equatable, Identifiable, Sendable {
    public let index: Int
    public let phase: TimerPhase
    public let duration: TimeInterval

    public var id: Int { index }

    public init(index: Int, phase: TimerPhase, duration: TimeInterval) {
        self.index = index
        self.phase = phase
        self.duration = max(0, duration)
    }

    public var title: String {
        switch phase {
        case .focus: return "Concentrazione"
        case .shortBreak: return "Pausa breve"
        case .longBreak: return "Pausa lunga"
        }
    }
}

/// Presentation origins used by the demo's radial reveal.  The selection is
/// intentionally an enum so it can be driven by a keyboard-accessible Picker;
/// the view-facing `unitPoint` remains a real SwiftUI `UnitPoint`.
public enum DemoRevealOrigin: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case topLeading
    case top
    case topTrailing
    case leading
    case center
    case trailing
    case bottomLeading
    case bottom
    case bottomTrailing

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Casuale"
        case .topLeading: return "In alto a sinistra"
        case .top: return "In alto"
        case .topTrailing: return "In alto a destra"
        case .leading: return "A sinistra"
        case .center: return "Al centro"
        case .trailing: return "A destra"
        case .bottomLeading: return "In basso a sinistra"
        case .bottom: return "In basso"
        case .bottomTrailing: return "In basso a destra"
        }
    }

    public var unitPoint: UnitPoint {
        switch self {
        case .automatic: return .center
        case .topLeading: return .topLeading
        case .top: return .top
        case .topTrailing: return .topTrailing
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        case .bottomLeading: return .bottomLeading
        case .bottom: return .bottom
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

/// A first-class, ephemeral playback engine for product walkthroughs.
///
/// This store intentionally has no `Persistence`, `Notifications`, or
/// `UserDefaults` dependency.  It owns an in-memory timeline and a supplied
/// clock, so starting, resetting, or closing a demo cannot touch the real
/// Pomodoro session.  The default timeline is 4 × 8-second focus periods with
/// 3-second short breaks and a 5-second long break (46 seconds total).
@MainActor
@Observable
public final class DemoSessionStore {
    public static let defaultSchedule: [DemoSegment] = [
        DemoSegment(index: 0, phase: .focus, duration: 8),
        DemoSegment(index: 1, phase: .shortBreak, duration: 3),
        DemoSegment(index: 2, phase: .focus, duration: 8),
        DemoSegment(index: 3, phase: .shortBreak, duration: 3),
        DemoSegment(index: 4, phase: .focus, duration: 8),
        DemoSegment(index: 5, phase: .shortBreak, duration: 3),
        DemoSegment(index: 6, phase: .focus, duration: 8),
        DemoSegment(index: 7, phase: .longBreak, duration: 5)
    ]

    /// A bundled image gives the default walkthrough a stable, offline visual.
    public static let defaultArtwork = Artwork(
        id: UUID(uuidString: "e11d8f1a-0e16-4f75-9a9c-4f5a4f6e2a01")!,
        name: "Water Lilies",
        assetName: "MonetWaterLilies",
        artist: "Claude Monet",
        source: "Art Institute of Chicago",
        credit: "Open access, Art Institute of Chicago",
        catalogueIdentifier: "16568",
        year: "1906",
        tileCount: 4,
        seed: 0x54454C415F44454D
    )

    public let clock: any Clock
    public let schedule: [DemoSegment]
    public let artwork: Artwork

    /// Whether a running segment automatically starts the next one when its
    /// deadline is reached.  It defaults to true for recording playback, while
    /// tests and guided narration can turn it off and use `step()` manually.
    public var autoplay: Bool

    public private(set) var state: TimerState = .idle
    public private(set) var phase: TimerPhase = .focus
    public private(set) var segmentIndex: Int = 0
    public private(set) var remaining: TimeInterval
    public private(set) var deadline: Date?
    public private(set) var startedAt: Date?
    public private(set) var completedFocusSessions: Int = 0
    public private(set) var isFinished = false

    public var cleanRecording = false
    public var revealOriginSelection: DemoRevealOrigin = .automatic

    private var tickTask: Task<Void, Never>?

    public var currentSegment: DemoSegment { schedule[segmentIndex] }
    public var revealOrigin: UnitPoint? {
        revealOriginSelection == .automatic ? nil : revealOriginSelection.unitPoint
    }
    public var revealJourneyID: UUID {
        UUID(uuidString: "A64AE799-18EF-43F8-9858-BA032E0BDA35")!
    }
    public var totalDuration: TimeInterval { schedule.reduce(0) { $0 + $1.duration } }
    public var hasCompletedArtwork: Bool { completedFocusSessions >= focusGoal }
    public var focusGoal: Int { schedule.filter { $0.phase == .focus }.count }

    /// The fraction of the current focus period that is complete.  Breaks do
    /// not preview artwork because they never consolidate focus progress.
    public var currentFocusProgress: Double {
        guard phase == .focus, state != .idle else { return 0 }
        let duration = currentSegment.duration
        guard duration > 0 else { return 1 }
        let elapsed: TimeInterval
        switch state {
        case .running:
            elapsed = duration - remaining(at: clock.now)
        case .paused:
            elapsed = duration - remaining
        case .idle:
            elapsed = 0
        }
        return min(max(elapsed / duration, 0), 1)
    }

    /// A continuous reveal preview matching Tela's production presentation:
    /// committed focus sessions plus the currently active focus fraction.
    public var revealProgress: Double {
        let preview = phase == .focus && state != .idle ? currentFocusProgress : 0
        return min(max((Double(completedFocusSessions) + preview) / Double(max(focusGoal, 1)), 0), 1)
    }

    public var progress: Double {
        guard currentSegment.duration > 0 else { return state == .idle ? 0 : 1 }
        return min(max((currentSegment.duration - remaining(at: clock.now)) / currentSegment.duration, 0), 1)
    }

    public init(
        clock: any Clock = SystemClock(),
        schedule: [DemoSegment] = DemoSessionStore.defaultSchedule,
        artwork: Artwork = DemoSessionStore.defaultArtwork,
        autoplay: Bool = true,
        automaticallyTicks: Bool = true
    ) {
        self.clock = clock
        let normalized = schedule.enumerated().map {
            DemoSegment(index: $0.offset, phase: $0.element.phase, duration: $0.element.duration)
        }
        self.schedule = normalized.isEmpty ? DemoSessionStore.defaultSchedule : normalized
        self.artwork = artwork
        self.autoplay = autoplay
        self.remaining = self.schedule[0].duration
        self.phase = self.schedule[0].phase
        if automaticallyTicks {
            startTickLoop()
        }
    }

    // MARK: Playback controls

    /// Starts the current segment, or resumes a paused one.
    public func play() {
        guard !isFinished else { return }
        guard state != .running else { return }
        let duration = state == .paused ? remaining : currentSegment.duration
        startCurrent(at: clock.now, duration: duration)
    }

    public func pause() {
        guard state == .running else { return }
        let now = clock.now
        remaining = max(0, remaining(at: now))
        state = .paused
        deadline = nil
        persistlessStateDidChange()
    }

    public func togglePlayPause() {
        if state == .running { pause() } else { play() }
    }

    /// Completes the current segment immediately.  When the segment was
    /// playing and autoplay is enabled, the next segment starts at the same
    /// logical instant; otherwise the next segment is left idle for narration.
    public func step() {
        guard !isFinished else { return }
        let wasRunning = state == .running
        let transitionDate = wasRunning ? (deadline ?? clock.now) : clock.now
        finishCurrent(at: transitionDate, continueAutomatically: wasRunning && autoplay)
    }

    /// Returns to the first focus period and forgets all demo-only progress.
    /// This does not alter production state because the demo has no persistence.
    public func reset() {
        state = .idle
        phase = schedule[0].phase
        segmentIndex = 0
        remaining = schedule[0].duration
        deadline = nil
        startedAt = nil
        completedFocusSessions = 0
        isFinished = false
        persistlessStateDidChange()
    }

    // MARK: Deterministic clock surface

    public func tick() {
        tick(at: clock.now)
    }

    /// Advances playback to an injected instant.  Tests can call this with a
    /// `MutableClock` without sleeping; the production view uses the no-arg
    /// version from the lightweight refresh task above.
    public func tick(at now: Date) {
        guard state == .running else { return }
        var transitions = 0
        while state == .running,
              let currentDeadline = deadline,
              currentDeadline <= now,
              transitions < schedule.count + 2 {
            transitions += 1
            finishCurrent(at: currentDeadline, continueAutomatically: autoplay)
        }
        if state == .running {
            remaining = remaining(at: now)
        }
    }

    // MARK: Private transition helpers

    private func startTickLoop() {
        tickTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func startCurrent(at start: Date, duration: TimeInterval) {
        phase = currentSegment.phase
        state = .running
        startedAt = start
        remaining = max(0, duration)
        deadline = start.addingTimeInterval(remaining)
        persistlessStateDidChange()
    }

    private func finishCurrent(at completionDate: Date, continueAutomatically: Bool) {
        guard !isFinished else { return }

        if phase == .focus {
            completedFocusSessions = min(completedFocusSessions + 1, focusGoal)
        }

        guard segmentIndex + 1 < schedule.count else {
            segmentIndex = schedule.count - 1
            phase = schedule[segmentIndex].phase
            state = .idle
            startedAt = nil
            deadline = nil
            remaining = 0
            isFinished = true
            persistlessStateDidChange()
            return
        }

        segmentIndex += 1
        phase = schedule[segmentIndex].phase
        state = .idle
        startedAt = nil
        deadline = nil
        remaining = schedule[segmentIndex].duration

        if continueAutomatically {
            startCurrent(at: completionDate, duration: remaining)
        } else {
            persistlessStateDidChange()
        }
    }

    private func remaining(at now: Date) -> TimeInterval {
        guard state == .running, let deadline else { return max(0, remaining) }
        return max(0, deadline.timeIntervalSince(now))
    }

    /// This no-op is intentionally named to make the absence of persistence
    /// explicit at every state mutation and to keep future integration honest.
    private func persistlessStateDidChange() {}
}
#endif
