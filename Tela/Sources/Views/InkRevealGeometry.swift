import CoreGraphics
import SwiftUI

/// Geometry for one continuous drop of ink soaking through the canvas.
///
/// The contour is polar around a single origin, so it can never split into
/// islands. Its early radius is based on canvas area—not distance to the
/// rectangular edges—which keeps the first reveal compact and drop-like.
struct InkRevealGeometry {
    static let sampleCount = 192
    static let safeMargin = 0.12

    let progress: Double
    let seed: UInt64
    let journeyID: UUID?
    let origin: UnitPoint?

    init(
        progress: Double,
        seed: UInt64,
        journeyID: UUID? = nil,
        origin: UnitPoint? = nil
    ) {
        self.progress = progress
        self.seed = seed
        self.journeyID = journeyID
        self.origin = origin
    }

    var clampedProgress: Double { min(max(progress, 0), 1) }

    var resolvedSeed: UInt64 {
        guard let journeyID else { return Self.mix(seed ^ 0xD6E8FEB86659FD93) }
        var value = seed ^ 0xA0761D6478BD642F
        withUnsafeBytes(of: journeyID.uuid) { bytes in
            for byte in bytes {
                value = Self.mix(value ^ UInt64(byte))
            }
        }
        return value
    }

    func resolvedOrigin(in rect: CGRect) -> CGPoint {
        let unit = origin.map(Self.clampedUnitPoint) ?? Self.randomOrigin(seed: resolvedSeed)
        return CGPoint(
            x: rect.minX + rect.width * unit.x,
            y: rect.minY + rect.height * unit.y
        )
    }

    /// One smoothly varying radius per angle. Every radius uses the same
    /// monotonic base scale, and the restrained noise profile never changes
    /// with progress, preventing spikes or backwards-moving pockets.
    func radii(in rect: CGRect) -> [CGFloat] {
        guard !rect.isEmpty, clampedProgress > 0 else {
            return Array(repeating: 0, count: Self.sampleCount)
        }

        let p = clampedProgress
        let center = resolvedOrigin(in: rect)
        let canvasArea = max(rect.width * rect.height, 1)
        let areaRadius = sqrt(canvasArea * CGFloat(p) / .pi)
        let farthestCorner = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ].map { hypot($0.x - center.x, $0.y - center.y) }.max() ?? 0

        // Preserve area-like growth for most of the journey. Only near the
        // end does the radius accelerate enough to wet every corner.
        let transitionStart = 0.72
        let minimumNoiseFactor: CGFloat = 0.86
        let coverageRadius = farthestCorner / minimumNoiseFactor
        let baseRadius: CGFloat
        if p <= transitionStart {
            baseRadius = areaRadius
        } else {
            let startRadius = sqrt(canvasArea * CGFloat(transitionStart) / .pi)
            let t = Self.smoothstep((p - transitionStart) / (1 - transitionStart))
            baseRadius = startRadius + ((coverageRadius - startRadius) * CGFloat(t))
        }

