import Foundation

struct HealthResponse: Decodable {
    let ok: Bool
    let service: String
    let uptime: Double
}

enum APIError: LocalizedError {
    case invalidServerURL
    case transport(String)
    case http(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            return "Endereço inválido. Use algo como http://192.168.0.100:8998"
        case .transport(let detail):
            return "Sem conexão com o servidor. \(detail)"
        case .http(let status, let message):
            if let message, !message.isEmpty {
                return "O servidor respondeu \(status): \(message)"
            }
            return "O servidor respondeu \(status)."
        }
    }
}

/// Cliente mínimo da API do Gramofone.
///
/// O endereço guardado é a raiz do servidor (sem `/api`): o cliente acrescenta
/// `/api` nas chamadas de dados e usa a raiz para mídia (`/api/media/...`) e
/// capas (`/api/covers/...`), como o app Android faz.
final class APIClient {
    let serverURL: URL

    init(serverURL: String) throws {
        let trimmed = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmed.isEmpty,
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            throw APIError.invalidServerURL
        }

        self.serverURL = url
    }

    private var apiBase: URL {
        serverURL.appendingPathComponent("api")
    }

    func health() async throws -> HealthResponse {
        try await get(apiBase.appendingPathComponent("health"))
    }

    /// URL absoluta de um arquivo da biblioteca (`/api/media/<filePath>`).
    ///
    /// Os componentes são codificados individualmente e concatenados na string —
    /// `appendingPathComponent` com uma barra dentro codificaria `%` de novo.
    func mediaURL(path: String) -> URL? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?%#"))
        let encoded = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: allowed) ?? String($0) }
            .joined(separator: "/")

        guard !encoded.isEmpty else { return nil }

        var base = serverURL.absoluteString
        while base.hasSuffix("/") { base.removeLast() }

        return URL(string: base + "/api/media/" + encoded)
    }

    func coverURL(albumId: String) -> URL {
        serverURL.appendingPathComponent("api/covers").appendingPathComponent(albumId)
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await Self.session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("resposta inesperada")
            }

            guard (200..<300).contains(http.statusCode) else {
                throw APIError.http(http.statusCode, Self.shortBody(data))
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.transport("não entendi a resposta do servidor")
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Gramofone-iOS/0.1"]
        return URLSession(configuration: configuration)
    }()

    private static func shortBody(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(160))
    }
}
