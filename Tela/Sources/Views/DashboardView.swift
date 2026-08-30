import SwiftUI

private enum DashboardSheet: String, Identifiable {
    case gallery

    var id: String { rawValue }
}

struct DashboardView: View {
    @Environment(TelaSessionStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var presentedSheet: DashboardSheet?

    var body: some View {
        ZStack {
            dashboard
                .allowsHitTesting(store.celebrationArtwork == nil)
                .accessibilityHidden(store.celebrationArtwork != nil)

            if let artwork = store.celebrationArtwork {
                CelebrationView(artwork: artwork) {
                    store.dismissCelebration()
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.97).combined(with: .opacity))
                .zIndex(10)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.45), value: store.state == .idle)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: store.celebrationArtwork != nil)
        .sheet(item: $presentedSheet) { destination in
            switch destination {
            case .gallery:
                GalleryView()
                    .environment(store)
                    .frame(minWidth: 860, minHeight: 620)
            }
        }
    }

    @ViewBuilder
    private var dashboard: some View {
        if store.state == .idle {
            RestingDashboard {
                presentedSheet = .gallery
            }
            .transition(.opacity)
        } else {
            ImmersiveSession {
                presentedSheet = .gallery
            }
            .transition(.opacity)
        }
    }
}

private struct RestingDashboard: View {
    @Environment(TelaSessionStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let showGallery: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            HStack(spacing: 34) {
                RestingArtworkPanel(
                    artwork: store.currentArtwork,
                    revealProgress: store.artworkRevealProgress,
                    reducedMotion: reduceMotion
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                RestingTimerPanel()
                    .frame(width: 350)
            }
            .padding(.horizontal, TelaMetrics.contentPadding)
            .padding(.top, 78)
            .padding(.bottom, TelaMetrics.contentPadding)

            DashboardToolbar(showGallery: showGallery, usesLightForeground: false)
                .padding(.top, 18)
                .padding(.horizontal, TelaMetrics.contentPadding)
        }
    }
}

private struct RestingArtworkPanel: View {
    @Environment(TelaSessionStore.self) private var store
    let artwork: Artwork
    let revealProgress: Double
    let reducedMotion: Bool

