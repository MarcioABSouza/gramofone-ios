import Foundation

/// Fila local de scrobbles: grava em `Documents/scrobble-queue.json`, tenta enviar
/// ao voltar a rede e só remove o item depois de um 2xx (o backend é idempotente
/// por `playId`, então reenviar é seguro).
@MainActor
final class ScrobbleQueue: ObservableObject {
    struct Pending: Codable, Identifiable, Equatable {
        let playId: String
        let title: String
        let artist: String?
        let album: String?
        let duration: Int
        let startedAt: Int

        var id: String { playId }
    }

    @Published private(set) var pending: [Pending] = []

    private var session: Session?
    private var isFlushing = false
    private var autoFlushTimer: Timer?
    private let fileURL: URL

    init() {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        fileURL = base.appendingPathComponent("scrobble-queue.json")
        load()
    }

    func configure(session: Session) {
        self.session = session
    }

    var count: Int { pending.count }

    /// Rede móvel/LAN pode reconectar sem o iOS entregar o evento de caminho:
    /// um tick de 60 s garante que a fila não fique presa.
    func startAutoFlush() {
        guard autoFlushTimer == nil else { return }

        autoFlushTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.flush()
            }
        }
    }

    /// Enfileira uma ouvida (idempotente por `playId`).
    func enqueue(
        title: String,
        artist: String?,
        album: String?,
        duration: Double,
        startedAt: Date,
        playId: String
    ) {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        guard !pending.contains(where: { $0.playId == playId }) else { return }

        let item = Pending(
            playId: playId,
            title: title,
            artist: artist,
            album: album,
            duration: max(1, Int(duration.rounded())),
            startedAt: Int(startedAt.timeIntervalSince1970)
        )

        pending.append(item)
        save()
        Task { await flush() }
    }

    /// Envia em ordem; para no primeiro erro que valha retry (rede/5xx/429).
    func flush() async {
        guard !isFlushing, !pending.isEmpty else { return }
        guard let session, case .signedIn = session.state else { return }

        isFlushing = true
        defer { isFlushing = false }

        for item in pending {
            do {
                let body = APIClient.ScrobbleBody(
                    title: item.title,
                    artist: item.artist,
                    album: item.album,
                    duration: item.duration,
                    playId: item.playId,
                    startedAt: item.startedAt
                )

                // `queued: false` = o backend recusou de forma definitiva
                // (faixa curta, timestamp velho, duplicado): não insiste.
                _ = try await session.authorized { client, token in
                    try await client.scrobble(token: token, body: body)
                }
                remove(item)
            } catch let error as APIError where error.isUnauthorized {
                break
            } catch let error as APIError {
                if case .http(let status, _) = error, (400..<500).contains(status), status != 429 {
                    // recusa definitiva do backend: descarta para não travar a fila
                    remove(item)
                    continue
                }
                break
            } catch {
                break
            }
        }
    }

    private func remove(_ item: Pending) {
        pending.removeAll { $0.playId == item.playId }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let items = try? JSONDecoder().decode([Pending].self, from: data)
        else {
            return
        }

        pending = items
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
