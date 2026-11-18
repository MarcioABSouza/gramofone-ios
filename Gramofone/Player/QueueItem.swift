import Foundation

/// Faixa na fila do player (persistida em `Documents/queue.json`).
struct QueueItem: Codable, Identifiable, Equatable {
    let trackId: String
    let songId: String?
    let albumId: String?
    let albumTitle: String?
    let title: String
    let artist: String?
    let duration: Double?
    let filePath: String?
    let number: Int?

    var id: String { trackId }

    init(
        trackId: String,
        songId: String?,
        albumId: String?,
        albumTitle: String?,
        title: String,
        artist: String?,
        duration: Double?,
        filePath: String?,
        number: Int?
    ) {
        self.trackId = trackId
        self.songId = songId
        self.albumId = albumId
        self.albumTitle = albumTitle
        self.title = title
        self.artist = artist
        self.duration = duration
        self.filePath = filePath
        self.number = number
    }

    init(track: Track, album: Album) {
        self.init(
            trackId: track.id,
            songId: track.songId,
            albumId: album.id,
            albumTitle: album.title,
            title: track.title,
            artist: track.artist ?? album.artist,
            duration: track.duration,
            filePath: track.filePath,
            number: track.number
        )
    }
}
