import Foundation

struct OfflineTrack: Codable, Identifiable {
    let trackId: String
    let songId: String?
    let number: Int?
    let title: String
    let artist: String?
    let duration: Double?
    let fileName: String

    var id: String { trackId }
}

struct OfflineAlbum: Codable, Identifiable {
    let albumId: String
    let title: String
    let artist: String?
    let year: Int?
    let savedAt: Date
    var tracks: [OfflineTrack]

    var id: String { albumId }
}

/// Álbuns baixados em `Documents/albums/<albumId>/` (+ `cover.jpg` + `manifest.json`).
enum OfflineStore {
    static var root: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("albums", isDirectory: true)
    }

    static func albumDirectory(_ albumId: String) -> URL {
        root.appendingPathComponent(albumId, isDirectory: true)
    }

    static func manifestURL(_ albumId: String) -> URL {
        albumDirectory(albumId).appendingPathComponent("manifest.json")
    }

    static func load(_ albumId: String) -> OfflineAlbum? {
        guard let data = try? Data(contentsOf: manifestURL(albumId)) else { return nil }
        return try? JSONDecoder().decode(OfflineAlbum.self, from: data)
    }

    static func all() -> [OfflineAlbum] {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return entries
            .compactMap { try? Data(contentsOf: $0.appendingPathComponent("manifest.json")) }
            .compactMap { try? JSONDecoder().decode(OfflineAlbum.self, from: $0) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    static func isDownloaded(_ albumId: String) -> Bool {
        load(albumId) != nil
    }

    static func localFile(_ albumId: String, fileName: String) -> URL? {
        let url = albumDirectory(albumId).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func coverFile(_ albumId: String) -> URL? {
        let url = albumDirectory(albumId).appendingPathComponent("cover.jpg")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func save(_ album: OfflineAlbum) throws {
        try FileManager.default.createDirectory(at: albumDirectory(album.albumId), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(album)
        try data.write(to: manifestURL(album.albumId), options: .atomic)
    }

    static func remove(_ albumId: String) {
        try? FileManager.default.removeItem(at: albumDirectory(albumId))
    }
}
