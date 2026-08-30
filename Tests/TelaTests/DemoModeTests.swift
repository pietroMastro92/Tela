#if TELA_DEMO
import XCTest
@testable import Tela

@MainActor
final class DemoModeTests: XCTestCase {
    func testDefaultTimelineIsDeterministicAndEphemeral() {
        let origin = Date(timeIntervalSince1970: 10_000)
        let store = DemoSessionStore(clock: MutableClock(now: origin), automaticallyTicks: false)

        XCTAssertEqual(store.schedule.map(\.phase), [.focus, .shortBreak, .focus, .shortBreak, .focus, .shortBreak, .focus, .longBreak])
        XCTAssertEqual(store.schedule.map(\.duration), [8, 3, 8, 3, 8, 3, 8, 5])
        XCTAssertEqual(store.totalDuration, 46)
        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.revealProgress, 0)
        XCTAssertFalse(store.isFinished)
    }

    func testAutoplayCompletesEveryFocusAndTheFinalBreak() {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 20_000))
        let store = DemoSessionStore(clock: clock, automaticallyTicks: false)
        store.play()

        for segment in store.schedule {
            clock.now = clock.now.addingTimeInterval(segment.duration)
            store.tick()
        }

        XCTAssertEqual(store.completedFocusSessions, 4)
        XCTAssertTrue(store.hasCompletedArtwork)
        XCTAssertEqual(store.revealProgress, 1)
        XCTAssertTrue(store.isFinished)
        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.remaining, 0)
    }

    func testPauseResumePreservesTheCurrentSegmentWithoutWallClockDrift() {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 30_000))
        let store = DemoSessionStore(clock: clock, automaticallyTicks: false)
        store.play()

        clock.now = clock.now.addingTimeInterval(3)
        store.pause()
        XCTAssertEqual(store.state, .paused)
        XCTAssertEqual(store.remaining, 5, accuracy: 0.001)
        XCTAssertEqual(store.revealProgress, 3.0 / 32.0, accuracy: 0.001)

        clock.now = clock.now.addingTimeInterval(60)
        store.tick()
        XCTAssertEqual(store.remaining, 5, accuracy: 0.001)

        store.play()
        XCTAssertEqual(store.state, .running)
        clock.now = clock.now.addingTimeInterval(5)
        store.tick()
        XCTAssertEqual(store.completedFocusSessions, 1)
        XCTAssertEqual(store.phase, .shortBreak)
    }

    func testStepCanDriveARepeatableGuidedWalkthroughAndReset() {
        let store = DemoSessionStore(
            clock: MutableClock(now: Date(timeIntervalSince1970: 40_000)),
            autoplay: false,
            automaticallyTicks: false
        )

        store.step()
        XCTAssertEqual(store.completedFocusSessions, 1)
        XCTAssertEqual(store.phase, .shortBreak)
        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.revealProgress, 0.25, accuracy: 0.001)

        store.step()
        XCTAssertEqual(store.phase, .focus)
        XCTAssertEqual(store.segmentIndex, 2)
        XCTAssertEqual(store.completedFocusSessions, 1)

        store.cleanRecording = true
        store.revealOriginSelection = .bottomTrailing
        store.reset()
        XCTAssertEqual(store.segmentIndex, 0)
        XCTAssertEqual(store.completedFocusSessions, 0)
        XCTAssertEqual(store.state, .idle)
        XCTAssertFalse(store.isFinished)
        XCTAssertTrue(store.cleanRecording)
        XCTAssertEqual(store.revealOriginSelection, .bottomTrailing)
        XCTAssertEqual(store.revealOrigin, .bottomTrailing)
    }

    func testExplicitClockTickCanCatchUpSeveralAutoplaySegments() {
        let origin = Date(timeIntervalSince1970: 50_000)
        let clock = MutableClock(now: origin)
        let store = DemoSessionStore(clock: clock, automaticallyTicks: false)
        store.play()

        clock.now = origin.addingTimeInterval(8 + 3 + 8 + 3)
        store.tick()

        XCTAssertEqual(store.completedFocusSessions, 2)
        XCTAssertEqual(store.segmentIndex, 4)
        XCTAssertEqual(store.phase, .focus)
        XCTAssertEqual(store.state, .running)
        XCTAssertEqual(store.remaining, 8, accuracy: 0.001)
    }
}
#endif
