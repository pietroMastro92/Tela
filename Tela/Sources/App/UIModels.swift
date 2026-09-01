import Foundation
import Observation
import SwiftUI

extension TimerPhase {
    var title: String {
        switch self {
        case .focus: "Concentrazione"
        case .shortBreak: "Pausa breve"
        case .longBreak: "Pausa lunga"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .focus: "Sessione di concentrazione"
        case .shortBreak: "Pausa breve"
        case .longBreak: "Pausa lunga"
        }
    }
}

extension TimerState {
    var title: String {
        switch self {
        case .idle: "Pronto"
        case .running: "In corso"
        case .paused: "In pausa"
        }
    }
}

extension Artwork {
    var subtitleText: String {
        [artist, year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var creditText: String { credit ?? source ?? "Imported artwork" }

    var fallbackSymbolName: String {
        switch assetName {
        case "MonetWaterLilies": "drop.fill"
        case "VanGoghBedroom": "bed.double.fill"
        case "HokusaiGreatWave": "water.waves"
        default: "photo.artframe"
        }
    }

}

enum TelaGallery {
    static func bundled(tileCount: Int) -> [Artwork] {
        ArtworkGallery.defaults.map { artwork in
            var normalized = artwork
            normalized.tileCount = min(max(tileCount, 4), 60)
            return normalized
        }
    }
}

protocol NotificationPreferenceService: Notifications, AnyObject {
    var soundEnabled: Bool { get set }
    var isEnabled: Bool { get set }
}

extension UserNotificationService: NotificationPreferenceService {}

/// UI-facing coordinator around the Core `TimerStore`.  It owns no timing
/// rules: lifecycle and persistence stay in Core, while this adapter provides
/// scene-friendly formatting, gallery tabs, preferences, and a lightweight
/// refresh pulse for deadline-based countdown rendering.
@MainActor
@Observable
final class TelaSessionStore {
    private enum Key {
        static let duration = "tela.ui.durationMinutes"
        static let shortBreak = "tela.ui.shortBreakMinutes"
        static let longBreak = "tela.ui.longBreakMinutes"
        static let sound = "tela.ui.soundEnabled"
        static let notifications = "tela.ui.notificationsEnabled"
        static let tileCount = "tela.ui.tileCount"
        static let imported = "tela.ui.importedArtworks"
    }

    private let defaults: UserDefaults
    private let notificationService: any NotificationPreferenceService
    private var pulseTask: Task<Void, Never>?
    private var knownCompletedIDs: Set<UUID>
    private var revision = 0

    private(set) var core: TimerStore
    private(set) var celebrationArtwork: Artwork?
    private(set) var durationMinutes: Int
    private(set) var shortBreakMinutes: Int
    private(set) var longBreakMinutes: Int
    private(set) var soundEnabled: Bool
    private(set) var notificationsEnabled: Bool
    private(set) var tileCount: Int
    private(set) var importedArtworks: [Artwork]
    private(set) var importErrorMessage: String?

    var phase: TimerPhase { observeCore(); return core.phase }
    var state: TimerState { observeCore(); return core.state }
    var isRunning: Bool { observeCore(); return core.state == .running }
    var isPaused: Bool { observeCore(); return core.state == .paused }
    var currentArtwork: Artwork {
        observeCore()
        return core.currentArtwork ?? TelaGallery.bundled(tileCount: tileCount)[0]
    }
    var artworkJourneyID: UUID? { observeCore(); return core.snapshot.artworkJourneyID }
    var revealedCount: Int { observeCore(); return core.artworkProgress?.revealedTileCount ?? 0 }
    /// The target is frozen when an artwork starts. The preference applies
    /// only when another artwork is selected.
    var activeTileCount: Int { observeCore(); return core.artworkProgress?.totalTiles ?? currentArtwork.tileCount }
    var completedArtworkSessions: Int { revealedCount }
    var artworkSessionGoal: Int { activeTileCount }
    var sessionsPerArtwork: Int {
        get { tileCount }
    }
    var completedFocusSessions: Int { observeCore(); return core.completedFocusSessions }
    var completedArtworkIDs: Set<UUID> { observeCore(); return Set(core.completedArtworks.map(\.artworkID)) }
    var sessionHistory: [TimerSessionRecord] { observeCore(); return core.sessionHistory }
    var archivedArtworkRecords: [CompletedArtwork] { observeCore(); return core.completedArtworks }

    var totalSeconds: TimeInterval {
        observeCore()
        return switch phase {
        case .focus: core.configuration.focusDuration
        case .shortBreak: core.configuration.shortBreakDuration
        case .longBreak: core.configuration.longBreakDuration
        }
    }

    var remaining: TimeInterval {
        observeCore()
        return core.state == .idle ? totalSeconds : core.remaining
    }

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return min(max((totalSeconds - remaining) / totalSeconds, 0), 1)
    }

    /// A continuous, non-destructive preview of the artwork reveal. The
    /// current focus contributes while it is running or paused, but Core only
    /// persists that contribution when the deadline is genuinely completed.
    var artworkRevealProgress: Double {
        Self.revealFraction(
            completedSessions: revealedCount,
            currentSessionProgress: progress,
            pendingSessionProgress: suspendedFocusProgress,
            goal: activeTileCount,
            previewsCurrentFocus: phase.isFocus && state != .idle
        )
    }

    private var suspendedFocusProgress: Double {
        observeCore()
        let artworkID = currentArtwork.id
        let journeyID = core.snapshot.artworkJourneyID
        return core.sessionHistory
            .filter {
                $0.phase == .focus && $0.status == .suspended &&
                    $0.artworkID == artworkID && $0.artworkJourneyID == journeyID
            }
            .reduce(0) { result, session in
                guard session.plannedDuration > 0 else { return result }
                return result + min(max(session.elapsed / session.plannedDuration, 0), 1)
            }
    }

    var artworkRevealPercentage: Int {
        Int((artworkRevealProgress * 100).rounded())
    }

    static func revealFraction(
        completedSessions: Int,
        currentSessionProgress: Double,
        pendingSessionProgress: Double = 0,
        goal: Int,
        previewsCurrentFocus: Bool
    ) -> Double {
        let safeGoal = max(goal, 1)
        let committed = Double(min(max(completedSessions, 0), safeGoal))
        let preview = previewsCurrentFocus
            ? min(max(currentSessionProgress, 0), 1)
            : 0
        let pending = max(0, pendingSessionProgress)
        return min(max((committed + pending + preview) / Double(safeGoal), 0), 1)
    }

    var formattedRemaining: String { Self.format(seconds: Int(ceil(remaining))) }

    var bundledArtworks: [Artwork] { TelaGallery.bundled(tileCount: tileCount) }
    var allArtworks: [Artwork] { bundledArtworks + importedArtworks }

    var completedArtworks: [Artwork] {
        (bundledArtworks + importedArtworks).filter { completedArtworkIDs.contains($0.id) }
    }

    init(
        defaults: UserDefaults = .standard,
        persistence: (any Persistence)? = nil,
        notificationService: (any NotificationPreferenceService)? = nil
    ) {
        self.defaults = defaults
        let uiTesting = ProcessInfo.processInfo.arguments.contains("--ui-testing")
        let savedDuration = defaults.integer(forKey: Key.duration)
        let savedShortBreak = defaults.integer(forKey: Key.shortBreak)
        let savedLongBreak = defaults.integer(forKey: Key.longBreak)
        let savedTileCount = defaults.integer(forKey: Key.tileCount)
        let duration = uiTesting ? 4 : (savedDuration == 0 ? 25 : savedDuration)
        let tiles = uiTesting ? 8 : (savedTileCount == 0 ? 12 : savedTileCount)
        let initialDuration = min(max(duration, 4), 60)
        let initialShortBreak = min(max(savedShortBreak == 0 ? 5 : savedShortBreak, 1), 30)
        let initialLongBreak = min(max(savedLongBreak == 0 ? 15 : savedLongBreak, 5), 60)
        let initialSound = defaults.object(forKey: Key.sound) as? Bool ?? true
        let initialNotifications = uiTesting
            ? false
            : (defaults.object(forKey: Key.notifications) as? Bool ?? true)
        let initialTileCount = min(max(tiles, 4), 60)
        durationMinutes = initialDuration
        shortBreakMinutes = initialShortBreak
        longBreakMinutes = initialLongBreak
        soundEnabled = initialSound
        notificationsEnabled = initialNotifications
        tileCount = initialTileCount

        let bundled = TelaGallery.bundled(tileCount: initialTileCount)
        let imported = Self.decodeImported(from: defaults, tileCount: initialTileCount)
        importedArtworks = imported
        let selected = Self.loadSelected(from: defaults, bundled: bundled, imported: imported) ?? bundled[0]
        let initialNotificationService = notificationService ?? UserNotificationService(
            soundEnabled: initialSound,
            isEnabled: initialNotifications
        )
        initialNotificationService.soundEnabled = initialSound
        initialNotificationService.isEnabled = initialNotifications
        self.notificationService = initialNotificationService
        let initialPersistence: any Persistence = persistence
            ?? (uiTesting ? InMemoryPersistence() : JSONPersistence())
        let initialCore = TimerStore(
            configuration: TimerConfiguration(
                focusDuration: TimeInterval(initialDuration * 60),
                shortBreakDuration: TimeInterval(initialShortBreak * 60),
                longBreakDuration: TimeInterval(initialLongBreak * 60)
            ),
            persistence: initialPersistence,
            notifications: initialNotificationService,
            artwork: selected
        )
        core = initialCore
        knownCompletedIDs = Set(initialCore.completedArtworks.map(\.artworkID))

        pulseTask = Task { @MainActor [weak self] in
            // A quarter-second cadence is useful only while a deadline is
            // active. Once idle or paused, the adapter sleeps longer and
            // emits no observation pulse; button actions still invalidate the
            // view synchronously. This keeps an idle app effectively dormant.
            while !Task.isCancelled {
                guard let self, !Task.isCancelled else { return }
                let cadence: UInt64 = self.core.state == .running
                    ? 250_000_000
                    : 2_000_000_000
                try? await Task.sleep(nanoseconds: cadence)
                guard !Task.isCancelled else { return }

                let wasRunning = self.core.state == .running
                self.core.reconcile()
                self.detectCompletion()

                // Running deadlines need a visual refresh. A transition out
                // of running also needs one final pulse; idle/paused states
                // otherwise remain quiet until an explicit user action.
                if wasRunning || self.core.state == .running {
                    self.revision &+= 1
                }
            }
        }
    }

    func start() {
        if core.currentArtwork == nil { core.setArtwork(currentArtwork) }
        core.start()
        revision &+= 1
    }

    func pause() { core.pause(); revision &+= 1 }
    func resume() { core.resume(); revision &+= 1 }
    func cancel() {
        core.suspend()
        celebrationArtwork = nil
        revision &+= 1
    }

    func abandonCurrentSession() {
        core.abandon()
        celebrationArtwork = nil
        revision &+= 1
    }

    func setFocusDuration(minutes: Int) {
        let value = min(max(minutes, 4), 60)
        guard value != durationMinutes else { return }
        durationMinutes = value
        defaults.set(value, forKey: Key.duration)
        core.updateConfiguration(focusDuration: TimeInterval(value * 60))
        revision &+= 1
    }

    func setShortBreakDuration(minutes: Int) {
        let value = min(max(minutes, 1), 30)
        guard value != shortBreakMinutes else { return }
        shortBreakMinutes = value
        defaults.set(value, forKey: Key.shortBreak)
        core.updateConfiguration(shortBreakDuration: TimeInterval(value * 60))
        revision &+= 1
    }

    func setLongBreakDuration(minutes: Int) {
        let value = min(max(minutes, 5), 60)
        guard value != longBreakMinutes else { return }
        longBreakMinutes = value
        defaults.set(value, forKey: Key.longBreak)
        core.updateConfiguration(longBreakDuration: TimeInterval(value * 60))
        revision &+= 1
    }

    func setSessionsPerArtwork(_ count: Int) {
        let value = min(max(count, 4), 60)
        guard value != tileCount else { return }
        tileCount = value
        defaults.set(value, forKey: Key.tileCount)
        revision &+= 1
    }

    func setSoundEnabled(_ enabled: Bool) {
        guard enabled != soundEnabled else { return }
        soundEnabled = enabled
        defaults.set(enabled, forKey: Key.sound)
        notificationService.soundEnabled = enabled
        revision &+= 1
    }

    func setNotificationsEnabled(_ enabled: Bool) {
        guard enabled != notificationsEnabled else { return }
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: Key.notifications)
        notificationService.isEnabled = enabled
        revision &+= 1
    }

