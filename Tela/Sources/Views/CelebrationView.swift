import SwiftUI

struct CelebrationView: View {
    let artwork: Artwork
    let onDismiss: () -> Void

    @AccessibilityFocusState private var continueFocused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.38)
                .ignoresSafeArea()
                .onTapGesture { }

            TelaGlassSurface(cornerRadius: 28) {
                VStack(spacing: 20) {
                    ArtworkThumbnail(artwork: artwork, cornerRadius: 18)
                        .frame(width: 240, height: 180)
                        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
                        .accessibilityHidden(true)

                    Image(systemName: "checkmark.seal.fill")
                        .font(.largeTitle)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Opera completata")
                            .font(.title.bold())
                        Text("Hai rivelato \(artwork.title). L’opera è stata aggiunta al tuo archivio.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button("Continua", action: onDismiss)
                        .telaGlassButton(prominent: true)
                        .controlSize(.large)
                        .keyboardShortcut(.return, modifiers: [])
                        .keyboardShortcut(.escape, modifiers: [])
                        .accessibilityFocused($continueFocused)
                }
                .padding(30)
                .frame(maxWidth: 420)
            }
            .padding(30)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .onAppear { continueFocused = true }
    }
}
