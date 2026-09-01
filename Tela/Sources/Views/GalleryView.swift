import SwiftUI
import UniformTypeIdentifiers

private enum GalleryShelf: String, CaseIterable, Identifiable {
    case all
    case klimt
    case monaLisa
    case imported
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Tutte le opere"
        case .klimt: "Gustav Klimt"
        case .monaLisa: "Gli occhi di Monna Lisa"
        case .imported: "Importate"
        case .completed: "Completate"
        }
    }

    var symbol: String {
        switch self {
        case .all: "photo.stack"
        case .klimt: "sun.max"
        case .monaLisa: "book.closed"
        case .imported: "square.and.arrow.down"
        case .completed: "checkmark.seal"
        }
    }
}

struct GalleryView: View {
    @Environment(TelaSessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var shelf: GalleryShelf? = .all
    @State private var searchText = ""
    @State private var showingImporter = false
    @State private var importMessage: String?

    private var selectedShelf: GalleryShelf { shelf ?? .all }

    private var artworks: [Artwork] {
        let candidates: [Artwork]
        switch selectedShelf {
        case .all:
            candidates = store.bundledArtworks
        case .klimt:
            candidates = store.bundledArtworks.filter { $0.collections?.contains("Klimt") == true }
        case .monaLisa:
            candidates = store.bundledArtworks.filter { $0.collections?.contains("Gli occhi di Monna Lisa") == true }
        case .imported:
            candidates = store.importedArtworks
        case .completed:
            candidates = store.completedArtworks
        }

        guard !searchText.isEmpty else { return candidates }
        return candidates.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
                ($0.artist?.localizedCaseInsensitiveContains(searchText) == true)
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $shelf) {
                Section("Biblioteca") {
                    shelfLink(.all)
                    shelfLink(.klimt)
                    shelfLink(.monaLisa)
                }

                Section("La mia raccolta") {
                    shelfLink(.imported)
                    shelfLink(.completed)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 220)
        } detail: {
            VStack(spacing: 0) {
                GallerySearchField(text: $searchText)
                galleryContent
            }
                .navigationTitle(selectedShelf.title)
                .toolbar { galleryToolbar }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true,
            onCompletion: handleImport
        )
    }

    private func shelfLink(_ value: GalleryShelf) -> some View {
        Label(value.title, systemImage: value.symbol)
            .tag(value)
    }

    @ViewBuilder
    private var galleryContent: some View {
        if artworks.isEmpty {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: selectedShelf.symbol)
            } description: {
                Text(emptyDescription)
            } actions: {
                if selectedShelf == .imported {
                    Button("Importa un’immagine") { showingImporter = true }
                        .telaGlassButton(prominent: true)
                }
            }
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 18)],
                    spacing: 22
                ) {
                    ForEach(artworks) { artwork in
                        GalleryArtworkCard(
                            artwork: artwork,
                            isSelected: artwork.id == store.currentArtwork.id
                        ) {
                            store.selectArtwork(artwork)
                        }
                    }
                }
                .padding(TelaMetrics.contentPadding)
            }
            .safeAreaInset(edge: .bottom) {
                if let message = store.importErrorMessage ?? importMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var galleryToolbar: some ToolbarContent {
        ToolbarItemGroup {
            if selectedShelf != .completed {
                Button {
                    store.selectNextArtwork()
                } label: {
                    Label("Opera successiva", systemImage: "shuffle")
                }
                .help("Seleziona l’opera successiva")
            }

            Button {
                showingImporter = true
            } label: {
                Label("Importa", systemImage: "square.and.arrow.down")
            }
            .help("Importa immagini JPG, PNG o HEIC")

            Button("Fine") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
        }
    }

    private var emptyTitle: String {
        switch selectedShelf {
        case .completed: "Nessuna opera completata"
        case .imported: "Nessuna immagine importata"
        default: "Nessun risultato"
        }
    }

    private var emptyDescription: String {
        switch selectedShelf {
        case .completed: "Le opere interamente rivelate appariranno qui."
        case .imported: "Aggiungi una tua immagine alla raccolta locale di Tela."
        default: "Prova a modificare la ricerca."
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            urls.forEach(store.importArtwork)
            importMessage = store.importErrorMessage ?? (urls.isEmpty ? nil : "Importazione completata")
        case .failure:
            importMessage = "Importazione annullata"
        }
    }
}

private struct GallerySearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Cerca opera o artista", text: $text)
                .textFieldStyle(.plain)
                .accessibilityLabel("Cerca opera o artista")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Cancella ricerca")
            }
        }
        .padding(8)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, TelaMetrics.contentPadding)
        .padding(.top, 16)
        .padding(.bottom, 4)
    }
}

private struct GalleryArtworkCard: View {
    let artwork: Artwork
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ArtworkThumbnail(artwork: artwork, cornerRadius: 14)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(10)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }

                Text(artwork.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if !artwork.subtitleText.isEmpty {
                    Text(artwork.subtitleText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 3)
                .allowsHitTesting(false)
        }
        .animation(.snappy, value: isSelected)
        .accessibilityLabel("\(artwork.title), \(artwork.artist ?? "artista sconosciuto")")
        .accessibilityValue(isSelected ? "Opera selezionata" : "Non selezionata")
        .accessibilityHint("Seleziona quest’opera per le prossime sessioni")
    }
}
