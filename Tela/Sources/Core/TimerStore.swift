import Combine
import Foundation

/// Main-actor timer coordinator.  The deadline, rather than a decrementing
/// counter, is persisted so suspension and relaunch cannot lose elapsed time.
@MainActor
public final class TimerStore: ObservableObject {
    @Published public private(set) var configuration: TimerConfiguration
    public let clock: any Clock
    public let persistence: any Persistence
    public let notifications: any Notifications

    @Published public private(set) var snapshot: TimerSnapshot
    @Published public private(set) var deadline: Date?
    @Published public private(set) var phase: TimerPhase
    @Published public private(set) var state: TimerState
    @Published public private(set) var currentArtwork: Artwork?
    @Published public private(set) var artworkProgress: ArtworkProgress?
    @Published public private(set) var completedArtworks: [CompletedArtwork]
    @Published public private(set) var sessionHistory: [TimerSessionRecord]
    @Published public private(set) var cycles: [TimerCycleRecord]
    @Published public private(set) var activeSessionID: UUID?
    @Published public private(set) var activeCycleID: UUID?
    @Published public private(set) var lastError: Error?

    public var completedFocusSessions: Int { snapshot.completedFocusSessions }

    public var remaining: TimeInterval {
        remaining(at: clock.now)
    }

    public init(
        configuration: TimerConfiguration = .default,
        clock: any Clock = SystemClock(),
        persistence: any Persistence = NullPersistence(),
        notifications: any Notifications = NullNotifications(),
        artwork: Artwork? = nil
    ) {
        self.configuration = configuration
        self.clock = clock
        self.persistence = persistence
        self.notifications = notifications

        let loaded: TimerSnapshot?
        let loadError: Error?
        do {
            loaded = try persistence.load()
            loadError = nil
        } catch {
            loaded = nil
            loadError = error
        }

        let effectiveConfiguration = loaded?.configuration ?? configuration
        var initial = loaded ?? TimerSnapshot()
        initial.configuration = effectiveConfiguration
        if initial.artwork == nil, let artwork {
            initial.artwork = artwork
            initial.artworkProgress = ArtworkProgress(artworkID: artwork.id, totalTiles: artwork.tileCount)
        }
        if let selectedArtwork = initial.artwork,
           initial.artworkProgress?.artworkID != selectedArtwork.id {
            initial.artworkProgress = ArtworkProgress(artworkID: selectedArtwork.id, totalTiles: selectedArtwork.tileCount)
        }
        if initial.artwork != nil,
           initial.artworkJourneyID == nil,
           initial.sessionHistory.isEmpty {
            initial.artworkJourneyID = UUID()
        }
        if initial.state == .running, initial.deadline == nil {
            initial.state = .idle
            initial.startedAt = nil
            initial.remaining = max(0, Self.duration(for: initial.phase, configuration: effectiveConfiguration))
        }
        initial.migrateSessionHistory(at: clock.now)

        self.configuration = effectiveConfiguration
        self.snapshot = initial
        self.deadline = initial.deadline
        self.phase = initial.phase
        self.state = initial.state
        self.currentArtwork = initial.artwork
        self.artworkProgress = initial.artworkProgress
        self.completedArtworks = initial.completedArtworks
        self.sessionHistory = initial.sessionHistory
        self.cycles = initial.cycles
        self.activeSessionID = initial.activeSessionID
        self.activeCycleID = initial.activeCycleID
        self.lastError = loadError

        if initial.state == .running {
            // Reconcile once on launch.  This also makes an expired persisted
            // deadline transition immediately instead of showing stale UI.
            reconcile(at: clock.now)
        }
    }

    /// Updates future period lengths and persists the setting. A currently
    /// running or paused period keeps its already-established deadline or
    /// remaining duration; the new values apply when the next period starts.
    public func updateConfiguration(_ newConfiguration: TimerConfiguration) {
        configuration = newConfiguration
        var next = snapshot
        next.configuration = newConfiguration
        if state == .idle {
            next.remaining = duration(for: next.phase)
        }
        set(next, notifySchedule: false)
        persist()
    }

    public func updateConfiguration(
        focusDuration: TimeInterval? = nil,
        shortBreakDuration: TimeInterval? = nil,
        longBreakDuration: TimeInterval? = nil,
        sessionsBeforeLongBreak: Int? = nil
    ) {
        var updated = configuration
        if let focusDuration { updated.focusDuration = max(0, focusDuration) }
        if let shortBreakDuration { updated.shortBreakDuration = max(0, shortBreakDuration) }
        if let longBreakDuration { updated.longBreakDuration = max(0, longBreakDuration) }
        if let sessionsBeforeLongBreak { updated.sessionsBeforeLongBreak = max(1, sessionsBeforeLongBreak) }
        updateConfiguration(updated)
    }

