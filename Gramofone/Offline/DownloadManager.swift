import Foundation

/// Baixa álbuns para `Documents/albums/<albumId>/` (faixas + capa + manifesto).
@MainActor
final class DownloadManager: ObservableObject {
    struct Progress: Equatable {
        var done: Int
        var total: Int
        var error: String?
    }

    @Published private(set) var progress: [String: Progress] = [:]
    @Published private(set) var downloaded: Set<String> = []

    private var session: Session?
    private var tasks: [String: Task<Void, Never>] = [:]
    /// Tentativa atual de cada álbum: uma tarefa cancelada não pode mexer no progresso,
    /// no manifesto ou na tarefa de uma nova tentativa do mesmo álbum.
    private var runs: [String: UUID] = [:]

    func configure(session: Session) {
        self.session = session
        refresh()
    }

    func refresh() {
        downloaded = Set(OfflineStore.all().map(\.albumId))
    }

    func isDownloading(_ albumId: String) -> Bool {
        progress[albumId] != nil && tasks[albumId] != nil
    }

    func download(album: AlbumDetail) {
        let albumId = album.album.id
        guard tasks[albumId] == nil else { return }

        let playable = album.tracks.filter { $0.filePath != nil }
        guard !playable.isEmpty else {
            progress[albumId] = Progress(done: 0, total: 0, error: "Nenhuma faixa disponível no servidor.")
            return
        }

        progress[albumId] = Progress(done: 0, total: playable.count, error: nil)

        let run = UUID()
        runs[albumId] = run

        tasks[albumId] = Task { [weak self] in
            guard let self else { return }
            defer { self.finish(albumId, run: run) }

            do {
                try Task.checkCancellation()
                try FileManager.default.createDirectory(
                    at: OfflineStore.albumDirectory(albumId),
                    withIntermediateDirectories: true
                )

                var offlineTracks: [OfflineTrack] = []

                for (offset, track) in playable.enumerated() {
                    try Task.checkCancellation()

                    guard let filePath = track.filePath else { continue }
                    guard let url = self.session?.client?.mediaURL(path: filePath) else {
                        throw URLError(.badURL)
                    }

                    let fileName = Self.fileName(for: track, filePath: filePath)
                    let destination = OfflineStore.albumDirectory(albumId).appendingPathComponent(fileName)

                    let (temporary, response) = try await URLSession.shared.download(from: url)
                    try Task.checkCancellation()

                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw URLError(.badServerResponse)
                    }

                    try? FileManager.default.removeItem(at: destination)
                    try FileManager.default.moveItem(at: temporary, to: destination)

                    offlineTracks.append(
                        OfflineTrack(
                            trackId: track.id,
                            songId: track.songId,
                            number: track.number,
                            title: track.title,
                            artist: track.artist,
                            duration: track.duration,
                            fileName: fileName
                        )
                    )

                    if self.runs[albumId] == run {
                        self.progress[albumId]?.done = offset + 1
                    }
                }

                await self.saveCover(for: album, albumId: albumId)
                try Task.checkCancellation()

                let manifest = OfflineAlbum(
                    albumId: albumId,
                    title: album.album.title,
                    artist: album.album.artist,
                    year: album.album.year,
                    savedAt: Date(),
                    tracks: offlineTracks
                )

                try OfflineStore.save(manifest)
                self.downloaded.insert(albumId)
                self.progress[albumId] = nil
            } catch is CancellationError {
                // Removido pelo usuário durante o download: nada a reportar.
            } catch {
                if self.runs[albumId] == run {
                    self.progress[albumId]?.error = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                }
            }
        }
    }

    private func finish(_ albumId: String, run: UUID) {
        guard runs[albumId] == run else { return }
        runs[albumId] = nil
        tasks[albumId] = nil
    }

    func remove(albumId: String) {
        tasks[albumId]?.cancel()
        tasks[albumId] = nil
        runs[albumId] = nil
        progress[albumId] = nil

        OfflineStore.remove(albumId)
        downloaded.remove(albumId)
    }

    func removeAll() {
        for albumId in downloaded {
            remove(albumId: albumId)
        }
    }

    var totalBytesLabel: String {
        let bytes = OfflineStore.all().reduce(0) { $0 + Self.directorySize(for: $1.albumId) }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private func saveCover(for album: AlbumDetail, albumId: String) async {
        guard album.album.hasCachedCover, let client = session?.client else { return }
        let url = client.coverURL(albumId: albumId)
        guard let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty else { return }
        try? data.write(
            to: OfflineStore.albumDirectory(albumId).appendingPathComponent("cover.jpg"),
            options: .atomic
        )
    }

    private static func fileName(for track: Track, filePath: String) -> String {
        let ext = (filePath as NSString).pathExtension.lowercased()
        let suffix = ext.isEmpty ? "mp3" : ext

        let prefix = track.number.map { String(format: "%02d - ", $0) } ?? ""
        let safeTitle = track.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(110)

        return "\(prefix)\(safeTitle).\(suffix)"
    }

    private static func directorySize(for albumId: String) -> Int {
        let directory = OfflineStore.albumDirectory(albumId)
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }

        return files.reduce(0) { total, file in
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + size
        }
    }
}