    var body: some View {
        ArtworkCanvas(
            artwork: artwork,
            revealProgress: revealProgress,
            reducedMotion: reducedMotion,
            journeyID: store.artworkJourneyID
        )
        .overlay(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomLeading) {
            VStack(alignment: .leading, spacing: 4) {
                Text(artwork.title)
                    .font(.title2.weight(.semibold))
                    .lineLimit(2)
                if !artwork.subtitleText.isEmpty {
                    Text(artwork.subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .foregroundStyle(.white)
            .padding(24)
            .accessibilityElement(children: .combine)
        }
        .clipShape(RoundedRectangle(cornerRadius: TelaMetrics.windowCornerRadius, style: .continuous))
        .shadow(color: .black.opacity(0.16), radius: 32, y: 16)
    }
}

private struct RestingTimerPanel: View {
    @Environment(TelaSessionStore.self) private var store

    @ScaledMetric(relativeTo: .largeTitle) private var countdownSize: CGFloat = 72

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(store.phase.title, systemImage: phaseSymbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 24)

            Text(store.formattedRemaining)
                .font(.system(size: countdownSize, weight: .thin, design: .rounded))
                .tracking(-2)
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel("\(store.phase.accessibilityLabel), \(store.formattedRemaining)")

            Text(prompt)
                .font(.title3)
                .foregroundStyle(.secondary)
                .padding(.top, 6)

            Button {
                store.start()
            } label: {
                Label(startLabel, systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .telaGlassButton(prominent: true)
            .controlSize(.large)
            .keyboardShortcut(.return, modifiers: [])
            .padding(.top, 28)
            .accessibilityHint("Avvia il timer e mostra il quadro a tutto schermo")

            Spacer(minLength: 28)

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Opera in corso")
                    Spacer()
                    Text("\(store.artworkRevealPercentage)%")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ProgressView(value: store.artworkRevealProgress)
                    .accessibilityLabel("Rivelazione dell'opera")
                    .accessibilityValue("\(store.artworkRevealPercentage) per cento")

                Text("\(store.completedArtworkSessions) di \(store.artworkSessionGoal) sessioni completate")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 18)
        }
        .padding(.vertical, 18)
        .frame(maxHeight: 560)
    }

    private var phaseSymbol: String {
        store.phase == .focus ? "timer" : "cup.and.saucer"
    }

    private var prompt: String {
        store.phase == .focus ? "Una cosa alla volta." : "Prenditi una pausa."
    }

    private var startLabel: String {
        store.phase == .focus ? "Inizia concentrazione" : "Inizia la pausa"
    }
}

private struct ImmersiveSession: View {
    @Environment(TelaSessionStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let showGallery: () -> Void

    var body: some View {
        ZStack {
            ArtworkCanvas(
                artwork: store.currentArtwork,
                revealProgress: store.artworkRevealProgress,
                reducedMotion: reduceMotion,
                journeyID: store.artworkJourneyID
            )

            ImmersiveEdgeScrims()

            VStack(spacing: 0) {
                DashboardToolbar(showGallery: showGallery, usesLightForeground: true)
                Spacer()
                ActiveControlDock()
            }
            .padding(.horizontal, TelaMetrics.contentPadding)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .ignoresSafeArea()
        .foregroundStyle(.white)
    }
}

private struct DashboardToolbar: View {
    @Environment(TelaSessionStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    let showGallery: () -> Void
    let usesLightForeground: Bool

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "circle.hexagongrid.fill")
                Text("Tela")
                    .fontWeight(.semibold)
                if store.state != .idle {
                    Text(store.currentArtwork.title)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .font(.subheadline)

            Spacer()

            TelaGlassGroup(spacing: 8) {
                HStack(spacing: 8) {
                    Button(action: showGallery) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .frame(width: 20, height: 20)
                    }
                    .telaGlassButton()
                    .keyboardShortcut("g", modifiers: [.command])
                    .help("Galleria")
                    .accessibilityLabel("Galleria")

                    Button {
                        openWindow(id: "activity")
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                            .frame(width: 20, height: 20)
                    }
                    .telaGlassButton()
                    .help("Attività")
                    .accessibilityLabel("Attività")

#if TELA_DEMO
                    Button {
                        openWindow(id: "demo")
                    } label: {
                        Image(systemName: "sparkles.rectangle.stack")
                            .frame(width: 20, height: 20)
                    }
                    .telaGlassButton()
                    .help("Studio Demo")
                    .accessibilityLabel("Studio Demo")
#endif

                    SettingsLink {
                        Image(systemName: "gearshape")
                            .frame(width: 20, height: 20)
                    }
                    .telaGlassButton()
                    .help("Impostazioni")
                    .accessibilityLabel("Impostazioni")
                }
            }
        }
        .foregroundStyle(usesLightForeground ? Color.white : Color.primary)
    }
}

private struct ActiveCountdown: View {
    @Environment(TelaSessionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(store.isPaused ? "In pausa" : store.phase.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(store.formattedRemaining)
                .font(.system(.title, design: .rounded, weight: .medium))
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(minWidth: 92, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(store.phase.accessibilityLabel), \(store.state.title)")
        .accessibilityValue("\(store.formattedRemaining) rimanenti, opera visibile al \(store.artworkRevealPercentage) per cento")
    }
}

private struct ActiveControlDock: View {
    @Environment(TelaSessionStore.self) private var store

    var body: some View {
        TelaGlassGroup(spacing: 10) {
            HStack(spacing: 10) {
                TelaGlassSurface(cornerRadius: 18) {
                    ActiveCountdown()
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                }

                TelaGlassSurface(cornerRadius: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text("\(store.artworkRevealPercentage)%")
                                .fontWeight(.semibold)
                                .monospacedDigit()
                            Text("rivelato")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)

                        ProgressView(value: store.artworkRevealProgress)
                            .frame(width: 170)
                            .tint(.white)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }

                Button {
                    store.isRunning ? store.pause() : store.resume()
                } label: {
                    Label(store.isRunning ? "Pausa" : "Riprendi", systemImage: store.isRunning ? "pause.fill" : "play.fill")
                }
                .telaGlassButton(prominent: true)
                .keyboardShortcut(.space, modifiers: [])

                Button(role: .destructive) {
                    store.cancel()
                } label: {
                    Label("Interrompi", systemImage: "pause.circle")
                }
                .telaGlassButton()
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityHint("Conserva la fase tra le sessioni in sospeso")
            }
        }
    }
}