    func dismissCelebration() { celebrationArtwork = nil }

    func artwork(for id: UUID?) -> Artwork? {
        guard let id else { return nil }
        return allArtworks.first(where: { $0.id == id })
    }

    func resumeSession(id: UUID) {
        if core.activeSessionID == id, core.state == .paused {
            core.resume()
        } else {
            core.resumeSession(id: id)
        }
        revision &+= 1
    }

    func abandonSession(id: UUID) {
        core.abandonSession(id: id)
        revision &+= 1
    }

    func selectArtwork(_ artwork: Artwork) {
        guard state == .idle else { return }
        var normalized = artwork
        normalized.tileCount = tileCount
        core.setArtwork(normalized)
        if let data = try? JSONEncoder().encode(normalized) {
            defaults.set(data, forKey: "tela.ui.selectedArtwork")
        }
        revision &+= 1
    }

    func selectNextArtwork() {
        let candidates = bundledArtworks + importedArtworks
        guard !candidates.isEmpty else { return }
        let current = candidates.firstIndex(where: { $0.id == currentArtwork.id }) ?? -1
        selectArtwork(candidates[(current + 1) % candidates.count])
    }

    func importArtwork(url: URL) {
        let artwork: Artwork
        do {
            artwork = try ImageImporter(defaultTileCount: tileCount).importArtwork(from: url)
        } catch {
            importErrorMessage = (error as? LocalizedError)?.errorDescription ?? "The image could not be imported."
            return
        }
        guard !importedArtworks.contains(where: {
            $0.title == artwork.title && $0.width == artwork.width && $0.height == artwork.height
        }) else { return }
        importErrorMessage = nil
        importedArtworks.append(artwork)
        if let data = try? JSONEncoder().encode(importedArtworks) {
            defaults.set(data, forKey: Key.imported)
        }
        selectArtwork(artwork)
    }

