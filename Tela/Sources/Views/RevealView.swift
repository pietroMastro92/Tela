import AppKit
import SwiftUI

/// Full-bleed artwork rendering. Reveal is deliberately continuous: a
/// deterministic, paint-like shape grows from one origin until the sharp
/// source image fills the canvas. The implementation has no grid or blur.
struct ArtworkCanvas: View {
    let artwork: Artwork
    let revealProgress: Double
    let reducedMotion: Bool
    let journeyID: UUID?
    let origin: UnitPoint?

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        artwork: Artwork,
        revealProgress: Double,
        reducedMotion: Bool,
        journeyID: UUID? = nil,
        origin: UnitPoint? = nil
    ) {
        self.artwork = artwork
        self.revealProgress = revealProgress
        self.reducedMotion = reducedMotion
        self.journeyID = journeyID
        self.origin = origin
    }

    private var reveal: Double {
        min(max(revealProgress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black

                ArtworkImage(artwork: artwork)
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .mask(
                        OrganicInkShape(
                            progress: reveal,
                            seed: artwork.seed,
                            journeyID: journeyID,
                            origin: origin
                        )
                        .fill(Color.white)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                    )
                    .allowsHitTesting(false)

                if reveal > 0, reveal < 1 {
                    OrganicInkShape(
                        progress: reveal,
                        seed: artwork.seed,
                        journeyID: journeyID,
                        origin: origin
                    )
                    .stroke(
                        Color.black.opacity(reduceTransparency ? 1 : 0.24),
                        lineWidth: reduceTransparency ? 1 : 0.75
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .animation(reducedMotion ? nil : .easeInOut(duration: 0.42), value: reveal)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rivelazione di \(artwork.title)")
        .accessibilityValue("\(Int((reveal * 100).rounded())) per cento visibile")
    }

}

struct ArtworkImage: View {
    let artwork: Artwork

    var body: some View {
        if let assetName = artwork.assetName {
            Image(assetName)
                .resizable()
        } else if let fileURL = artwork.fileURL, let image = ArtworkImageCache.shared.image(at: fileURL) {
            Image(nsImage: image)
                .resizable()
        } else {
            ZStack {
                LinearGradient(
                    colors: [Color.accentColor, Color.purple.opacity(0.72), Color.black],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: artwork.fallbackSymbolName)
                    .resizable()
                    .scaledToFit()
                    .padding(80)
                    .foregroundStyle(.white.opacity(0.72))
            }
        }
    }
}

private final class ArtworkImageCache: @unchecked Sendable {
    static let shared = ArtworkImageCache()
    private let images = NSCache<NSURL, NSImage>()

    func image(at url: URL) -> NSImage? {
        let key = url as NSURL
        if let cached = images.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: key)
        return image
    }
}
