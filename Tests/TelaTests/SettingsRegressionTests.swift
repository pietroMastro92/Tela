import XCTest
@testable import Tela

@MainActor
final class SettingsRegressionTests: XCTestCase {
    func testDurationSettersClampWithoutReentrantMutation() {
        let defaults = isolatedDefaults()
        let store = makeStore(defaults: defaults)

        store.setFocusDuration(minutes: 100)
        store.setShortBreakDuration(minutes: -10)
        store.setLongBreakDuration(minutes: 1)
        store.setSessionsPerArtwork(100)

        XCTAssertEqual(store.durationMinutes, 60)
        XCTAssertEqual(store.shortBreakMinutes, 1)
        XCTAssertEqual(store.longBreakMinutes, 5)
        XCTAssertEqual(store.sessionsPerArtwork, 60)
        XCTAssertEqual(defaults.integer(forKey: "tela.ui.durationMinutes"), 60)
    }

    func testChangingPreferencesDoesNotMoveActiveDeadline() {
        let defaults = isolatedDefaults()
        let store = makeStore(defaults: defaults)
        store.start()
        let deadline = store.core.deadline

        store.setFocusDuration(minutes: 60)
        store.setShortBreakDuration(minutes: 10)

        XCTAssertEqual(store.core.deadline, deadline)
        XCTAssertEqual(store.core.configuration.focusDuration, 60 * 60)
        XCTAssertEqual(store.core.configuration.shortBreakDuration, 10 * 60)
    }

    func testSelectingArtworkUpdatesCurrentSelection() {
        let defaults = isolatedDefaults()
        let store = makeStore(defaults: defaults)
        let candidate = store.bundledArtworks[1]

        store.selectArtwork(candidate)

        XCTAssertEqual(store.currentArtwork.id, candidate.id)
        XCTAssertNotNil(defaults.data(forKey: "tela.ui.selectedArtwork"))
    }

    func testSuspendedFocusPreviewRemainsVisibleUntilAbandoned() {
        let defaults = isolatedDefaults()
        let store = makeStore(defaults: defaults)
        store.start()
        store.core.pause()
        let preview = store.artworkRevealProgress
        store.cancel()

        XCTAssertEqual(store.state, .idle)
        XCTAssertGreaterThanOrEqual(store.artworkRevealProgress, preview)
        guard let suspended = store.sessionHistory.first(where: { $0.status == .suspended }) else {
            return XCTFail("Expected suspended session")
        }
        store.abandonSession(id: suspended.id)
        XCTAssertEqual(store.artworkRevealProgress, 0)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "TelaTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func makeStore(defaults: UserDefaults) -> TelaSessionStore {
        TelaSessionStore(
            defaults: defaults,
            persistence: InMemoryPersistence(),
            notificationService: TestNotificationPreferences()
        )
    }
}

private final class TestNotificationPreferences: NotificationPreferenceService, @unchecked Sendable {
    var soundEnabled = false
    var isEnabled = false

    func schedule(deadline: Date, phase: TimerPhase) {}
    func cancel() {}
    func notify(_ event: TimerNotification) {}
}
