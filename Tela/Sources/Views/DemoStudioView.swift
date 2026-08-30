#if TELA_DEMO
import SwiftUI

/// A faithful, isolated preview of Tela's real immersive session. The regular
/// toolbar, timer, progress and controls are visible in the guided view;
/// Clean Recording reduces the overlay to a small timer/progress capsule.
@MainActor
public struct DemoStudioView: View {
    @State private var store: DemoSessionStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: DemoSessionStore = DemoSessionStore()) {
        _store = State(initialValue: store)
    }

    public var body: some View {
        ZStack {
            DemoArtworkCanvas(
                artwork: store.artwork,
                revealProgress: store.revealProgress,
                revealOrigin: store.revealOrigin,
                journeyID: store.revealJourneyID,
                reducedMotion: reduceMotion
            )

            ImmersiveEdgeScrims()

            VStack(spacing: 0) {
                if !store.cleanRecording {
                    DemoAppToolbar(store: store)
                }
                Spacer()
                VStack(spacing: 10) {
                    if !store.cleanRecording {
                        DemoDirectorPanel(store: store)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                        DemoAppControlDock(store: store)
                    } else {
                        DemoMinimalTimer(store: store)
                            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                }
            }
            .padding(.horizontal, TelaMetrics.contentPadding)
            .padding(.top, 18)
            .padding(.bottom, 24)

            if store.isFinished {
                CelebrationView(artwork: store.artwork) {
                    store.reset()
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .frame(minWidth: 820, minHeight: 520)
        .foregroundStyle(.white)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: store.cleanRecording)
        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: store.isFinished)
        .onExitCommand {
            if store.cleanRecording { store.cleanRecording = false }
            else { store.pause() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Studio Demo di Tela")
    }
}

/// Clean recordings retain just enough state for the viewer to understand the
/// walkthrough. The painting remains unobstructed and Esc restores the full
/// toolbar and director controls.
private struct DemoMinimalTimer: View {
    let store: DemoSessionStore

    var body: some View {
        TelaGlassSurface(cornerRadius: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.state == .paused ? "In pausa" : store.currentSegment.title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formattedRemaining)
                        .font(.system(.title3, design: .rounded, weight: .medium))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }

                ProgressView(value: store.revealProgress)
                    .frame(width: 130)
                    .tint(.white)

                Text("\(revealPercentage)%")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Timer Demo, \(store.currentSegment.title)")
            .accessibilityValue("\(formattedRemaining) rimanenti, \(revealPercentage) per cento rivelato")
        }
    }

    private var revealPercentage: Int {
        Int((store.revealProgress * 100).rounded())
    }

    private var formattedRemaining: String {
        let total = max(0, Int(ceil(store.remaining)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

private struct DemoAppToolbar: View {
    let store: DemoSessionStore

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid.fill")
                Text("Tela")
                    .fontWeight(.semibold)
                Text(store.artwork.title)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("DEMO")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.orange.opacity(0.88), in: Capsule())
                    .foregroundStyle(.black)
            }
            .font(.subheadline)

            Spacer()

            Button {
                store.cleanRecording.toggle()
            } label: {
                Image(systemName: store.cleanRecording ? "slider.horizontal.3" : "video.fill")
                    .frame(width: 20, height: 20)
            }
            .telaGlassButton()
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .help(store.cleanRecording ? "Mostra regia" : "Nascondi solo la regia")
            .accessibilityLabel(store.cleanRecording ? "Mostra regia Demo" : "Registrazione pulita")
        }
    }
}

/// Same visual hierarchy and labels as the real app's active-session dock.
private struct DemoAppControlDock: View {
    let store: DemoSessionStore

    var body: some View {
        TelaGlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                TelaGlassSurface(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.state == .paused ? "In pausa" : store.currentSegment.title)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(formattedRemaining)
                            .font(.system(.title, design: .rounded, weight: .medium))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                    }
                    .frame(minWidth: 92, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Timer Demo, \(store.currentSegment.title)")
                    .accessibilityValue("\(formattedRemaining) rimanenti")
                }

                TelaGlassSurface(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text("\(revealPercentage)%")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text("rivelato")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        ProgressView(value: store.revealProgress)
                            .frame(width: 170)
                            .tint(.white)
                            .accessibilityLabel("Rivelazione Demo")
                            .accessibilityValue("\(revealPercentage) per cento")
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                Button {
                    store.togglePlayPause()
                } label: {
                    Label(
                        playbackLabel,
                        systemImage: store.state == .running ? "pause.fill" : "play.fill"
                    )
                }
                .telaGlassButton(prominent: true)
                .keyboardShortcut(.space, modifiers: [])

                Button(role: .destructive) {
                    store.reset()
                } label: {
                    Label("Interrompi", systemImage: "pause.circle")
                }
                .telaGlassButton()
                .keyboardShortcut(.escape, modifiers: [])
                .help("Ferma e riavvolge soltanto la Demo")
            }
        }
    }

    private var revealPercentage: Int {
        Int((store.revealProgress * 100).rounded())
    }

    private var playbackLabel: String {
        switch store.state {
        case .running: "Pausa"
        case .paused: "Riprendi"
        case .idle: store.phase == .focus ? "Inizia concentrazione" : "Inizia pausa"
        }
    }

    private var formattedRemaining: String {
        let total = max(0, Int(ceil(store.remaining)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// Extra controls for preparing the promotional sequence. This is the only
/// surface removed by Clean Recording mode.
private struct DemoDirectorPanel: View {
    let store: DemoSessionStore

    var body: some View {
        TelaGlassSurface(cornerRadius: 16) {
            HStack(spacing: 12) {
                Label("Regia Demo", systemImage: "slider.horizontal.3")
                    .font(.caption.weight(.semibold))

                Button {
                    store.step()
                } label: {
                    Label("Fase successiva", systemImage: "forward.end.fill")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button {
                    store.reset()
                } label: {
                    Label("Ricomincia", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut("0", modifiers: [.command])

                Picker("Origine", selection: Binding(
                    get: { store.revealOriginSelection },
                    set: { store.revealOriginSelection = $0 }
                )) {
                    ForEach(DemoRevealOrigin.allCases) { origin in
                        Text(origin.title).tag(origin)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)

                Toggle("Autoplay", isOn: Binding(
                    get: { store.autoplay },
                    set: { store.autoplay = $0 }
                ))
                .toggleStyle(.checkbox)

                Button {
                    store.cleanRecording = true
                } label: {
                    Label("Nascondi regia", systemImage: "video.fill")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .accessibilityIdentifier("DemoDirectorPanel")
    }
}

private struct DemoArtworkCanvas: View {
    let artwork: Artwork
    let revealProgress: Double
    let revealOrigin: UnitPoint?
    let journeyID: UUID
    let reducedMotion: Bool

    var body: some View {
        ArtworkCanvas(
            artwork: artwork,
            revealProgress: min(max(revealProgress, 0), 1),
            reducedMotion: reducedMotion,
            journeyID: journeyID,
            origin: revealOrigin
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rivelazione demo di \(artwork.title)")
        .accessibilityValue("\(Int((revealProgress * 100).rounded())) per cento visibile")
    }
}
#endif
