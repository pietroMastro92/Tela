import XCTest
@testable import Tela

@MainActor
final class TimerHistoryTests: XCTestCase {
    private func artwork(_ name: String, tiles: Int = 2, seed: UInt64) -> Artwork {
        Artwork(name: name, tileCount: tiles, seed: seed)
    }

    func testPauseSuspendResumeKeepsOneStableSessionRecord() {
        let origin = Date(timeIntervalSince1970: 10_000)
        let clock = MutableClock(now: origin)
        let persistence = InMemoryPersistence()
        let store = TimerStore(
            configuration: TimerConfiguration(focusDuration: 10, shortBreakDuration: 5, longBreakDuration: 15),
            clock: clock,
            persistence: persistence,
            artwork: artwork("A", seed: 1)
        )

        store.start()
        guard let id = store.activeSessionID else { return XCTFail("missing active session") }
        XCTAssertEqual(store.sessionHistory.count, 1)
        XCTAssertEqual(store.sessionHistory[0].status, .running)

        clock.now = origin.addingTimeInterval(3)
        store.pause()
        XCTAssertEqual(store.activeSessionID, id)
        XCTAssertEqual(store.sessionHistory[0].status, .paused)
        XCTAssertEqual(store.sessionHistory[0].remaining, 7, accuracy: 0.001)

        store.suspend()
        XCTAssertEqual(store.sessionHistory[0].status, .suspended)
        XCTAssertEqual(store.sessionHistory[0].remaining, 7, accuracy: 0.001)
        XCTAssertEqual(store.state, .idle)
        XCTAssertNil(store.activeSessionID)

        clock.now = origin.addingTimeInterval(100)
        XCTAssertTrue(store.resumeSession(id: id))
        XCTAssertEqual(store.activeSessionID, id)
        XCTAssertEqual(store.sessionHistory.count, 1)
        XCTAssertEqual(store.sessionHistory[0].status, .running)
        XCTAssertEqual(store.deadline, clock.now.addingTimeInterval(7))
    }

