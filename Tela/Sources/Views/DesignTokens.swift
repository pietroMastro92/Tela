import AppKit
import SwiftUI

enum TelaMetrics {
    static let windowCornerRadius: CGFloat = 28
    static let surfaceCornerRadius: CGFloat = 22
    static let controlCornerRadius: CGFloat = 14
    static let contentPadding: CGFloat = 28
}

struct TelaGlassGroup<Content: View>: View {
    private let spacing: CGFloat
    private let content: Content

    init(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content
            }
        } else {
            content
        }
    }
}

struct TelaGlassSurface<Content: View>: View {
    private let cornerRadius: CGFloat
    private let interactive: Bool
    private let content: Content

    init(
        cornerRadius: CGFloat = TelaMetrics.surfaceCornerRadius,
        interactive: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.interactive = interactive
        self.content = content()
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *) {
            if interactive {
                content
                    .glassEffect(
                        .regular.interactive(),
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            } else {
                content
                    .glassEffect(
                        .regular,
                        in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    )
            }
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.16), lineWidth: 0.75)
                }
        }
    }
}

/// Keeps the immersive controls legible without tinting or dimming the
/// artwork itself. The scrims are confined to the edges where controls live;
/// the center of the canvas remains a clean, sharp discovery surface.
struct ImmersiveEdgeScrims: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [.black.opacity(0.28), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 128)

            Spacer(minLength: 0)

            LinearGradient(
                colors: [.clear, .black.opacity(0.58)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 220)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TelaGlassButtonModifier: ViewModifier {
    let prominent: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

extension View {
    func telaGlassButton(prominent: Bool = false) -> some View {
        modifier(TelaGlassButtonModifier(prominent: prominent))
    }
}

struct ArtworkThumbnail: View {
    let artwork: Artwork
    var cornerRadius: CGFloat = 14

    var body: some View {
        ArtworkImage(artwork: artwork)
            .scaledToFill()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

struct ArtworkSymbol: View {
    let artwork: Artwork
    var size: CGFloat = 72

    var body: some View {
        ArtworkThumbnail(artwork: artwork, cornerRadius: size * 0.20)
            .frame(width: size, height: size)
            .accessibilityHidden(false)
            .accessibilityLabel("Anteprima di \(artwork.title)")
    }
}