    public static func production(
        configuration: TimerConfiguration = .default,
        persistence: JSONPersistence = JSONPersistence(),
        notifications: UserNotificationService = UserNotificationService()
    ) -> TimerStore {
        TimerStore(
            configuration: configuration,
            persistence: persistence,
            notifications: notifications
        )
    }

    // MARK: Timer lifecycle

    /// Starts an idle focus/break period. Calling start while already running
    /// or paused is intentionally idempotent.
    public func start() {
        guard state == .idle else { return }
        let now = clock.now
        ensureSessionForStart(at: now)
        beginRunning(phase: phase, at: now, duration: duration(for: phase), preservingSession: false)
    }

    /// Pauses without incrementing a focus or revealing a tile.
    public func pause() {
        guard state == .running else { return }
        let now = clock.now
        let left = max(0, (deadline ?? now).timeIntervalSince(now))
        var next = snapshot
        next.state = .paused
        next.remaining = left
        next.deadline = nil
        set(next, notifySchedule: false)
        updateActiveSession(status: .paused, at: now, remaining: left)
        notifications.cancel()
        persist()
    }

    /// Resumes a paused period from its persisted remaining duration.
    public func resume() {
        guard state == .paused else { return }
        guard snapshot.remaining > 0 else {
            // A zero duration is considered elapsed and follows the same
            // transition path as an expired deadline.
            var next = snapshot
            next.state = .running
            next.deadline = clock.now
            set(next, notifySchedule: false)
            updateActiveSession(status: .running, at: clock.now, remaining: 0)
            reconcile(at: clock.now)
            return
        }
        updateActiveSession(status: .running, at: clock.now, remaining: snapshot.remaining)
        beginRunning(phase: phase, at: clock.now, duration: snapshot.remaining, preservingSession: true)
    }

    /// Suspends a period without consuming its remaining time. This is distinct
    /// from a user pause in history, while retaining the existing paused UI.
    public func suspend() {
        guard state == .running || state == .paused else { return }
        let now = clock.now
        let left = state == .paused
            ? max(0, snapshot.remaining)
            : max(0, (deadline ?? now).timeIntervalSince(now))
        updateActiveSession(status: .suspended, at: now, remaining: left)
        if let cycleID = activeCycleID,
           let cycleIndex = cycles.firstIndex(where: { $0.id == cycleID }) {
            cycles[cycleIndex].status = .suspended
        }
        activeSessionID = nil
        activeCycleID = nil
        syncHistoryIntoSnapshot()
        var next = snapshot
        next.state = .idle
        next.phase = .focus
        next.startedAt = nil
        next.remaining = 0
        next.deadline = nil
        next.activeSessionID = nil
        next.activeCycleID = nil
        set(next, notifySchedule: false)
        notifications.cancel()
        persist()
    }

    /// Cancels the current period. Progress and completed artwork history are
    /// retained, while the next start begins a fresh focus period.
    public func cancel() {
        abandon()
    }

    /// Permanently abandons the current period and records it once.
    public func abandon() {
        let now = clock.now
        updateActiveSession(status: .abandoned, at: now, remaining: remaining(at: now))
        activeSessionID = nil
        abandonActiveCycle(at: now)
        syncHistoryIntoSnapshot()
        var next = snapshot
        next.state = .idle
        next.phase = .focus
        next.startedAt = nil
        next.deadline = nil
        next.remaining = 0
        set(next, notifySchedule: false)
        notifications.cancel()
        persist()
    }

    public func reset() { cancel() }

    /// Applies every elapsed period at the current injected time.
    public func reconcile() {
        reconcile(at: clock.now)
    }

    public func reconcile(now: Date) { reconcile(at: now) }

    public func startTimer() { start() }
    public func pauseTimer() { pause() }
    public func resumeTimer() { resume() }
    public func cancelTimer() { cancel() }
    public func suspendTimer() { suspend() }
    public func abandonTimer() { abandon() }

