import Foundation

/// Deterministic, platform-independent tile order.  A SplitMix64 stream is
/// used instead of `Hasher` or `SystemRandomNumberGenerator`, both of which
/// deliberately vary between processes.
public struct TileOrder: Equatable, Sendable {
    public let tileCount: Int
    public let seed: UInt64
    public let indices: [Int]

    public init(tileCount: Int, seed: UInt64) {
        self.tileCount = max(0, tileCount)
        self.seed = seed
        self.indices = Self.makeOrder(tileCount: max(0, tileCount), seed: seed)
    }

    public static func order(tileCount: Int, seed: UInt64) -> [Int] {
        makeOrder(tileCount: max(0, tileCount), seed: seed)
    }

    public static func order(for artwork: Artwork) -> [Int] {
        order(tileCount: artwork.tileCount, seed: artwork.seed)
    }

    public func nextUnrevealed(in revealed: Set<Int>) -> Int? {
        indices.first(where: { !revealed.contains($0) })
    }

    private static func makeOrder(tileCount: Int, seed: UInt64) -> [Int] {
        guard tileCount > 0 else { return [] }
        var result = Array(0..<tileCount)
        var random = SplitMix64(seed: seed)
        // Fisher-Yates yields one stable permutation for each (count, seed).
        if result.count > 1 {
            for index in stride(from: result.count - 1, through: 1, by: -1) {
                let swapIndex = Int(random.next() % UInt64(index + 1))
                if index != swapIndex {
                    result.swapAt(index, swapIndex)
                }
            }
        }
        return result
    }
}
public typealias DeterministicTileOrder = TileOrder

private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { self.state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
