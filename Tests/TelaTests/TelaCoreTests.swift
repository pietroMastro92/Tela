import AppKit
import XCTest
@testable import Tela

@MainActor
final class ArtworkFadeTests: XCTestCase {
    func testRevealFractionIncludesOnlyActiveFocusPreview() {
        XCTAssertEqual(
            TelaSessionStore.revealFraction(
                completedSessions: 3,
                currentSessionProgress: 0.5,
                goal: 10,
                previewsCurrentFocus: true
            ),
            0.35,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            TelaSessionStore.revealFraction(
                completedSessions: 3,
                currentSessionProgress: 0.5,
                goal: 10,
                previewsCurrentFocus: false
            ),
            0.3,
            accuracy: 0.0001
        )
    }

    func testRevealFractionClampsAtBothEnds() {
        XCTAssertEqual(
            TelaSessionStore.revealFraction(
                completedSessions: -3,
                currentSessionProgress: -1,
                goal: 0,
                previewsCurrentFocus: true
            ),
            0
        )
        XCTAssertEqual(
            TelaSessionStore.revealFraction(
                completedSessions: 12,
                currentSessionProgress: 1,
                goal: 10,
                previewsCurrentFocus: true
            ),
            1
        )
    }
}

final class TileOrderTests: XCTestCase {
    func testOrderIsStableAndComplete() {
        let first = TileOrder.order(tileCount: 12, seed: 0x1234)
        XCTAssertEqual(first, TileOrder.order(tileCount: 12, seed: 0x1234))
        XCTAssertEqual(Set(first), Set(0..<12))
        XCTAssertEqual(first.count, 12)
    }

    func testProgressBoundariesAndDuplicateReveal() {
        let id = UUID()
        var progress = ArtworkProgress(artworkID: id, totalTiles: 2)
        XCTAssertEqual(progress.revealedTileCount, 0)
        XCTAssertTrue(progress.reveal(tile: 0))
        XCTAssertFalse(progress.reveal(tile: 0))
        XCTAssertFalse(progress.reveal(tile: 2))
        XCTAssertFalse(progress.isComplete)
        XCTAssertTrue(progress.reveal(tile: 1))
        XCTAssertTrue(progress.isComplete)
        XCTAssertNil(progress.revealNext(using: [1, 0]))
    }
}

final class BundledArtworkCatalogTests: XCTestCase {
    func testCuratedShelvesAreCompleteAndStable() {
        let catalog = ArtworkGallery.defaults
        XCTAssertEqual(catalog.count, 54)
        XCTAssertEqual(catalog.filter { $0.collections?.contains("Klimt") == true }.count, 16)
        XCTAssertEqual(catalog.filter { $0.collections?.contains("Gli occhi di Monna Lisa") == true }.count, 36)
        XCTAssertEqual(Set(catalog.map(\.id)).count, catalog.count)
        XCTAssertEqual(Set(catalog.compactMap(\.assetName)).count, catalog.count)
    }

    func testEveryCuratedArtworkHasAResolvableImage() {
        let missing = ArtworkGallery.defaults.compactMap { artwork -> String? in
            guard let assetName = artwork.assetName else { return artwork.title }
            return NSImage(named: assetName) == nil ? assetName : nil
        }
        XCTAssertTrue(missing.isEmpty, "Missing bundled images: \(missing.joined(separator: ", "))")
    }
}

@MainActor
final class TimerStoreTests: XCTestCase {
    func testFocusOnlyProgressAndLongBreakAfterConfiguredCount() {
        let origin = Date(timeIntervalSince1970: 1_000)
        let clock = MutableClock(now: origin)
        let config = TimerConfiguration(focusDuration: 10, shortBreakDuration: 5, longBreakDuration: 20, sessionsBeforeLongBreak: 2)
        let artwork = Artwork(name: "Test", tileCount: 4, seed: 7)
        let store = TimerStore(configuration: config, clock: clock, artwork: artwork)

        store.start()
        clock.now = origin.addingTimeInterval(10)
        store.reconcile()
        XCTAssertEqual(store.completedFocusSessions, 1)
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 1)
        XCTAssertEqual(store.phase, .shortBreak)
        XCTAssertEqual(store.state, .idle)

