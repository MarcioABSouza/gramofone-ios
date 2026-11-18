import SwiftUI

struct LibraryView: View {
    @ObservedObject var session: Session
    let user: PublicUser

    @State private var albums: [Album] = []
    @State private var total = 0
    @State private var search = ""
    @State private var query = ""
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
                if isLoading {
                    ProgressView("Carregando biblioteca…")
                        .padding(.top, 60)
                } else if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.zinc400)
                        Button("Tentar novamente") {
                            Task { await reload() }
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
                            // Forma "eager" do NavigationLink: a versão com closure
                            // de destino só existe a partir do iOS 16.
                            NavigationLink(
                                destination: AlbumView(session: session, album: album),
                                label: {
                                    AlbumCell(album: album, session: session)
                                }
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
            .searchable(text: $search, prompt: "Buscar álbum ou artista")
            .onChange(of: search) { newValue in
                Task {
                    // Debounce: só consulta depois de 350 ms sem digitar.
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard trimmed == search.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                    query = trimmed
                    await reload()
                }
            }
            .navigationTitle("Biblioteca")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAccount = true
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .sheet(isPresented: $showAccount) {
                AccountView(session: session, user: user)
            }
            .task {
                if albums.isEmpty { await reload() }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func reload() async {
        isLoading = albums.isEmpty
        error = nil

        do {
            let page = try await session.authorized { client, token in
                try await client.albums(token: token, skip: 0, take: pageSize, search: query)
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
                try await client.albums(token: token, skip: skip, take: pageSize, search: query)
            }
            albums.append(contentsOf: page.data)
            total = page.total
        } catch {
            // Paginação falhou: mantém o que já está na tela.
        }

        isLoadingMore = false
    }
}

private struct AlbumCell: View {
    let album: Album
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            CoverImage(url: coverURL)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if album.isComplete {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(6)
                    }
                }

            Text(album.title)
                .font(.subheadline.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.zinc400)
                .lineLimit(1)
        }
    }

    private var subtitle: String {
        var parts: [String] = []
        if let artist = album.artist { parts.append(artist) }
        if let year = album.year { parts.append(String(year)) }
        return parts.isEmpty ? album.trackCountLabel : parts.joined(separator: " · ")
    }

    private var coverURL: URL? {
        guard album.hasCachedCover else { return nil }
        guard let client = session.client else { return nil }
        return client.coverURL(albumId: album.id)
    }
}
