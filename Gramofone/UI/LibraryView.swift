import SwiftUI

enum LibrarySort: String, CaseIterable, Identifiable {
    case title, artist, year, added

    var id: String { rawValue }

    var label: String {
        switch self {
        case .title: return "Título"
        case .artist: return "Artista"
        case .year: return "Ano"
        case .added: return "Adicionado"
        }
    }

    /// Texto começa A–Z; ano/data começam pelos mais recentes.
    var defaultAscending: Bool {
        switch self {
        case .title, .artist: return true
        case .year, .added: return false
        }
    }

    var isText: Bool {
        self == .title || self == .artist
    }
}

struct LibraryView: View {
    enum Tab: Hashable { case library, downloads }

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var network: NetworkMonitor

    @State private var tab: Tab = .library
    @State private var sort: LibrarySort = {
        let raw = UserDefaults.standard.string(forKey: "gramofone.library.sort") ?? ""
        return LibrarySort(rawValue: raw) ?? .title
    }()
    @State private var ascending: Bool = {
        if let stored = UserDefaults.standard.object(forKey: "gramofone.library.ascending") as? Bool {
            return stored
        }
        return true
    }()

    @State private var search = ""
    @State private var query = ""
    @State private var albums: [Album] = []
    @State private var offlineAlbums: [OfflineAlbum] = []
    @State private var total = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var error: String?
    @State private var showAccount = false

    private let pageSize = 24

    private let columns = [
        GridItem(.adaptive(minimum: 140), spacing: 14),
    ]

