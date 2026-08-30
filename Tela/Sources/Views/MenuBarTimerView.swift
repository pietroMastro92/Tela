import SwiftUI

struct MenuBarTimerView: View {
    @Environment(TelaSessionStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                ArtworkThumbnail(artwork: store.currentArtwork, cornerRadius: 9)
                    .frame(width: 46, height: 46)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.phase.title).font(.headline)
                    Text(store.state.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }

            Text(store.formattedRemaining)
                .font(.system(.largeTitle, design: .rounded, weight: .light))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("\(store.phase.accessibilityLabel), \(store.formattedRemaining) rimanenti")

            ProgressView(value: store.progress)
                .accessibilityLabel("Avanzamento della sessione")
                .accessibilityValue("\(Int(store.progress * 100)) per cento")

            HStack(spacing: 8) {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: primarySymbol).frame(maxWidth: .infinity)
                }
                .telaGlassButton(prominent: true)

                Button { store.cancel() } label: {
                    Label("Interrompi", systemImage: "pause.circle").labelStyle(.iconOnly)
                }
                .telaGlassButton()
                .disabled(store.state == .idle)
                .help("Sospendi la sessione")
            }

            Divider()

            HStack {
                Button("Apri Tela") { openWindow(id: "main") }
                    .keyboardShortcut("o", modifiers: [.command])
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .labelStyle(.iconOnly)
                    .help("Impostazioni")
            }
        }
        .padding(18)
        .frame(width: 300)
    }

    private var primaryTitle: String { store.isRunning ? "Pausa" : (store.isPaused ? "Riprendi" : "Inizia") }
    private var primarySymbol: String { store.isRunning ? "pause.fill" : "play.fill" }

    private func primaryAction() {
        if store.isRunning { store.pause() }
        else if store.isPaused { store.resume() }
        else { store.start() }
    }
}
