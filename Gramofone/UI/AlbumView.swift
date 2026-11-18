import SwiftUI

struct AlbumView: View {
    @ObservedObject var session: Session
    let album: Album

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
                    if !detail.isLocal {
                        Label(
                            "Faixas só no catálogo — sem cópia no servidor para tocar.",
                            systemImage: "info.circle"
                        )
                        .font(.footnote)
                        .foregroundColor(.zinc400)
                    }

                    VStack(spacing: 0) {
                        ForEach(detail.tracks) { track in
                            TrackRow(track: track, isLocal: detail.isLocal)

                            if track.id != detail.tracks.last?.id {
                                Divider().background(Color.zinc700)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(album.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

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

    private var trackCountText: String {
        guard let detail else { return album.trackCountLabel }
        return detail.isLocal ? album.trackCountLabel : "\(detail.tracks.count) faixas no catálogo"
    }

    private var coverURL: URL? {
        guard album.hasCachedCover, let client = session.client else { return nil }
        return client.coverURL(albumId: album.id)
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

    var body: some View {
        HStack(spacing: 12) {
            Text(track.number.map(String.init) ?? "–")
                .font(.footnote.monospacedDigit())
                .foregroundColor(.zinc500)
                .frame(width: 22, alignment: .trailing)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(.subheadline)
                    .lineLimit(1)

                if let artist = track.artist, artist.isEmpty == false {
                    Text(artist)
                        .font(.caption2)
                        .foregroundColor(.zinc500)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if !isLocal || !track.isPlayable {
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
        .opacity(isLocal && track.isPlayable ? 1 : 0.5)
    }
}
