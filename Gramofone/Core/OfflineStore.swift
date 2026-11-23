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

extension OfflineAlbum {
    private enum CodingKeys: String, CodingKey {
        case albumId, title, artist, year, savedAt, tracks
    }

    /// Uma faixa malformada é descartada sozinha; o resto do álbum continua disponível.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        albumId = try container.decode(String.self, forKey: .albumId)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        savedAt = try container.decode(Date.self, forKey: .savedAt)
        tracks = try container.decode([LossyOfflineTrack].self, forKey: .tracks).compactMap(\.track)
    }
}

private struct LossyOfflineTrack: Decodable {
    let track: OfflineTrack?

    init(from decoder: Decoder) throws {
        track = try? OfflineTrack(from: decoder)
    }
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

    /// Pastas com `manifest.json` que não decodifica. Os arquivos continuam no disco:
    /// o app não apaga nada automaticamente, só avisa.
    static func unreadableCount() -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        return entries.filter { entry in
            guard let data = try? Data(contentsOf: entry.appendingPathComponent("manifest.json")) else {
                return false
            }
            return (try? JSONDecoder().decode(OfflineAlbum.self, from: data)) == nil
        }.count
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
