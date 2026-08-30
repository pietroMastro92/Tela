import CoreGraphics
import SwiftUI
import XCTest
@testable import Tela

/// Regression coverage for the single-drop reveal.  These tests deliberately
/// exercise the pure geometry rather than rendering pixels, so they remain
/// deterministic on every supported macOS display size.
final class InkRevealGeometryTests: XCTestCase {
    private let rect = CGRect(x: 0, y: 0, width: 480, height: 300)

    private func journey(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            XCTFail("Invalid test UUID: \(value)")
            return UUID()
        }
        return id
    }

    private func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        return points.dropFirst().reduce(CGRect(origin: first, size: .zero)) { result, point in
            result.union(CGRect(origin: point, size: .zero))
        }
    }

    private func polygonArea(of points: [CGPoint]) -> Double {
        guard points.count >= 3 else { return 0 }
        var twiceArea = 0.0
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            twiceArea += (Double(current.x) * Double(next.y))
                - (Double(next.x) * Double(current.y))
        }
        return abs(twiceArea) * 0.5
    }

    private func mean(_ values: [CGFloat]) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / CGFloat(values.count)
    }

    private func radialRange(of values: [CGFloat]) -> CGFloat {
        guard let minimum = values.min(), let maximum = values.max() else { return 0 }
        return maximum - minimum
    }

    private func cyclicMatchFraction(
        _ values: [CGFloat],
        offset: Int,
        tolerance: CGFloat = 0.000001
    ) -> Double {
        guard !values.isEmpty else { return 1 }
        let distance = offset % values.count
        let matches = values.indices.reduce(into: 0) { count, index in
            let rotatedIndex = (index + distance) % values.count
            if abs(values[index] - values[rotatedIndex]) <= tolerance {
                count += 1
            }
        }
        return Double(matches) / Double(values.count)
    }

    private func cyclicMeanDifference(_ values: [CGFloat], offset: Int) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let distance = offset % values.count
        let total = values.indices.reduce(CGFloat.zero) { result, index in
            let rotatedIndex = (index + distance) % values.count
            return result + abs(values[index] - values[rotatedIndex])
        }
        return total / CGFloat(values.count)
    }

    private func pathSubpathCounts(_ path: Path) -> (moves: Int, closes: Int) {
        var moves = 0
        var closes = 0
        path.forEach { element in
            switch element {
            case .move:
                moves += 1
            case .closeSubpath:
                closes += 1
            default:
                break
            }
        }
        return (moves, closes)
    }

    func testProgressClampsAndHasEmptyAndFullEndpoints() {
        XCTAssertEqual(InkRevealGeometry(progress: -1, seed: 7).clampedProgress, 0)
        XCTAssertEqual(InkRevealGeometry(progress: 2, seed: 7).clampedProgress, 1)

        let emptyGeometry = InkRevealGeometry(progress: 0, seed: 7)
        XCTAssertTrue(emptyGeometry.radii(in: rect).allSatisfy { $0 == 0 })
        XCTAssertTrue(emptyGeometry.path(in: rect).isEmpty)

        let full = OrganicInkShape(progress: 1, seed: 7).path(in: rect)
        XCTAssertEqual(full.boundingRect, rect)
    }

    func testJourneyOriginAndShapeAreStableButNewJourneysDiffer() {
        let firstJourney = journey("00000000-0000-0000-0000-000000000001")
        let secondJourney = journey("00000000-0000-0000-0000-000000000002")
        let first = InkRevealGeometry(progress: 0.42, seed: 0x1234, journeyID: firstJourney)
        let second = InkRevealGeometry(progress: 0.42, seed: 0x1234, journeyID: firstJourney)
        let differentJourney = InkRevealGeometry(progress: 0.42, seed: 0x1234, journeyID: secondJourney)

        XCTAssertEqual(first.resolvedSeed, second.resolvedSeed)
        XCTAssertEqual(first.resolvedOrigin(in: rect), second.resolvedOrigin(in: rect))
        XCTAssertEqual(first.boundaryPoints(in: rect), second.boundaryPoints(in: rect))
        XCTAssertNotEqual(first.resolvedOrigin(in: rect), differentJourney.resolvedOrigin(in: rect))
        XCTAssertNotEqual(first.resolvedSeed, differentJourney.resolvedSeed)
    }

    func testOriginRespectsTwelvePercentSafeMarginIncludingExplicitOrigin() {
        let ids = (1...16).map { journey(String(format: "00000000-0000-0000-0000-%012d", $0)) }
        for id in ids {
            let origin = InkRevealGeometry(progress: 0, seed: 0xBEEF, journeyID: id)
                .resolvedOrigin(in: rect)
            let x = (origin.x - rect.minX) / rect.width
            let y = (origin.y - rect.minY) / rect.height
            XCTAssertGreaterThanOrEqual(x, InkRevealGeometry.safeMargin)
            XCTAssertLessThanOrEqual(x, 1 - InkRevealGeometry.safeMargin)
            XCTAssertGreaterThanOrEqual(y, InkRevealGeometry.safeMargin)
            XCTAssertLessThanOrEqual(y, 1 - InkRevealGeometry.safeMargin)
        }

        let clamped = InkRevealGeometry(
            progress: 0,
            seed: 1,
            origin: UnitPoint(x: 0, y: 1)
        ).resolvedOrigin(in: rect)
        XCTAssertEqual(clamped.x, rect.minX + rect.width * InkRevealGeometry.safeMargin, accuracy: 0.0001)
        XCTAssertEqual(clamped.y, rect.minY + rect.height * (1 - InkRevealGeometry.safeMargin), accuracy: 0.0001)
    }

    func testBoundaryAreaAndEveryRadiusGrowMonotonically() {
        let progressValues = [0.01, 0.05, 0.25, 0.50, 0.75, 0.99]
        var previousRadii = Array(repeating: CGFloat.zero, count: InkRevealGeometry.sampleCount)
        var previousArea = 0.0

        for progress in progressValues {
            let geometry = InkRevealGeometry(progress: progress, seed: 0xCAFE)
            let radii = geometry.radii(in: rect)
            XCTAssertEqual(radii.count, InkRevealGeometry.sampleCount)
            XCTAssertTrue(zip(previousRadii, radii).allSatisfy { $1 >= $0 })

            let area = polygonArea(of: geometry.boundaryPoints(in: rect))
            XCTAssertGreaterThan(area, previousArea)
            previousRadii = radii
            previousArea = area
        }
    }

    func testEarlyDropIsCompactAndNearlyCircularAcrossAspectRatios() {
        // Equal-area canvases make the area-based initial radius directly
        // comparable even when their width/height ratios differ.
        let firstRect = CGRect(x: 0, y: 0, width: 480, height: 300)
        let secondRect = CGRect(x: 0, y: 0, width: 600, height: 240)
        let first = InkRevealGeometry(
            progress: 0.01,
            seed: 91,
            origin: UnitPoint(x: 0.5, y: 0.5)
        )
        let second = InkRevealGeometry(
            progress: 0.01,
            seed: 91,
            origin: UnitPoint(x: 0.5, y: 0.5)
        )
        let firstBounds = boundingBox(of: first.boundaryPoints(in: firstRect))
        let secondBounds = boundingBox(of: second.boundaryPoints(in: secondRect))

        XCTAssertLessThan(firstBounds.width / firstBounds.height, 1.18)
        XCTAssertGreaterThan(firstBounds.width / firstBounds.height, 0.85)
        XCTAssertLessThan(secondBounds.width / secondBounds.height, 1.18)
        XCTAssertGreaterThan(secondBounds.width / secondBounds.height, 0.85)
        XCTAssertEqual(firstBounds.width, secondBounds.width, accuracy: 0.5)
        XCTAssertEqual(firstBounds.height, secondBounds.height, accuracy: 0.5)
        XCTAssertLessThan(firstBounds.width, min(firstRect.width, firstRect.height) * 0.25)
    }

    func testMidProgressContourHasMeaningfulIrregularityAcrossSeeds() {
        let seeds: [UInt64] = [
            0x1,
            0x1234,
            0xCAFE,
            0xFEED,
            0x0123_4567_89AB_CDEF
        ]

        for seed in seeds {
            let radii = InkRevealGeometry(
                progress: 0.50,
                seed: seed,
                origin: UnitPoint(x: 0.5, y: 0.5)
            ).radii(in: rect)
            let average = mean(radii)
            let relativeRange = radialRange(of: radii) / average

            XCTAssertGreaterThanOrEqual(
                relativeRange,
                0.12,
                "Seed " + String(seed, radix: 16) + " should produce an organic mid-progress edge"
            )
        }
    }

    func testCircularNoiseDoesNotRepeatAtCommonRotationalOffsets() {
        let offsets = [1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48]
        let seeds: [UInt64] = [0x1234, 0xCAFE, 0xFEED]

        for seed in seeds {
            let radii = InkRevealGeometry(
                progress: 0.50,
                seed: seed,
                origin: UnitPoint(x: 0.5, y: 0.5)
            ).radii(in: rect)
            let average = mean(radii)

            for offset in offsets {
                let exactMatchFraction = cyclicMatchFraction(radii, offset: offset)
                let normalizedDifference = cyclicMeanDifference(radii, offset: offset) / average

                // A rotationally copied contour would match at every sample;
                // even a dominant short period would leave most samples equal.
                XCTAssertLessThan(
                    exactMatchFraction,
                    0.05,
                    "Seed " + String(seed, radix: 16) + " repeats at offset " + String(offset)
                )
                XCTAssertGreaterThan(
                    normalizedDifference,
                    0.001,
                    "Seed " + String(seed, radix: 16) + " is too rotationally regular at offset " + String(offset)
                )
            }
        }
    }

    func testAdjacentRadiiStayBoundedAcrossSeveralSeeds() {
        let seeds: [UInt64] = [0x1, 0x1234, 0xCAFE, 0xFEED, 0x0123_4567_89AB_CDEF]

        for seed in seeds {
            let radii = InkRevealGeometry(
                progress: 0.50,
                seed: seed,
                origin: UnitPoint(x: 0.5, y: 0.5)
            ).radii(in: rect)
            let average = mean(radii)
            let adjacentDeltas = radii.indices.map { index in
                abs(radii[index] - radii[(index + 1) % radii.count])
            }

            XCTAssertLessThan(
                adjacentDeltas.max() ?? .greatestFiniteMagnitude,
                average * 0.08,
                "Seed " + String(seed, radix: 16) + " has a spike in adjacent samples"
            )
        }
    }

    func testNoiseIsDeterministicAndMonotonicAcrossSeveralSeeds() {
        let progressValues = [0.01, 0.05, 0.25, 0.50, 0.75, 0.99]
        let seeds: [UInt64] = [0x1, 0x1234, 0xCAFE, 0xFEED, 0x0123_4567_89AB_CDEF]

        for seed in seeds {
            var previous = Array(repeating: CGFloat.zero, count: InkRevealGeometry.sampleCount)
            for progress in progressValues {
                let geometry = InkRevealGeometry(
                    progress: progress,
                    seed: seed,
                    origin: UnitPoint(x: 0.5, y: 0.5)
                )
                let radii = geometry.radii(in: rect)
                let repeatRadii = geometry.radii(in: rect)

                XCTAssertEqual(radii, repeatRadii, "Seed " + String(seed, radix: 16) + " is not deterministic")
                XCTAssertEqual(radii.count, InkRevealGeometry.sampleCount)
                XCTAssertTrue(
                    zip(previous, radii).allSatisfy { $1 >= $0 },
                    "Seed " + String(seed, radix: 16) + " shrinks at progress " + String(progress)
                )
                previous = radii
            }
        }
    }

    func testAdjacentRadiiHaveNoSpikes() {
        let radii = InkRevealGeometry(progress: 0.50, seed: 0x12345678).radii(in: rect)
        let mean = radii.reduce(0, +) / CGFloat(radii.count)
        let adjacentDeltas = radii.indices.map { index in
            abs(radii[index] - radii[(index + 1) % radii.count])
        }
        XCTAssertLessThan(adjacentDeltas.max() ?? .greatestFiniteMagnitude, mean * 0.08)
    }

    func testRevealIsOneClosedConnectedPolarRegion() {
        for progress in [0.01, 0.25, 0.50, 0.75, 0.99] {
            let geometry = InkRevealGeometry(progress: progress, seed: 0xFEED)
            let points = geometry.boundaryPoints(in: rect)
            XCTAssertEqual(points.count, InkRevealGeometry.sampleCount)
            XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            XCTAssertTrue(geometry.radii(in: rect).allSatisfy { $0 > 0 })
            XCTAssertGreaterThan(polygonArea(of: points), 0)

            let subpaths = pathSubpathCounts(geometry.path(in: rect))
            XCTAssertEqual(subpaths.moves, 1)
            XCTAssertEqual(subpaths.closes, 1)
        }
    }

    @MainActor
    func testSelectingCompletedArtworkAgainCreatesANewDropJourney() throws {
        let art = Artwork(name: "Restart", tileCount: 1, seed: 0xCAFE)
        let store = TimerStore(artwork: art)
        let firstJourney = try XCTUnwrap(store.snapshot.artworkJourneyID)
        XCTAssertNotNil(store.revealNextTile())
        XCTAssertTrue(store.artworkProgress?.isComplete == true)

        store.setArtwork(art)

        let secondJourney = try XCTUnwrap(store.snapshot.artworkJourneyID)
        XCTAssertNotEqual(firstJourney, secondJourney)
        XCTAssertEqual(store.artworkProgress?.revealedTileCount, 0)
        let firstOrigin = InkRevealGeometry(progress: 0.1, seed: art.seed, journeyID: firstJourney)
            .resolvedOrigin(in: rect)
        let secondOrigin = InkRevealGeometry(progress: 0.1, seed: art.seed, journeyID: secondJourney)
            .resolvedOrigin(in: rect)
        XCTAssertNotEqual(firstOrigin, secondOrigin)
    }
}