    @discardableResult
    public func resumeSession(id: UUID) -> Bool {
        guard state == .idle, activeSessionID == nil,
              let index = sessionHistory.firstIndex(where: { $0.id == id }),
              sessionHistory[index].status == .paused || sessionHistory[index].status == .suspended else {
            return false
        }
        let record = sessionHistory[index]
        let currentJourneyID = snapshot.artworkJourneyID
        let currentProgress = snapshot.artworkProgress
        var next = snapshot
        next.phase = record.phase
        next.state = .idle
        next.startedAt = record.startedAt
        next.deadline = nil
        next.remaining = max(0, record.remaining)
        next.artworkJourneyID = record.artworkJourneyID
        if record.phase == .focus, let artwork = record.artworkSnapshot {
            next.artwork = artwork
            let savedProgress = record.artworkProgressSnapshot
                ?? ArtworkProgress(artworkID: artwork.id, totalTiles: artwork.tileCount)
            if currentJourneyID == record.artworkJourneyID,
               let currentProgress,
               currentProgress.artworkID == artwork.id {
                let total = max(savedProgress.totalTiles, currentProgress.totalTiles)
                next.artworkProgress = ArtworkProgress(
                    artworkID: artwork.id,
                    totalTiles: total,
                    revealedTiles: savedProgress.revealedTiles.union(currentProgress.revealedTiles)
                )
            } else {
                next.artworkProgress = savedProgress
            }
        }
        next.activeSessionID = id
        next.activeCycleID = record.cycleID
        if let cycleIndex = next.cycles.firstIndex(where: { $0.id == record.cycleID }) {
            next.cycles[cycleIndex].status = .running
        }
        set(next, notifySchedule: false)
        activeSessionID = id
        activeCycleID = record.cycleID
        beginRunning(phase: record.phase, at: clock.now, duration: max(0, record.remaining), preservingSession: true)
        return true
    }

    @discardableResult
    public func abandonSession(id: UUID) -> Bool {
        if id == activeSessionID {
            abandon()
            return true
        }
        guard let index = sessionHistory.firstIndex(where: { $0.id == id }),
              !sessionHistory[index].status.isTerminal else { return false }
        let cycleID = sessionHistory[index].cycleID
        sessionHistory[index].transition(to: .abandoned, at: clock.now)
        if let cycleIndex = cycles.firstIndex(where: { $0.id == cycleID }),
           !cycles[cycleIndex].status.isTerminal {
            cycles[cycleIndex].status = .abandoned
            cycles[cycleIndex].completedAt = clock.now
        }
        syncHistoryIntoSnapshot()
        persist()
        return true
    }

    public func resumeHistorySession(id: UUID) -> Bool { resumeSession(id: id) }
    public func abandonHistorySession(id: UUID) -> Bool { abandonSession(id: id) }

    /// Applies every elapsed period up to `now`; exposed for deterministic
    /// tests and scene-activation handlers.
    public func reconcile(at now: Date) {
        guard state == .running else { return }

        var transitions = 0
        var changed = false
        while state == .running,
              let currentDeadline = deadline,
              currentDeadline <= now,
              transitions < 256 {
            transitions += 1
            finishCurrentPhase(at: currentDeadline)
            changed = true
        }

        // A malformed configuration with all durations set to zero must not
        // spin forever. Keep the state resumable at an immediate deadline.
        if transitions == 256, state == .running, deadline == now {
            var safe = snapshot
            safe.state = .paused
            safe.remaining = 0
            safe.deadline = nil
            set(safe, notifySchedule: false)
            notifications.cancel()
            changed = true
        }

        if changed { persist() }
    }

    /// Forces one transition, useful for notification handlers that already
    /// know a deadline has fired. It is still guarded by the running state,
    /// making repeated delivery idempotent.
    public func completeCurrentPhase(at date: Date? = nil) {
        guard state == .running else { return }
        let completionDate = date ?? deadline ?? clock.now
        guard let currentDeadline = deadline, completionDate >= currentDeadline else { return }
        finishCurrentPhase(at: currentDeadline)
        persist()
    }

    // MARK: Artwork

    public func setArtwork(_ artwork: Artwork?) {
        var next = snapshot
        next.artwork = artwork
        let restartsCompletedArtwork = artwork != nil
            && snapshot.artwork?.id == artwork?.id
            && snapshot.artworkProgress?.isComplete == true
        next.artworkProgress = artwork.map {
            if !restartsCompletedArtwork,
               let existing = snapshot.artworkProgress,
               existing.artworkID == $0.id {
                return existing
            }
            return ArtworkProgress(artworkID: $0.id, totalTiles: $0.tileCount)
        }
        if let artwork, snapshot.artwork?.id != artwork.id || restartsCompletedArtwork {
            next.artworkJourneyID = UUID()
        } else if artwork == nil {
            next.artworkJourneyID = nil
        } else if next.artworkJourneyID == nil {
            next.artworkJourneyID = UUID()
        }
        set(next, notifySchedule: false)
        persist()
    }