    var body: some View {
        NavigationView {
            ScrollView {
                if !network.isOnline {
                    offlineBanner
                }

                Picker("Aba", selection: $tab) {
                    Text("Biblioteca").tag(Tab.library)
                    Text("Baixados").tag(Tab.downloads)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                if tab == .library {
                    libraryContent
                } else {
                    downloadsContent
                }
            }
            .searchable(text: $search, prompt: tab == .library ? "Buscar álbum ou artista" : "Filtrar baixados")
            .onChange(of: search) { newValue in
                guard tab == .library else { return }

                Task {
                    // Debounce: só consulta depois de 350 ms sem digitar.
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed == search.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                    query = trimmed
                    await reload()
                }
            }
            .onChange(of: sort) { _ in
                ascending = sort.defaultAscending
                savePreferences()
                Task { await reload() }
            }
            .navigationTitle(tab == .library ? "Biblioteca" : "Baixados")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink(destination: ListsView()) {
                            Image(systemName: "list.bullet")
                        }

                        Menu {
                            sortMenu
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAccount) {
                AccountView()
            }
            .task {
                reloadOffline()

                // Sem rede a única aba útil é a de baixados.
                if !network.isOnline {
                    tab = .downloads
                    isLoading = false
                    return
                }

                if albums.isEmpty { await reload() }
            }
            .onChange(of: downloads.downloaded) { _ in
                reloadOffline()
            }
            .onChange(of: tab) { _ in
                if tab == .downloads { reloadOffline() }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    // MARK: - Menu

    @ViewBuilder
    private var sortMenu: some View {
        Picker("Ordenar por", selection: $sort) {
            ForEach(LibrarySort.allCases) { option in
                Text(option.label).tag(option)
            }
        }

        Button(orderLabel) {
            ascending.toggle()
            savePreferences()
            Task { await reload() }
        }

        Divider()

        Button {
            showAccount = true
        } label: {
            Label("Conta", systemImage: "person.crop.circle")
        }
    }

    private var orderLabel: String {
        if sort.isText {
            return ascending ? "A–Z" : "Z–A"
        }
        return ascending ? "Antigos primeiro" : "Recentes primeiro"
    }

    private func savePreferences() {
        UserDefaults.standard.set(sort.rawValue, forKey: "gramofone.library.sort")
        UserDefaults.standard.set(ascending, forKey: "gramofone.library.ascending")
    }

    // MARK: - Aba Biblioteca

    @ViewBuilder
    private var libraryContent: some View {
        if isLoading {
            ProgressView("Carregando biblioteca…")
                .padding(.top, 60)
        } else if let error {
            VStack(spacing: 12) {
                Image(systemName: network.isOnline ? "exclamationmark.triangle" : "wifi.slash")
                    .font(.largeTitle)
                    .foregroundColor(.orange)

                Text(network.isOnline ? error : "Sem conexão. Os álbuns baixados continuam disponíveis.")
                    .multilineTextAlignment(.center)
                    .foregroundColor(.zinc400)

                if network.isOnline {
                    Button("Tentar novamente") {
                        Task { await reload() }
                    }
                } else {
                    Button("Ir para Baixados") {
                        tab = .downloads
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brand)
                }
            }
            .padding(32)
        } else if albums.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "square.grid.2x2")
                    .font(.largeTitle)
                    .foregroundColor(.zinc500)
                Text(query.isEmpty ? "Nenhum álbum no servidor." : "Nada encontrado para “\(query)”.")
                    .foregroundColor(.zinc400)
            }
            .padding(.top, 60)
        } else {
            LazyVGrid(columns: columns, spacing: 18) {
                ForEach(albums) { album in
                    // Forma "eager" do NavigationLink: a versão com closure de
                    // destino só existe a partir do iOS 16.
                    NavigationLink(
                        destination: AlbumView(album: album),
                        label: { AlbumCell(album: album) }
                    )
                    .buttonStyle(.plain)
                    .onAppear {
                        if album.id == albums.last?.id {
                            Task { await loadMore() }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isLoadingMore {
                ProgressView()
                    .padding(.vertical, 16)
            } else {
                Text("\(albums.count) de \(total)")
                    .font(.footnote)
                    .foregroundColor(.zinc500)
                    .padding(.vertical, 16)
            }
        }
    }

    // MARK: - Aba Baixados

    @ViewBuilder
    private var downloadsContent: some View {
        let filtered = filteredOfflineAlbums

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(offlineAlbums.count) álbum(ns) · \(downloads.totalBytesLabel)")
                    .font(.footnote)
                    .foregroundColor(.zinc400)
                Spacer()
            }

            HStack(spacing: 10) {
                Button {
                    playAllDownloads(shuffled: false)
                } label: {
                    Label("Tocar tudo", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)

                Button {
                    playAllDownloads(shuffled: true)
                } label: {
                    Label("Aleatório", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .tint(.brand)
            }
            .disabled(offlineAlbums.isEmpty)

            if offlineAlbums.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                        .font(.largeTitle)
                        .foregroundColor(.zinc500)
                    Text("Nenhum álbum baixado ainda.")
                        .foregroundColor(.zinc400)
                    Text("Abra um álbum e use “Baixar para offline”.")
                        .font(.footnote)
                        .foregroundColor(.zinc500)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)
            } else if filtered.isEmpty {
                Text("Nada encontrado para “\(search)”.")
                    .foregroundColor(.zinc400)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(filtered) { offline in
                        NavigationLink(
                            destination: AlbumView(album: Album.from(manifest: offline)),
                            label: { AlbumCell(album: Album.from(manifest: offline)) }
                        )
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(16)
    }

    private var filteredOfflineAlbums: [OfflineAlbum] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return offlineAlbums }

        return offlineAlbums.filter { album in
            album.title.lowercased().contains(term) || (album.artist ?? "").lowercased().contains(term)
        }
    }

    private func playAllDownloads(shuffled: Bool) {
        // Ordem previsível: por título do álbum, depois número da faixa.
        let items = offlineAlbums
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .flatMap(\.queueItems)

        guard !items.isEmpty else { return }

        if shuffled {
            player.playShuffled(items)
        } else {
            player.play(queue: items, startingAt: 0)
        }
    }

    private func reloadOffline() {
        offlineAlbums = OfflineStore.all()
    }

    // MARK: - Rede

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("Sem conexão — só o que está baixado toca.")
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundColor(.orange)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.12))
    }

    private func reload() async {
        isLoading = albums.isEmpty
        error = nil

        do {
            let page = try await session.authorized { client, token in
                try await client.albums(
                    token: token,
                    skip: 0,
                    take: pageSize,
                    search: query,
                    sort: sort.rawValue,
                    order: ascending ? "asc" : "desc"
                )
            }
            albums = page.data
            total = page.total
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }

    private func loadMore() async {
        guard !isLoadingMore, albums.count < total, !isLoading else { return }

        isLoadingMore = true
        let skip = albums.count

        do {
            let page = try await session.authorized { client, token in
                try await client.albums(
                    token: token,
                    skip: skip,
                    take: pageSize,
                    search: query,
                    sort: sort.rawValue,
                    order: ascending ? "asc" : "desc"
                )
            }
            albums.append(contentsOf: page.data)
            total = page.total
        } catch {
            // Paginação falhou: mantém o que já está na tela.
        }

        isLoadingMore = false
    }
}
