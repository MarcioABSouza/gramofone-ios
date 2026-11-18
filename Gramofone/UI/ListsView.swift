import SwiftUI

/// Listas do usuário: álbuns e músicas (somente leitura).
struct ListsView: View {
    enum Kind: Hashable { case albums, songs }

    @EnvironmentObject private var session: Session

    @State private var kind: Kind = .albums
    @State private var albumLists: [AlbumListSummary] = []
    @State private var songLists: [SongListSummary] = []
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            Picker("Tipo", selection: $kind) {
                Text("Álbuns").tag(Kind.albums)
                Text("Músicas").tag(Kind.songs)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)

            if isLoading {
                ProgressView("Carregando listas…")
                    .padding(.top, 60)
            } else if let error {
                VStack(spacing: 10) {
                    Text(error)
                        .foregroundColor(.zinc400)
                        .multilineTextAlignment(.center)
                    Button("Tentar novamente") {
                        Task { await load() }
                    }
                }
                .padding(32)
            } else if kind == .albums {
                albumRows
            } else {
                songRows
            }
        }
        .navigationTitle("Listas")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private var albumRows: some View {
        if albumLists.isEmpty {
            emptyState("Nenhuma lista de álbuns.")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(albumLists) { list in
                    NavigationLink(destination: AlbumListPage(list: list)) {
                        HStack(spacing: 12) {
                            AlbumMosaic(previews: list.previewAlbums)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                Text("\(list.itemCount) álbum(ns)")
                                    .font(.caption)
                                    .foregroundColor(.zinc400)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.zinc500)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .background(Color.zinc700)
                        .padding(.leading, 84)
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var songRows: some View {
        if songLists.isEmpty {
            emptyState("Nenhuma lista de músicas.")
        } else {
            LazyVStack(spacing: 0) {
                ForEach(songLists) { list in
                    NavigationLink(destination: SongListPage(list: list)) {
                        HStack(spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.zinc800)
                                Image(systemName: "music.note.list")
                                    .foregroundColor(.brand)
                            }
                            .frame(width: 56, height: 56)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.primary)
                                    .lineLimit(2)

                                Text("\(list.itemCount) música(s)")
                                    .font(.caption)
                                    .foregroundColor(.zinc400)
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.zinc500)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider()
                        .background(Color.zinc700)
                        .padding(.leading, 84)
                }
            }
            .padding(.top, 8)
        }
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list")
                .font(.largeTitle)
                .foregroundColor(.zinc500)
            Text(text)
                .foregroundColor(.zinc400)
        }
        .padding(.top, 60)
    }

    private func load() async {
        isLoading = true
        error = nil

        do {
            albumLists = try await session.authorized { client, token in
                try await client.albumLists(token: token)
            }

            songLists = try await session.authorized { client, token in
                try await client.songLists(token: token)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}