    public func clearArtwork() { setArtwork(nil) }

    /// Reveals one tile only while the current period is focus. Normal app
    /// flow calls this from a focus completion; keeping it public is useful for
    /// previews and makes the focus-only rule directly testable.
    @discardableResult
    public func revealNextTile() -> Int? {
        guard phase == .focus, let artwork = currentArtwork else { return nil }
        var next = snapshot
        var progress = next.artworkProgress
            ?? ArtworkProgress(artworkID: artwork.id, totalTiles: artwork.tileCount)
        guard progress.artworkID == artwork.id else { return nil }
        let tile = progress.revealNext(using: TileOrder.order(for: artwork))
        guard tile != nil else { return nil }
        next.artworkProgress = progress
        set(next, notifySchedule: false)
        persist()
        recordCompletedArtworkIfNeeded(at: clock.now)
        return tile
    }

    /// Idempotently records a completed artwork. Repeated calls cannot append
    /// duplicate records for the same artwork/progress state.
    @discardableResult
    public func recordCompletedArtworkIfNeeded(at date: Date? = nil) -> CompletedArtwork? {
        recordCompletedArtworkIfNeeded(at: date, partialRoutine: true)
    }

    @discardableResult
    public func recordCompletedArtworkIfNeeded(
        at date: Date? = nil,
        partialRoutine: Bool
    ) -> CompletedArtwork? {
        guard let artwork = currentArtwork,
              let progress = artworkProgress,
              progress.artworkID == artwork.id,
              progress.isComplete else { return nil }
        if let existingIndex = completedArtworks.firstIndex(where: {
            $0.artworkID == artwork.id
                && ($0.artworkJourneyID == snapshot.artworkJourneyID || $0.artworkJourneyID == nil)
                && $0.revealedTileCount >= progress.totalTiles
        }) {
            if !partialRoutine, completedArtworks[existingIndex].upgradeToCompleteRoutine() {
                var next = snapshot
                next.completedArtworks = completedArtworks
                set(next, notifySchedule: false)
                persist()
                return completedArtworks[existingIndex]
            }
            return nil
        }

        let contributionIDs = sessionHistory
            .filter { $0.artworkID == artwork.id && $0.artworkJourneyID == snapshot.artworkJourneyID }
            .map(\.id)
        let completedCycleCount = cycles.filter {
            $0.artworkJourneyID == snapshot.artworkJourneyID && $0.status == .completed
        }.count
        let expectedCycleCount = max(1, progress.totalTiles)
        let completed = CompletedArtwork(
            artworkID: artwork.id,
            completedAt: date ?? clock.now,
            focusSessions: completedFocusSessions,
            revealedTileCount: progress.revealedTileCount,
            partialRoutine: partialRoutine,
            completeRoutine: !partialRoutine,
            artworkJourneyID: snapshot.artworkJourneyID,
            contributingSessionIDs: contributionIDs,
            expectedCycles: expectedCycleCount,
            completedCycles: completedCycleCount,
            missingPauseSessionIDs: []
        )
        var next = snapshot
        next.completedArtworks.append(completed)
        set(next, notifySchedule: false)
        persist()
        return completed
    }

    /// Completes an already-revealed artwork routine after its final break.
    /// The same record is upgraded; no duplicate archive row is appended.
    @discardableResult
    public func upgradeCompletedArtworkIfPossible(at date: Date? = nil) -> CompletedArtwork? {
        upgradeCompletedArtworkIfPossible(
            at: date,
            artworkID: currentArtwork?.id,
            journeyID: snapshot.artworkJourneyID
        )
    }

