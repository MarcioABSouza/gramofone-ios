import Foundation

/// Ponte entre o que está baixado (`OfflineAlbum`) e as telas, que trabalham
/// com `Album`/`AlbumDetail` vindos da API. Sem isso, abrir um álbum baixado
/// sem rede mostraria erro.
extension Album {
    static func from(manifest: OfflineAlbum) -> Album {
        Album(
            id: manifest.albumId,
            title: manifest.title,
            artist: manifest.artist,
            artistId: nil,
            year: manifest.year,
            genre: nil,
            coverUrl: nil,
            types: [],
            isSuggestion: false,
            availableLocally: true,
            localCoverPath: nil,
            localTrackCount: manifest.tracks.count,
            catalogTrackCount: nil,
            isFavorite: false,
            hasCachedCover: OfflineStore.coverFile(manifest.albumId) != nil,
            coverVersion: nil,
            isComplete: true
        )
    }
}

extension OfflineAlbum {
    var asDetail: AlbumDetail {
        AlbumDetail(
            album: .from(manifest: self),
            localAlbumId: nil,
            trackSource: "local",
            tracks: tracks.map { track in
                Track(
                    id: track.trackId,
                    number: track.number,
                    title: track.title,
                    artist: track.artist,
                    duration: track.duration,
                    filePath: track.fileName,
                    songId: track.songId,
                    hasLyrics: false,
                    hasChords: false
                )
            },
            userStatus: nil
        )
    }

    /// Todas as faixas baixadas, na ordem do álbum.
    var queueItems: [QueueItem] {
        tracks.map { track in
            QueueItem(
                trackId: track.trackId,
                songId: track.songId,
                albumId: albumId,
                albumTitle: title,
                title: track.title,
                artist: track.artist ?? artist,
                duration: track.duration,
                filePath: track.fileName,
                number: track.number
            )
        }
    }
}
