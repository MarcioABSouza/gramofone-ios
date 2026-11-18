import Foundation

// MARK: - Fila (mesmo shape de /library/tracks, /home/lists/…/tracks e /home/random)

struct QueueTrack: Decodable {
    let trackId: String
    let songId: String?
    let title: String
    let artist: String?
    let albumId: String
    let albumTitle: String
    let albumArtist: String?
    let albumArtistId: String?
    let duration: Double?
    let filePath: String

    var queueItem: QueueItem {
        QueueItem(
            trackId: trackId,
            songId: songId,
            albumId: albumId,
            albumTitle: albumTitle,
            title: title,
            artist: artist ?? albumArtist,
            duration: duration,
            filePath: filePath,
            number: nil
        )
    }
}

struct QueueTracksResponse: Decodable {
    let data: [QueueTrack]
}

// MARK: - Listas de álbuns

struct AlbumCoverPreview: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let coverUrl: String?
    let localCoverPath: String?
    let hasCachedCover: Bool
    let coverVersion: String?
}

struct AlbumListSummary: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let itemCount: Int
    let previewAlbums: [AlbumCoverPreview]
}

struct AlbumListDetail: Decodable {
    struct Info: Decodable, Equatable {
        let id: String
        let name: String
        let description: String?
        let itemCount: Int
        let playableCount: Int
    }

    struct Item: Decodable, Identifiable {
        let position: Int
        let album: Album

        var id: String { album.id }
    }

    let list: Info
    let items: [Item]
}

// MARK: - Listas de músicas

struct SongListSummary: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String?
    let itemCount: Int
    /// Lista virtual do sistema ("Favoritas").
    let system: Bool?
}

struct SongListDetail: Decodable {
    struct Info: Decodable, Equatable {
        let id: String
        let name: String
        let description: String?
        let system: Bool?
    }

    struct WrittenSong: Decodable, Equatable {
        let id: String
        let number: Int?
        let title: String
        let artist: String?
        let duration: Double?
        let albumId: String
    }

    struct LocalTrack: Decodable, Equatable {
        let id: String
        let filePath: String
    }

    struct Item: Decodable, Identifiable {
        let position: Int
        let albumId: String?
        let albumTitle: String?
        let albumArtist: String?
        let hasLyrics: Bool
        let hasChords: Bool
        let localTrack: LocalTrack?
        let song: WrittenSong

        var id: String { song.id }

        var durationLabel: String? {
            guard let duration = song.duration, duration > 0 else { return nil }
            let total = Int(duration.rounded())
            return String(format: "%d:%02d", total / 60, total % 60)
        }
    }

    let list: Info
    let items: [Item]
}

struct SongListsResponse: Decodable {
    let data: [SongListSummary]
}