    @discardableResult
    private func upgradeCompletedArtworkIfPossible(
        at date: Date?,
        artworkID: UUID?,
        journeyID: UUID?
    ) -> CompletedArtwork? {
        guard let artworkID,
              let index = completedArtworks.firstIndex(where: {
                  $0.artworkID == artworkID
                    && $0.artworkJourneyID == journeyID
                    && $0.partialRoutine
              }) else { return nil }
        var record = completedArtworks[index]
        record.contributingSessionIDs = sessionHistory
            .filter { $0.artworkID == artworkID && $0.artworkJourneyID == journeyID }
            .map(\.id)
        record.completedCycles = cycles.filter {
            $0.artworkJourneyID == journeyID && $0.status == .completed
        }.count
        record.missingPauseSessionIDs.removeAll { sessionID in
            sessionHistory.first(where: { $0.id == sessionID })?.status == .completed
        }
        guard record.completedCycles >= record.expectedCycles,
              record.missingPauseSessionIDs.isEmpty else {
            var next = snapshot
            next.completedArtworks[index] = record
            set(next, notifySchedule: false)
            persist()
            return nil
        }
        _ = record.upgradeToCompleteRoutine()
        var next = snapshot
        next.completedArtworks[index] = record
        set(next, notifySchedule: false)
        persist()
        return record
    }

    // MARK: Internal transition helpers

    private func ensureSessionForStart(at date: Date) {
        guard activeSessionID == nil else { return }
        let cycleID: UUID
        if phase == .focus || activeCycleID == nil {
            cycleID = UUID()
            var nextCycles = cycles
            nextCycles.append(
                TimerCycleRecord(
                    id: cycleID,
                    artworkID: currentArtwork?.id,
                    artworkJourneyID: snapshot.artworkJourneyID,
                    status: .running,
                    startedAt: date
                )
            )
            cycles = nextCycles
            activeCycleID = cycleID
        } else {
            cycleID = activeCycleID!
        }

        let cycle = cycles.first(where: { $0.id == cycleID })
        let sessionArtworkID = cycle?.artworkID ?? currentArtwork?.id
        let sessionJourneyID = cycle?.artworkJourneyID ?? snapshot.artworkJourneyID
        let session = TimerSessionRecord(
            cycleID: cycleID,
            phase: phase,
            status: .running,
            artworkID: sessionArtworkID,
            artworkJourneyID: sessionJourneyID,
            artworkSnapshot: currentArtwork,
            artworkProgressSnapshot: artworkProgress,
            startedAt: date,
            plannedDuration: duration(for: phase),
            remaining: duration(for: phase)
        )
        sessionHistory.append(session)
        activeSessionID = session.id
        if let cycleIndex = cycles.firstIndex(where: { $0.id == cycleID }) {
            if phase == .focus { cycles[cycleIndex].focusSessionID = session.id }
            else { cycles[cycleIndex].breakSessionID = session.id }
        }
        if phase.isBreak,
           let completedIndex = completedArtworks.firstIndex(where: {
               $0.artworkJourneyID == sessionJourneyID && $0.partialRoutine
           }),
           !completedArtworks[completedIndex].missingPauseSessionIDs.contains(session.id) {
            completedArtworks[completedIndex].missingPauseSessionIDs.append(session.id)
        }
        syncHistoryIntoSnapshot()
    }

    private func updateActiveSession(
        status: TimerSessionStatus,
        at date: Date,
        remaining: TimeInterval,
        elapsed: TimeInterval? = nil
    ) {
        guard let id = activeSessionID,
              let index = sessionHistory.firstIndex(where: { $0.id == id }) else { return }
        let planned = sessionHistory[index].plannedDuration
        let computedElapsed = elapsed ?? max(0, planned - remaining)
        sessionHistory[index].status = status
        sessionHistory[index].elapsed = max(0, computedElapsed)
        sessionHistory[index].remaining = max(0, remaining)
        sessionHistory[index].artworkSnapshot = currentArtwork
        sessionHistory[index].artworkProgressSnapshot = artworkProgress
        if sessionHistory[index].startedAt == nil { sessionHistory[index].startedAt = date }
        syncHistoryIntoSnapshot()
    }

    private func completeActiveSession(at date: Date) -> TimerSessionRecord? {
        guard let id = activeSessionID,
              let index = sessionHistory.firstIndex(where: { $0.id == id }) else { return nil }
        let left = state == .running ? max(0, (deadline ?? date).timeIntervalSince(date)) : snapshot.remaining
        let planned = sessionHistory[index].plannedDuration
        sessionHistory[index].transition(
            to: .completed,
            at: date,
            elapsed: max(planned, planned - left),
            remaining: 0
        )
        let completed = sessionHistory[index]
        activeSessionID = nil
        syncHistoryIntoSnapshot()
        return completed
    }

    private func completeActiveCycle(at date: Date) {
        guard let id = activeCycleID,
              let index = cycles.firstIndex(where: { $0.id == id }) else { return }
        cycles[index].status = .completed
        cycles[index].completedAt = date
        activeCycleID = nil
        syncHistoryIntoSnapshot()
    }

