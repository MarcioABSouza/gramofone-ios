import SwiftUI

/// Lista de álbuns: tocar na ordem, aleatório (embaralhando as faixas) e abrir cada álbum.
struct AlbumListPage: View {
    let list: AlbumListSummary

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var player: PlayerController

    @State private var detail: AlbumListDetail?
    @State private var isLoading = true
    @State private var error: String?
    @State private var isPreparing = false

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                actions

                if isLoading {
                    ProgressView("Carregando álbuns…")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                } else if let error {
                    VStack(spacing: 10) {
                        Text(error)
                            .foregroundColor(.zinc400)
                            .multilineTextAlignment(.center)
                        Button("Tentar novamente") {
                            Task { await load() }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                } else if let detail {
                    LazyVGrid(columns: columns, spacing: 18) {
                        ForEach(detail.items) { item in
                            NavigationLink(
                                destination: AlbumView(album: item.album),
                                label: {
                                    AlbumCell(album: item.album)
                                }
                            )
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(list.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(list.name)
                .font(.title3.weight(.semibold))

            if let description = list.description, !description.isEmpty {
                Text(description)
                    .font(.footnote)
                    .foregroundColor(.zinc400)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.zinc500)
        }
    }

    private var subtitle: String {
        let count = detail?.list.itemCount ?? list.itemCount
        let playable = detail?.list.playableCount
        var text = "\(count) álbum(ns)"
        if let playable {
            text += " · \(playable) faixa(s) no servidor"
        }
        return text
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                Task { await playFromList(shuffled: false) }
            } label: {
                Label("Tocar", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brand)

            Button {
                Task { await playFromList(shuffled: true) }
            } label: {
                Label("Aleatório", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.brand)
        }
        .disabled(isPreparing || (detail?.list.playableCount ?? 0) == 0)
    }

    private func load() async {
        isLoading = true
        error = nil

        do {
            detail = try await session.authorized { client, token in
                try await client.albumList(id: list.id, token: token)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }

    private func playFromList(shuffled: Bool) async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        do {
            let tracks = try await session.authorized { client, token in
                try await client.listTracks(kind: "albums", id: list.id, token: token)
            }

            let items = tracks.map(\.queueItem)
            guard !items.isEmpty else { return }

            if shuffled {
                player.playShuffled(items)
            } else {
                player.play(queue: items, startingAt: 0)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
