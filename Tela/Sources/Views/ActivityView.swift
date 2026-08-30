import SwiftUI

struct ActivityView: View {
    @Environment(TelaSessionStore.self) private var store

    private var pending: [TimerSessionRecord] {
        store.sessionHistory
            .filter { $0.status == .paused || $0.status == .suspended }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    private var today: [TimerSessionRecord] {
        store.sessionHistory
            .filter { Calendar.current.isDateInToday($0.startedAt ?? $0.endedAt ?? .distantPast) }
            .sorted { ($0.startedAt ?? .distantPast) > ($1.startedAt ?? .distantPast) }
    }

    private var history: [TimerSessionRecord] {
        store.sessionHistory
            .filter { $0.status == .completed || $0.status == .abandoned }
            .sorted { ($0.endedAt ?? $0.startedAt ?? .distantPast) > ($1.endedAt ?? $1.startedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationSplitView {
            List {
                Label("In sospeso", systemImage: "pause.circle")
                Label("Oggi", systemImage: "calendar")
                Label("Cronologia", systemImage: "clock.arrow.circlepath")
                Label("Quadri", systemImage: "photo.artframe")
            }
            .navigationTitle("Attività")
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            List {
                pendingSection
                todaySection
                historySection
                artworksSection
            }
            .navigationTitle("Attività")
        }
        .frame(minWidth: 780, minHeight: 540)
    }

    @ViewBuilder
    private var pendingSection: some View {
        Section("In sospeso") {
            if pending.isEmpty {
                Text("Nessuna fase da riprendere")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pending) { session in
                    PendingSessionRow(session: session, artwork: store.artwork(for: session.artworkID)) {
                        store.resumeSession(id: session.id)
                    } abandon: {
                        store.abandonSession(id: session.id)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var todaySection: some View {
        Section("Oggi") {
            ForEach(today) { session in
                SessionHistoryRow(session: session, artwork: store.artwork(for: session.artworkID))
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section("Cronologia") {
            ForEach(history) { session in
                SessionHistoryRow(session: session, artwork: store.artwork(for: session.artworkID))
            }
        }
    }

    @ViewBuilder
    private var artworksSection: some View {
        Section("Quadri") {
            if store.archivedArtworkRecords.isEmpty {
                Text("Nessun quadro completato")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.archivedArtworkRecords) { record in
                    CompletedArtworkRow(record: record, artwork: store.artwork(for: record.artworkID))
                }
            }
        }
    }
}

private struct PendingSessionRow: View {
    let session: TimerSessionRecord
    let artwork: Artwork?
    let resume: () -> Void
    let abandon: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.phase.isFocus ? "brain.head.profile" : "cup.and.saucer")
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(session.phase.title).font(.headline)
                Text("\(artwork?.title ?? "Nessuna opera") · \(TelaSessionStore.format(seconds: Int(ceil(session.remaining)))) rimanenti")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Riprendi", action: resume)
                .buttonStyle(.borderedProminent)
            Button("Abbandona", role: .destructive, action: abandon)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

private struct SessionHistoryRow: View {
    let session: TimerSessionRecord
    let artwork: Artwork?

    var body: some View {
        LabeledContent {
            Text(session.status.activityTitle)
                .foregroundStyle(session.status == .completed ? .green : .secondary)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.phase.title)
                Text(artwork?.title ?? "Nessuna opera")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CompletedArtworkRow: View {
    let record: CompletedArtwork
    let artwork: Artwork?

    var body: some View {
        HStack(spacing: 12) {
            if let artwork {
                ArtworkThumbnail(artwork: artwork, cornerRadius: 8)
                    .frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(artwork?.title ?? "Opera completata").font(.headline)
                Label(
                    record.completeRoutine ? "Ciclo completo" : "Percorso parziale",
                    systemImage: record.completeRoutine ? "checkmark.seal.fill" : "circle.dashed"
                )
                .font(.caption)
                .foregroundStyle(record.completeRoutine ? .green : .secondary)
            }
            Spacer()
            Text(record.completedAt, format: .dateTime.day().month().year())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private extension TimerSessionStatus {
    var activityTitle: String {
        switch self {
        case .running: "In corso"
        case .paused: "In pausa"
        case .suspended: "Sospesa"
        case .completed: "Completata"
        case .abandoned: "Abbandonata"
        }
    }
}
