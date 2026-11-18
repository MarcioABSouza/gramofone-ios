import SwiftUI

/// Barra fixa acima do conteúdo enquanto há fila.
struct MiniPlayer: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        if let item = player.currentItem {
            HStack(spacing: 10) {
                CoverImage(url: player.coverURL(for: item), cornerRadius: 6)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)

                    Text(subtitle(item))
                        .font(.caption)
                        .foregroundColor(.zinc400)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                Button {
                    player.toggle()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)

                Button {
                    player.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 16))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 56)
            .background(Color.zinc800)
            .overlay(alignment: .top) { progressLine }
            .contentShape(Rectangle())
            .onTapGesture { player.isExpanded = true }
        }
    }

    private var progressLine: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(Color.brand)
                .frame(width: geometry.size.width * progress, height: 2)
        }
        .frame(height: 2)
    }

    private var progress: Double {
        guard player.duration > 0 else { return 0 }
        return min(1, max(0, player.position / player.duration))
    }

    private func subtitle(_ item: QueueItem) -> String {
        [item.artist, item.albumTitle].compactMap { $0 }.joined(separator: " · ")
    }
}