        let rawNoise = (0 ..< Self.sampleCount).map { index in
            let angle = Self.angle(for: index)
            return Self.capillaryNoise(angle: angle, seed: resolvedSeed)
        }
        let minimum = rawNoise.min() ?? -1
        let maximum = rawNoise.max() ?? 1
        let span = max(maximum - minimum, 0.000_001)
        return rawNoise.map { value in
            // Normalize each deterministic contour to a guaranteed 19%
            // radial range. Different seeds keep different silhouettes, while
            // no artwork accidentally receives an almost perfect circle.
            let normalized = ((value - minimum) / span * 2) - 1
            return max(0, baseRadius * CGFloat(1 + normalized * 0.095))
        }
    }

    func boundaryPoints(in rect: CGRect) -> [CGPoint] {
        guard clampedProgress > 0, !rect.isEmpty else { return [] }
        let center = resolvedOrigin(in: rect)
        return radii(in: rect).enumerated().map { index, radius in
            let angle = Self.angle(for: index)
            return CGPoint(
                x: center.x + cos(angle) * radius,
                y: center.y + sin(angle) * radius
            )
        }
    }

    func path(in rect: CGRect) -> Path {
        guard !rect.isEmpty, clampedProgress > 0 else { return Path() }
        if clampedProgress >= 1 { return Path(rect) }
        let points = boundaryPoints(in: rect)
        guard points.count >= 3 else { return Path() }
        return Self.smoothClosedPath(points)
    }

    private static func angle(for index: Int) -> Double {
        (Double(index) / Double(sampleCount) * (2 * .pi)) - (.pi / 2)
    }

    private static func capillaryNoise(angle: Double, seed: UInt64) -> Double {
        let turn = (angle + .pi / 2) / (2 * .pi)

        // Circular value-noise avoids the visibly repeated petals produced by
        // a short sum of sine waves. Each octave is periodic only at the seam,
        // while its individual bumps have deterministic random heights.
        let broad = circularNoise(turn: turn, frequency: 3, seed: seed ^ 0x8EBC6AF09C88C6E3)
        let medium = circularNoise(turn: turn, frequency: 8, seed: seed ^ 0x589965CC75374CC3)
        let fine = circularNoise(turn: turn, frequency: 19, seed: seed ^ 0x1D8E4E27C47D124F)
        let fibres = circularNoise(turn: turn, frequency: 41, seed: seed ^ 0xDB4F0B9175AE2165)

        // Broad pooling carries most of the silhouette. The small, faster
        // octaves make the perimeter look absorbed by paper fibres rather than
        // geometrically drawn, while keeping every radius safely positive.
        return (broad * 0.070)
            + (medium * 0.041)
            + (fine * 0.024)
            + (fibres * 0.011)
    }

    private static func circularNoise(turn: Double, frequency: Int, seed: UInt64) -> Double {
        let wrapped = turn - floor(turn)
        let position = wrapped * Double(frequency)
        let lower = Int(floor(position))
        let fraction = position - Double(lower)
        let next = (lower + 1) % frequency
        let lhs = signedValue(mix(seed ^ UInt64(lower &* 0x45D9F3B)))
        let rhs = signedValue(mix(seed ^ UInt64(next &* 0x45D9F3B)))
        let eased = fraction * fraction * (3 - 2 * fraction)
        return lhs + ((rhs - lhs) * eased)
    }

    private static func signedValue(_ value: UInt64) -> Double {
        (unitValue(value) * 2) - 1
    }

    private static func smoothClosedPath(_ points: [CGPoint]) -> Path {
        guard let first = points.first else { return Path() }
        var path = Path()
        path.move(to: midpoint(points[points.count - 1], first))
        for index in points.indices {
            let current = points[index]
            let next = points[(index + 1) % points.count]
            path.addQuadCurve(to: midpoint(current, next), control: current)
        }
        path.closeSubpath()
        return path
    }

    private static func midpoint(_ lhs: CGPoint, _ rhs: CGPoint) -> CGPoint {
        CGPoint(x: (lhs.x + rhs.x) * 0.5, y: (lhs.y + rhs.y) * 0.5)
    }

    private static func clampedUnitPoint(_ point: UnitPoint) -> UnitPoint {
        UnitPoint(
            x: min(max(point.x, safeMargin), 1 - safeMargin),
            y: min(max(point.y, safeMargin), 1 - safeMargin)
        )
    }

    private static func randomOrigin(seed: UInt64) -> UnitPoint {
        let span = 1 - (safeMargin * 2)
        return UnitPoint(
            x: safeMargin + unitValue(mix(seed ^ 0xA0761D6478BD642F)) * span,
            y: safeMargin + unitValue(mix(seed ^ 0xE7037ED1A0B428DB)) * span
        )
    }

    private static func smoothstep(_ value: Double) -> Double {
        let t = min(max(value, 0), 1)
        return t * t * (3 - 2 * t)
    }

    private static func unitValue(_ value: UInt64) -> Double {
        Double(value >> 11) / 9_007_199_254_740_992
    }

    private static func mix(_ value: UInt64) -> UInt64 {
        var mixed = value &+ 0x9E3779B97F4A7C15
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58476D1CE4E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D049BB133111EB
        return mixed ^ (mixed >> 31)
    }
}

struct OrganicInkShape: Shape {
    var progress: Double
    let seed: UInt64
    let journeyID: UUID?
    let origin: UnitPoint?

    init(
        progress: Double,
        seed: UInt64,
        journeyID: UUID? = nil,
        origin: UnitPoint? = nil
    ) {
        self.progress = progress
        self.seed = seed
        self.journeyID = journeyID
        self.origin = origin
    }

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        InkRevealGeometry(
            progress: progress,
            seed: seed,
            journeyID: journeyID,
            origin: origin
        ).path(in: rect)
    }
}
