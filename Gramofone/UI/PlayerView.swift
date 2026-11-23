import SwiftUI

/// Tela cheia do player (abre pela mini barra).
struct PlayerView: View {
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var isFavorite = false
    @State private var favoriteReady = false
    @State private var favoriteBusy = false
    @State private var showingAddToList = false
    @State private var note: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    header

                    if let item = player.currentItem {
                        CoverImage(url: player.coverURL(for: item), cornerRadius: 16)
                            .aspectRatio(1, contentMode: .fit)
                            .frame(maxWidth: 320)

                        VStack(spacing: 4) {
                            Text(item.title)
                                .font(.title2.weight(.semibold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)

                            Text(subtitle(item))
                                .font(.subheadline)
                                .foregroundColor(.zinc400)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                        }

                        progressBar
                        controls
                        songActions(item)

                        if let error = player.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundColor(.orange)
                        }

                        if let note {
                            Label(note, systemImage: "checkmark.circle")
                                .font(.footnote)
                                .foregroundColor(.zinc400)
                                .multilineTextAlignment(.center)
                        }

                        queueList
                    } else {
                        Text("Fila vazia")
                            .foregroundColor(.zinc400)
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .task(id: player.currentItem?.songId) {
                await loadFavorite()
            }
        }
        .sheet(isPresented: $showingAddToList) {
            if let songId = player.currentItem?.songId {
                AddToListSheet(songId: songId, onAdded: { name in
                    note = "Adicionada a \(name)"
                })
            }
        }
    }

    private func songActions(_ item: QueueItem) -> some View {
        let songId = item.songId
        let enabled = songId != nil && network.isOnline

        return VStack(spacing: 6) {
            HStack(spacing: 14) {
                Button {
                    guard let songId else { return }
                    Task { await toggleFavorite(songId: songId) }
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 22))
                        .foregroundColor(isFavorite ? .brand : .zinc400)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .disabled(!enabled || !favoriteReady || favoriteBusy)
                .opacity(enabled ? 1 : 0.4)

                Button {
                    showingAddToList = true
                } label: {
                    Label("Adicionar à playlist", systemImage: "text.badge.plus")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
                .tint(.brand)
                .disabled(!enabled)
            }

            if !network.isOnline {
                Text("Favoritos e playlists precisam de conexão.")
                    .font(.caption)
                    .foregroundColor(.zinc500)
            }
        }
    }

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text("Tocando")
                .font(.footnote.weight(.medium))
                .foregroundColor(.zinc400)

            Spacer()

            Color.clear.frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var progressBar: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { isScrubbing ? scrubValue : player.position },
                    set: { value in
                        scrubValue = value
                        isScrubbing = true
                    }
                ),
                in: 0...max(player.duration, 1),
                onEditingChanged: { editing in
                    if !editing {
                        player.seek(to: scrubValue)
                        isScrubbing = false
                    }
                }
            )
            .tint(.brand)

            HStack {
                Text(timeLabel(isScrubbing ? scrubValue : player.position))
                Spacer()
                Text(timeLabel(player.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundColor(.zinc500)
        }
    }

    private var controls: some View {
        // Larguras somadas cabem nos 320 pt do iPod (268 pt de 280 disponíveis).
        HStack(spacing: 8) {
            Button {
                player.cycleRepeat()
            } label: {
                Image(systemName: player.repeatMode.symbol)
                    .font(.system(size: 16))
                    .foregroundColor(player.repeatMode.isActive ? .brand : .zinc500)
                    .frame(width: 40, height: 44)
            }

            Button {
                player.previous()
            } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 24))
                    .frame(width: 52, height: 52)
            }

            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.brand)
            }

            Button {
                player.next()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 24))
                    .frame(width: 52, height: 52)
            }

            Color.clear.frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var queueList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Na fila")
                .font(.footnote.weight(.medium))
                .foregroundColor(.zinc400)
                .padding(.top, 8)

            ForEach(Array(player.queue.enumerated()), id: \.element.id) { position, item in
                Button {
                    player.jump(to: position)
                } label: {
                    HStack(spacing: 10) {
                        Text(item.number.map(String.init) ?? "–")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.zinc500)
                            .frame(width: 22, alignment: .trailing)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.subheadline)
                                .foregroundColor(position == player.index ? .brand : .primary)
                                .lineLimit(1)

                            if let artist = item.artist {
                                Text(artist)
                                    .font(.caption2)
                                    .foregroundColor(.zinc500)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)

                        if position == player.index, player.isPlaying {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundColor(.brand)
                        }
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadFavorite() async {
        favoriteReady = false
        note = nil

        guard let songId = player.currentItem?.songId, network.isOnline else { return }

        do {
            let status: SongStatus = try await session.authorized { client, token in
                try await client.songStatus(songId: songId, token: token)
            }
            guard player.currentItem?.songId == songId else { return }
            isFavorite = status.isFavorite
            favoriteReady = true
        } catch {
            guard !Task.isCancelled else { return }
            note = message(for: error)
        }
    }

    /// O toggle não é idempotente: em falha, lê o estado real antes de qualquer nova tentativa.
    private func toggleFavorite(songId: String) async {
        guard !favoriteBusy else { return }
        favoriteBusy = true
        note = nil
        defer { favoriteBusy = false }

        do {
            let status: SongStatus = try await session.authorized { client, token in
                try await client.toggleFavorite(songId: songId, token: token)
            }
            guard player.currentItem?.songId == songId else { return }
            isFavorite = status.isFavorite
        } catch {
            let actual: SongStatus? = try? await session.authorized { client, token in
                try await client.songStatus(songId: songId, token: token)
            }
            if let actual, player.currentItem?.songId == songId {
                isFavorite = actual.isFavorite
            }
            note = message(for: error)
        }
    }

    private func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func subtitle(_ item: QueueItem) -> String {
        [item.artist, item.albumTitle].compactMap { $0 }.joined(separator: " · ")
    }

    private func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