    static func format(seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        let remainder = max(0, seconds) % 60
        return String(format: "%02d:%02d", minutes, remainder)
    }

    private func detectCompletion() {
        let currentIDs = Set(core.completedArtworks.map(\.artworkID))
        guard let newID = currentIDs.subtracting(knownCompletedIDs).first else {
            knownCompletedIDs = currentIDs
            return
        }
        celebrationArtwork = (bundledArtworks + importedArtworks).first(where: { $0.id == newID })
        knownCompletedIDs = currentIDs
    }

    private func observeCore() {
        _ = revision
    }

    private static func decodeImported(from defaults: UserDefaults, tileCount: Int) -> [Artwork] {
        guard let data = defaults.data(forKey: Key.imported),
              let artworks = try? JSONDecoder().decode([Artwork].self, from: data) else { return [] }
        return artworks.map {
            var copy = $0
            copy.tileCount = tileCount
            return copy
        }
    }

    private static func loadSelected(from defaults: UserDefaults, bundled: [Artwork], imported: [Artwork]) -> Artwork? {
        guard let data = defaults.data(forKey: "tela.ui.selectedArtwork"),
              let saved = try? JSONDecoder().decode(Artwork.self, from: data) else { return nil }
        return (bundled + imported).first(where: { $0.id == saved.id }) ?? saved
    }
}