    func testAbandonIsTerminalAndIdempotent() {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 11_000))
        let store = TimerStore(
            configuration: TimerConfiguration(focusDuration: 10),
            clock: clock,
            artwork: artwork("A", seed: 2)
        )
        store.start()
        guard let id = store.activeSessionID else { return XCTFail("missing active session") }
        store.abandon()
        store.abandon()
        XCTAssertNil(store.activeSessionID)
        XCTAssertEqual(store.sessionHistory.filter { $0.id == id }.count, 1)
        XCTAssertEqual(store.sessionHistory.first(where: { $0.id == id })?.status, .abandoned)
        XCTAssertEqual(store.completedFocusSessions, 0)
    }

    func testLateRoutineUpgradeUsesJourneyAfterArtworkSelectionChanges() {
        let origin = Date(timeIntervalSince1970: 12_000)
        let clock = MutableClock(now: origin)
        let first = artwork("First", tiles: 1, seed: 3)
        let second = artwork("Second", tiles: 1, seed: 4)
        let store = TimerStore(
            configuration: TimerConfiguration(focusDuration: 1, shortBreakDuration: 1, longBreakDuration: 3),
            clock: clock,
            artwork: first
        )

        store.start()
        clock.now = origin.addingTimeInterval(1)
        store.reconcile()
        XCTAssertEqual(store.phase, .shortBreak)
        XCTAssertEqual(store.completedArtworks.count, 1)
        XCTAssertTrue(store.completedArtworks[0].partialRoutine)
        let firstJourney = store.completedArtworks[0].artworkJourneyID

        // Selecting another artwork while the break is idle must not orphan
        // the first journey's pending break.
        store.setArtwork(second)
        store.start()
        clock.now = origin.addingTimeInterval(2)
        store.reconcile()

        let firstRecord = store.completedArtworks.first(where: { $0.artworkID == first.id })
        XCTAssertNotNil(firstRecord)
        XCTAssertEqual(firstRecord?.artworkJourneyID, firstJourney)
        XCTAssertFalse(firstRecord?.partialRoutine ?? true)
        XCTAssertTrue(firstRecord?.completeRoutine ?? false)
        XCTAssertEqual(store.completedArtworks.filter { $0.artworkID == first.id }.count, 1)
    }

    func testV1MigrationSynthesizesOnlyActiveSessionAndIsIdempotent() {
        let now = Date(timeIntervalSince1970: 13_000)
        let artwork = artwork("Legacy", seed: 5)
        var idle = TimerSnapshot(phase: .focus, state: .idle, artwork: artwork)
        idle.migrateSessionHistory(at: now)
        XCTAssertTrue(idle.sessionHistory.isEmpty)
        XCTAssertNil(idle.activeSessionID)

        var running = TimerSnapshot(
            phase: .focus,
            state: .running,
            startedAt: now.addingTimeInterval(-2),
            deadline: now.addingTimeInterval(8),
            remaining: 8,
            configuration: TimerConfiguration(focusDuration: 10),
            artwork: artwork
        )
        running.migrateSessionHistory(at: now)
        running.migrateSessionHistory(at: now)
        XCTAssertEqual(running.sessionHistory.count, 1)
        XCTAssertEqual(running.sessionHistory[0].status, .running)
        XCTAssertEqual(running.activeSessionID, running.sessionHistory[0].id)
    }

    func testRelaunchPreservesEveryDetachedSuspendedSession() throws {
        let first = TimerSessionRecord(status: .suspended, remaining: 4)
        let second = TimerSessionRecord(status: .suspended, remaining: 7)
        var snapshot = TimerSnapshot(sessionHistory: [first, second])

        snapshot.migrateSessionHistory(at: Date(timeIntervalSince1970: 13_500))

        XCTAssertNil(snapshot.activeSessionID)
        XCTAssertEqual(snapshot.sessionHistory.map(\.status), [.suspended, .suspended])
        XCTAssertEqual(snapshot.sessionHistory.map(\.remaining), [4, 7])
    }

    func testResumingOldFocusRestoresItsArtworkAndCreditsIt() {
        let origin = Date(timeIntervalSince1970: 13_600)
        let clock = MutableClock(now: origin)
        let first = artwork("First", tiles: 2, seed: 31)
        let second = artwork("Second", tiles: 2, seed: 32)
        let store = TimerStore(
            configuration: TimerConfiguration(focusDuration: 10, shortBreakDuration: 2),
            clock: clock,
            artwork: first
        )
        store.start()
        clock.now = origin.addingTimeInterval(4)
        store.suspend()
        let pendingID = try! XCTUnwrap(store.sessionHistory.first?.id)
        store.setArtwork(second)

        XCTAssertTrue(store.resumeSession(id: pendingID))
        XCTAssertEqual(store.currentArtwork?.id, first.id)
        clock.now = origin.addingTimeInterval(10)
        store.reconcile()

        XCTAssertEqual(store.artworkProgress?.artworkID, first.id)
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 1)
    }

    func testResumingOlderFocusDoesNotEraseNewerProgressOnSameJourney() {
        let origin = Date(timeIntervalSince1970: 13_650)
        let clock = MutableClock(now: origin)
        let art = artwork("Shared journey", tiles: 3, seed: 34)
        let store = TimerStore(
            configuration: TimerConfiguration(focusDuration: 10, shortBreakDuration: 2),
            clock: clock,
            artwork: art
        )

        store.start()
        clock.now = origin.addingTimeInterval(4)
        store.suspend()
        let olderFocusID = try! XCTUnwrap(store.sessionHistory.first?.id)

        store.start()
        clock.now = origin.addingTimeInterval(14)
        store.reconcile()
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 1)

        // The pending break is deliberately suspended so the older focus can
        // be resumed without changing the artwork journey.
        store.start()
        store.suspend()
        XCTAssertTrue(store.resumeSession(id: olderFocusID))
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 1)

        clock.now = origin.addingTimeInterval(20)
        store.reconcile()
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 2)
    }

    func testPartialArtworkWaitsForEveryMissingBreakBeforeUpgrade() {
        let origin = Date(timeIntervalSince1970: 13_700)
        let clock = MutableClock(now: origin)
        let art = artwork("Two cycles", tiles: 2, seed: 33)
        let store = TimerStore(
            configuration: TimerConfiguration(focusDuration: 1, shortBreakDuration: 1, longBreakDuration: 1),
            clock: clock,
            artwork: art
        )

        store.start()
        clock.now = origin.addingTimeInterval(1)
        store.reconcile()
        store.start()
        let firstBreakID = try! XCTUnwrap(store.activeSessionID)
        store.suspend()

        store.start()
        clock.now = origin.addingTimeInterval(2)
        store.reconcile()
        XCTAssertTrue(store.completedArtworks.first?.partialRoutine == true)
        store.start()
        clock.now = origin.addingTimeInterval(3)
        store.reconcile()

        XCTAssertTrue(store.completedArtworks.first?.partialRoutine == true)
        XCTAssertEqual(store.completedArtworks.first?.completedCycles, 1)

        XCTAssertTrue(store.resumeSession(id: firstBreakID))
        clock.now = origin.addingTimeInterval(4)
        store.reconcile()
        XCTAssertTrue(store.completedArtworks.first?.completeRoutine == true)
        XCTAssertEqual(store.completedArtworks.first?.completedCycles, 2)
    }

    func testJSONPersistenceMigratesEnvelopeV1ToV2() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelaHistoryMigration-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artwork = artwork("Legacy", seed: 6)
        let now = Date(timeIntervalSince1970: 14_000)
        let oldSnapshot = TimerSnapshot(
            phase: .focus,
            state: .paused,
            startedAt: now.addingTimeInterval(-4),
            remaining: 6,
            configuration: TimerConfiguration(focusDuration: 10),
            artwork: artwork
        )
        let v1 = JSONPersistence(directory: directory, version: 1)
        try v1.save(oldSnapshot)

        let v2 = JSONPersistence(directory: directory, version: 2)
        let migrated = try XCTUnwrap(v2.load())
        XCTAssertEqual(migrated.sessionHistory.count, 1)
        XCTAssertEqual(migrated.sessionHistory[0].status, .paused)

        let data = try Data(contentsOf: v2.fileURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 2)
    }
}
