import Foundation

struct Album: Decodable, Identifiable, Equatable {
    let id: String
    let title: String
    let artist: String?
    let artistId: String?
    let year: Int?
    let genre: String?
    let coverUrl: String?
    let types: [String]
    let isSuggestion: Bool
    let availableLocally: Bool
    let localCoverPath: String?
    let localTrackCount: Int?
    let catalogTrackCount: Int?
    let isFavorite: Bool
    let hasCachedCover: Bool
    let coverVersion: String?
    let isComplete: Bool

    /// Subtítulo do card/detalhe.
    var trackCountLabel: String {
        if let local = localTrackCount, local > 0 { return "\(local) faixas no servidor" }
        if let catalog = catalogTrackCount, catalog > 0 { return "\(catalog) faixas no catálogo" }
        return "sem faixas"
    }

    /// "1997 · EP" quando houver.
    var yearAndTypes: String {
        var parts: [String] = []
        if let year { parts.append(String(year)) }
        parts.append(contentsOf: types)
        return parts.joined(separator: " · ")
    }
}

struct AlbumPage: Decodable {
    let data: [Album]
    let total: Int
    let localTotal: Int?
}

struct AlbumDetail: Decodable {
    let album: Album
    let localAlbumId: String?
    let trackSource: String
    let tracks: [Track]
    let userStatus: UserStatus?

    var isLocal: Bool { trackSource == "local" }
}

struct Track: Decodable, Identifiable, Equatable {
    let id: String
    let number: Int?
    let title: String
    let artist: String?
    let duration: Int?
    let filePath: String?
    let songId: String?
    let hasLyrics: Bool
    let hasChords: Bool

    var isPlayable: Bool { filePath != nil }

    var durationLabel: String? {
        guard let duration, duration > 0 else { return nil }
        return String(format: "%d:%02d", duration / 60, duration % 60)
    }
}

struct UserStatus: Decodable {
    let rating: Int?
    let isFavorite: Bool
    let note: String?
}
