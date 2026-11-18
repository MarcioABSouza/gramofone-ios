import SwiftUI

/// Lista de músicas: tocar a partir da linha escolhida ou tudo embaralhado.
struct SongListPage: View {
    let list: SongListSummary

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var player: PlayerController

    @State private var detail: SongListDetail?
    @State private var isLoading = true
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                actions

                if isLoading {
                    ProgressView("Carregando músicas…")
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
                    VStack(spacing: 0) {
                        ForEach(detail.items) { item in
                            row(item)

                            if item.id != detail.items.last?.id {
                                Divider().background(Color.zinc700)
                            }
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

            Text("\(detail?.items.count ?? list.itemCount) música(s) · \(playableCount) no servidor")
                .font(.caption)
                .foregroundColor(.zinc500)
        }
    }

    private var playableCount: Int {
        detail?.items.filter { $0.localTrack != nil }.count ?? 0
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                play(shuffled: false)
            } label: {
                Label("Tocar", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brand)

            Button {
                play(shuffled: true)
            } label: {
                Label("Aleatório", systemImage: "shuffle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.brand)
        }
        .disabled(playableCount == 0)
    }

    private func row(_ item: SongListDetail.Item) -> some View {
        let isCurrent = player.currentItem?.trackId == item.localTrack?.id
        let isPlayable = item.localTrack != nil

        return Button {
            play(from: item)
        } label: {
            HStack(spacing: 12) {
                Text(String(item.position))
                    .font(.footnote.monospacedDigit())
                    .foregroundColor(isCurrent ? .brand : .zinc500)
                    .frame(width: 24, alignment: .trailing)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.song.title)
                        .font(.subheadline)
                        .foregroundColor(isCurrent ? .brand : .primary)
                        .lineLimit(1)

                    Text(rowSubtitle(item))
                        .font(.caption2)
                        .foregroundColor(.zinc500)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if !isPlayable {
                    Image(systemName: "icloud.slash")
                        .font(.caption)
                        .foregroundColor(.zinc500)
                }

                if let duration = item.durationLabel {
                    Text(duration)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.zinc500)
                }
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isPlayable)
        .opacity(isPlayable ? 1 : 0.5)
    }

    private func rowSubtitle(_ item: SongListDetail.Item) -> String {
        [item.song.artist ?? item.albumArtist, item.albumTitle]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    private var queueItems: [QueueItem] {
        (detail?.items ?? []).compactMap { item in
            guard let local = item.localTrack else { return nil }
            return QueueItem(
                trackId: local.id,
                songId: item.song.id,
                albumId: item.albumId ?? item.song.albumId,
                albumTitle: item.albumTitle,
                title: item.song.title,
                artist: item.song.artist ?? item.albumArtist,
                duration: item.song.duration,
                filePath: local.filePath,
                number: item.song.number
            )
        }
    }

    private func play(shuffled: Bool) {
        let items = queueItems
        guard !items.isEmpty else { return }

        if shuffled {
            player.playShuffled(items)
        } else {
            player.play(queue: items, startingAt: 0)
        }
    }

    private func play(from item: SongListDetail.Item) {
        guard let local = item.localTrack else { return }

        let items = queueItems
        guard let start = items.firstIndex(where: { $0.trackId == local.id }) else { return }
        player.play(queue: items, startingAt: start)
    }

    private func load() async {
        isLoading = true
        error = nil

        do {
            detail = try await session.authorized { client, token in
                try await client.songList(id: list.id, token: token)
            }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }
}