        // A break never increments or reveals.
        store.start()
        clock.now = origin.addingTimeInterval(15)
        store.reconcile()
        XCTAssertEqual(store.completedFocusSessions, 1)
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 1)
        XCTAssertEqual(store.phase, .focus)

        store.start()
        clock.now = origin.addingTimeInterval(25)
        store.reconcile()
        XCTAssertEqual(store.completedFocusSessions, 2)
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 2)
        XCTAssertEqual(store.phase, .longBreak)
        XCTAssertEqual(store.state, .idle)
    }

    func testExpiredDeadlineIsIdempotent() {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 2_000))
        let config = TimerConfiguration(focusDuration: 1, shortBreakDuration: 1, longBreakDuration: 1)
        let store = TimerStore(configuration: config, clock: clock)
        store.start()
        clock.now = clock.now.addingTimeInterval(1)
        store.reconcile()
        store.reconcile()
        XCTAssertEqual(store.completedFocusSessions, 1)
    }

    func testConfigurationUpdateDoesNotChangeActiveDeadline() {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 3_000))
        let store = TimerStore(configuration: TimerConfiguration(focusDuration: 30), clock: clock)
        store.start()
        let deadline = store.deadline
        store.updateConfiguration(focusDuration: 5)
        XCTAssertEqual(store.deadline, deadline)
        XCTAssertEqual(store.configuration.focusDuration, 5)
    }

    func testPauseResumePreservesRemainingAndIsIdempotent() {
        let origin = Date(timeIntervalSince1970: 4_000)
        let clock = MutableClock(now: origin)
        let store = TimerStore(configuration: TimerConfiguration(focusDuration: 30), clock: clock)
        store.start()
        store.start()
        clock.now = origin.addingTimeInterval(7)
        store.pause()
        store.pause()
        XCTAssertEqual(store.state, .paused)
        XCTAssertEqual(store.remaining, 23, accuracy: 0.001)

        clock.now = origin.addingTimeInterval(100)
        store.reconcile()
        XCTAssertEqual(store.completedFocusSessions, 0)
        store.resume()
        store.resume()
        XCTAssertEqual(store.deadline, clock.now.addingTimeInterval(23))
    }

    func testCancelNeverCompletesOrReveals() {
        let clock = MutableClock(now: Date(timeIntervalSince1970: 5_000))
        let artwork = Artwork(name: "Test", tileCount: 4, seed: 9)
        let store = TimerStore(configuration: TimerConfiguration(focusDuration: 10), clock: clock, artwork: artwork)
        store.start()
        clock.now = clock.now.addingTimeInterval(5)
        store.cancel()
        store.cancel()
        clock.now = clock.now.addingTimeInterval(100)
        store.reconcile()
        XCTAssertEqual(store.state, .idle)
        XCTAssertEqual(store.completedFocusSessions, 0)
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 0)
    }

    func testExpiredPersistedFocusCompletesExactlyOnceOnRestore() throws {
        let now = Date(timeIntervalSince1970: 6_000)
        let artwork = Artwork(name: "Restore", tileCount: 4, seed: 11)
        let snapshot = TimerSnapshot(
            phase: .focus,
            state: .running,
            startedAt: now.addingTimeInterval(-20),
            deadline: now.addingTimeInterval(-10),
            remaining: 10,
            configuration: TimerConfiguration(focusDuration: 10),
            artwork: artwork,
            artworkProgress: ArtworkProgress(artworkID: artwork.id, totalTiles: 4)
        )
        let persistence = InMemoryPersistence(snapshot: snapshot)
        let store = TimerStore(clock: MutableClock(now: now), persistence: persistence)
        XCTAssertEqual(store.completedFocusSessions, 1)
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 1)
        XCTAssertEqual(store.state, .idle)

        let restoredAgain = TimerStore(clock: MutableClock(now: now), persistence: persistence)
        XCTAssertEqual(restoredAgain.completedFocusSessions, 1)
        XCTAssertEqual(restoredAgain.artworkProgress?.revealedTileCount, 1)
    }

    func testCompletedArtworkIsArchivedOnlyOnce() {
        let origin = Date(timeIntervalSince1970: 7_000)
        let clock = MutableClock(now: origin)
        let artwork = Artwork(name: "Tiny", tileCount: 1, seed: 13)
        let store = TimerStore(configuration: TimerConfiguration(focusDuration: 1), clock: clock, artwork: artwork)
        store.start()
        clock.now = origin.addingTimeInterval(1)
        store.reconcile()
        store.reconcile()
        _ = store.recordCompletedArtworkIfNeeded()
        XCTAssertEqual(store.completedArtworks.count, 1)
        XCTAssertEqual(store.completedArtworks.first?.artworkID, artwork.id)
    }
}

final class JSONPersistenceTests: XCTestCase {
    func testRoundTripAndCorruptQuarantine() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelaTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = JSONPersistence(directory: directory)
        let snapshot = TimerSnapshot(phase: .shortBreak, state: .idle, completedFocusSessions: 3)
        try persistence.save(snapshot)
        XCTAssertEqual(try persistence.load(), snapshot)

        try Data("not-json".utf8).write(to: persistence.fileURL)
        XCTAssertNil(try persistence.load())
        XCTAssertNotNil(persistence.lastQuarantinedURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: persistence.lastQuarantinedURL?.path ?? ""))
    }

    func testMissingFileIsSafeAndUnsupportedVersionIsQuarantined() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelaSchemaTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = JSONPersistence(directory: directory, version: 1)
        XCTAssertNil(try persistence.load())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{\"version\":99,\"snapshot\":{}}".utf8).write(to: persistence.fileURL)
        XCTAssertThrowsError(try persistence.load()) { error in
            XCTAssertEqual(error as? JSONPersistenceError, .unsupportedVersion(99))
        }
        XCTAssertNotNil(persistence.lastQuarantinedURL)
    }
}

final class ImageImporterTests: XCTestCase {
    func testPNGIsCopiedAndNormalizedInsideDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TelaImageTests-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source.png")
        let destination = root.appendingPathComponent("Artwork", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let image = NSImage(size: NSSize(width: 20, height: 10))
        image.lockFocus()
        NSColor.systemBlue.setFill()
        NSRect(x: 0, y: 0, width: 20, height: 10).fill()
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return XCTFail("Unable to make test PNG")
        }
        try png.write(to: source)

        let artwork = try ImageImporter(maxDimension: 4096).importArtwork(
            from: source,
            destinationDirectory: destination
        )
        XCTAssertNotEqual(artwork.fileURL, source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artwork.fileURL?.path ?? ""))
        XCTAssertLessThanOrEqual(max(artwork.width, artwork.height), 4096)
    }

    func testUnreadableAndRemoteFilesAreRejected() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try ImageImporter().metadata(for: missing)) { error in
            XCTAssertEqual(error as? ImageImportError, .fileMissing)
        }
        XCTAssertThrowsError(try ImageImporter().metadata(for: URL(string: "https://example.com/a.png")!)) { error in
            XCTAssertEqual(error as? ImageImportError, .notLocalFile)
        }
    }
}
