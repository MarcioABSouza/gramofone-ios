import SwiftUI

/// Card de álbum usado na Biblioteca, nas listas e nos baixados.
struct AlbumCell: View {
    let album: Album

    @EnvironmentObject private var session: Session
    @EnvironmentObject private var downloads: DownloadManager

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
                .overlay(alignment: .bottomLeading) {
                    if downloads.downloaded.contains(album.id) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption)
                            .foregroundColor(.brand)
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
        if let file = OfflineStore.coverFile(album.id) { return file }
        guard album.hasCachedCover, let client = session.client else { return nil }
        return client.coverURL(albumId: album.id)
    }
}

/// Mosaico do card de lista: 1 capa ou 2×2.
struct AlbumMosaic: View {
    let previews: [AlbumCoverPreview]

    @EnvironmentObject private var session: Session

    var body: some View {
        Group {
            if previews.count >= 4 {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 2), GridItem(.flexible(), spacing: 2)],
                    spacing: 2
                ) {
                    ForEach(Array(previews.prefix(4))) { preview in
                        CoverImage(url: url(for: preview), cornerRadius: 0)
                            .aspectRatio(1, contentMode: .fit)
                    }
                }
            } else if let first = previews.first {
                CoverImage(url: url(for: first), cornerRadius: 0)
            } else {
                ZStack {
                    Color.zinc800
                    Image(systemName: "opticaldisc")
                        .foregroundColor(.zinc500)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func url(for preview: AlbumCoverPreview) -> URL? {
        guard preview.hasCachedCover, let client = session.client else { return nil }
        return client.coverURL(albumId: preview.id)
    }
}
