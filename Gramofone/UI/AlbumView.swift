import SwiftUI

struct AlbumView: View {
    let album: Album

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager

    @State private var detail: AlbumDetail?
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if isLoading {
                    ProgressView("Carregando faixas…")
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
                    actions(detail)

                    if !detail.isLocal {
                        Label(
                            "Faixas só no catálogo — sem cópia no servidor para tocar.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundColor(.zinc400)
                    }

                    trackList(detail)
                }
            }
            .padding(16)
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            CoverImage(url: coverURL, cornerRadius: 12)
                .frame(width: 140, height: 140)

            VStack(alignment: .leading, spacing: 6) {
                Text(album.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)

                if let artist = album.artist {
                    Text(artist)
                        .font(.subheadline)
                        .foregroundColor(.zinc400)
                }

                if !album.yearAndTypes.isEmpty {
                    Text(album.yearAndTypes)
                        .font(.caption)
                        .foregroundColor(.zinc500)
                }

                if let genre = album.genre, !genre.isEmpty {
                    Text(genre)
                        .font(.caption)
                        .foregroundColor(.zinc500)
                }

                Text(trackCountText)
                    .font(.caption)
                    .foregroundColor(.zinc500)
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Ações (tocar / baixar)

    @ViewBuilder
    private func actions(_ detail: AlbumDetail) -> some View {
        let albumId = detail.album.id
        let playable = detail.tracks.filter { $0.filePath != nil }
        let progress = downloads.progress[albumId]
        let isDownloaded = downloads.downloaded.contains(albumId)

        VStack(spacing: 10) {
            if !playable.isEmpty {
                Button {
                    play(detail: detail, startingAt: 0)
                } label: {
                    Label("Tocar (\(playable.count))", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.brand)
            }

            if let progress {
                HStack(spacing: 10) {
                    ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                        .tint(.brand)
                    Text("\(progress.done)/\(progress.total)")
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.zinc400)
                }

                if let error = progress.error {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            } else if isDownloaded {
                HStack {
                    Label("Disponível offline", systemImage: "arrow.down.circle.fill")
                        .font(.footnote)
                        .foregroundColor(.green)
                    Spacer()
                    Button("Remover download", role: .destructive) {
                        downloads.remove(albumId: albumId)
                    }
                    .font(.footnote)
                }
            } else if !playable.isEmpty {
                Button {
                    downloads.download(album: detail)
                } label: {
                    Label("Baixar para offline", systemImage: "arrow.down.circle")
                        .font(.footnote)
                }
            }
        }
    }

    // MARK: - Faixas

    private func trackList(_ detail: AlbumDetail) -> some View {
        VStack(spacing: 0) {
            ForEach(detail.tracks) { track in
                TrackRow(
                    track: track,
                    isLocal: detail.isLocal,
                    isCurrent: player.currentItem?.trackId == track.id,
                    isPlaying: player.currentItem?.trackId == track.id && player.isPlaying,
                    onTap: {
                        guard let position = detail.tracks
                            .filter({ $0.filePath != nil })
                            .firstIndex(where: { $0.id == track.id })
                        else {
                            return
                        }
                        play(detail: detail, startingAt: position)
                    }
                )

                if track.id != detail.tracks.last?.id {
                    Divider().background(Color.zinc700)
                }
            }
        }
    }

    private var trackCountText: String {
        guard let detail else { return album.trackCountLabel }
        return detail.isLocal ? album.trackCountLabel : "\(detail.tracks.count) faixas no catálogo"
    }

    private var coverURL: URL? {
        if let file = OfflineStore.coverFile(album.id) { return file }
        guard album.hasCachedCover, let client = session.client else { return nil }
        return client.coverURL(albumId: album.id)
    }

    private func play(detail: AlbumDetail, startingAt start: Int) {
        let items = detail.tracks
            .filter { $0.filePath != nil }
            .map { QueueItem(track: $0, album: detail.album) }

        guard !items.isEmpty else { return }
        player.play(queue: items, startingAt: min(start, items.count - 1))
    }

    private func load() async {
        isLoading = true
        error = nil

        do {
            detail = try await session.authorized { client, token in
                try await client.album(id: album.id, token: token)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}

private struct TrackRow: View {
    let track: Track
    let isLocal: Bool
    let isCurrent: Bool
    let isPlaying: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(track.number.map(String.init) ?? "–")
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(isCurrent ? .brand : .zinc500)
                    .frame(width: 22, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title)
                        .font(.subheadline)
                        .foregroundColor(isCurrent ? .brand : .primary)
                        .lineLimit(1)

                    if let artist = track.artist, artist.isEmpty == false {
                        Text(artist)
                            .font(.caption2)
                            .foregroundColor(.zinc500)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.brand)
                } else if !isLocal || !track.isPlayable {
                    Image(systemName: "icloud.slash")
                        .font(.caption)
                        .foregroundColor(.zinc500)
                }

                if let duration = track.durationLabel {
                    Text(duration)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.zinc500)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isLocal || !track.isPlayable)
        .opacity(isLocal && track.isPlayable ? 1 : 0.5)
    }
}