    private func abandonActiveCycle(at date: Date) {
        guard let id = activeCycleID,
              let index = cycles.firstIndex(where: { $0.id == id }),
              cycles[index].status.isActive else { return }
        cycles[index].status = .abandoned
        cycles[index].completedAt = date
        activeCycleID = nil
        syncHistoryIntoSnapshot()
    }

    private func syncHistoryIntoSnapshot() {
        var next = snapshot
        next.sessionHistory = sessionHistory
        next.cycles = cycles
        next.activeSessionID = activeSessionID
        next.activeCycleID = activeCycleID
        next.completedArtworks = completedArtworks
        snapshot = next
    }

    private func duration(for phase: TimerPhase) -> TimeInterval {
        Self.duration(for: phase, configuration: configuration)
    }

    private static func duration(for phase: TimerPhase, configuration: TimerConfiguration) -> TimeInterval {
        switch phase {
        case .focus: return configuration.focusDuration
        case .shortBreak: return configuration.shortBreakDuration
        case .longBreak: return configuration.longBreakDuration
        }
    }

    private func beginRunning(phase: TimerPhase, at start: Date, duration: TimeInterval) {
        beginRunning(phase: phase, at: start, duration: duration, preservingSession: false)
    }

    private func beginRunning(
        phase: TimerPhase,
        at start: Date,
        duration: TimeInterval,
        preservingSession: Bool
    ) {
        updateActiveSession(
            status: .running,
            at: start,
            remaining: max(0, duration),
            elapsed: preservingSession ? nil : 0
        )
        var next = snapshot
        next.phase = phase
        next.state = .running
        next.startedAt = preservingSession ? (snapshot.startedAt ?? start) : start
        next.remaining = max(0, duration)
        next.deadline = start.addingTimeInterval(max(0, duration))
        set(next, notifySchedule: false)
        if let deadline {
            notifications.schedule(deadline: deadline, phase: phase)
            notifications.notify(.scheduled(phase: phase, deadline: deadline))
        }
        persist()
    }

    private func finishCurrentPhase(at completionDate: Date) {
        let completedPhase = phase
        let completedSession = completeActiveSession(at: completionDate)
        if completedPhase == .focus {
            var next = snapshot
            next.completedFocusSessions += 1
            set(next, notifySchedule: false)
            _ = revealNextTile()
            // `revealNextTile` persists separately; use the current snapshot
            // again so the phase transition cannot discard its progress.
            if artworkProgress?.isComplete == true {
                _ = recordCompletedArtworkIfNeeded(at: completionDate, partialRoutine: true)
            }
        }

        notifications.notify(.completed(phase: completedPhase))
        notifications.cancel()
        let nextPhase: TimerPhase
        if completedPhase == .focus {
            nextPhase = completedFocusSessions % configuration.sessionsBeforeLongBreak == 0
                ? .longBreak
                : .shortBreak
        } else {
            nextPhase = .focus
        }
        if completedPhase.isBreak {
            completeActiveCycle(at: completionDate)
            upgradeCompletedArtworkIfPossible(
                at: completionDate,
                artworkID: completedSession?.artworkID,
                journeyID: completedSession?.artworkJourneyID
            )
        }
        // A finished period only selects the next phase. The user explicitly
        // starts that phase; this avoids silently consuming break time while
        // the app is in the background.
        var next = snapshot
        next.phase = nextPhase
        next.state = .idle
        next.startedAt = nil
        next.deadline = nil
        next.remaining = max(0, duration(for: nextPhase))
        set(next, notifySchedule: false)
    }

    private func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .idle: return 0
        case .paused: return max(0, snapshot.remaining)
        case .running:
            guard let deadline else { return max(0, snapshot.remaining) }
            return max(0, deadline.timeIntervalSince(now))
        }
    }

    private func set(_ next: TimerSnapshot, notifySchedule: Bool) {
        snapshot = next
        deadline = next.deadline
        phase = next.phase
        state = next.state
        currentArtwork = next.artwork
        artworkProgress = next.artworkProgress
        completedArtworks = next.completedArtworks
        sessionHistory = next.sessionHistory
        cycles = next.cycles
        activeSessionID = next.activeSessionID
        activeCycleID = next.activeCycleID
        if notifySchedule, let deadline {
            notifications.schedule(deadline: deadline, phase: phase)
        }
    }

    private func persist() {
        do {
            try persistence.save(snapshot)
            lastError = nil
        } catch {
            lastError = error
        }
    }
}
