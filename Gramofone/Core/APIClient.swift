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

    var isUnauthorized: Bool {
        if case .http(401, _) = self { return true }
        return false
    }

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

    // MARK: - Endpoints

    func health() async throws -> HealthResponse {
        try await get("health")
    }

    func authConfig() async throws -> AuthConfig {
        try await get("auth/config")
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        try await post("auth", body: ["email": email, "password": password])
    }

    func refresh(refreshToken: String) async throws -> RefreshResponse {
        try await post("auth/refresh", body: ["refreshToken": refreshToken], token: nil)
    }

    func me(token: String) async throws -> PublicUser {
        try await get("auth/me", token: token)
    }

    // MARK: - Biblioteca

    /// Álbuns com cópia no servidor (`local=true`), ordenados por título.
    func albums(token: String, skip: Int, take: Int, search: String) async throws -> AlbumPage {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "local", value: "true"),
            URLQueryItem(name: "sort", value: "title"),
            URLQueryItem(name: "order", value: "asc"),
            URLQueryItem(name: "skip", value: String(skip)),
            URLQueryItem(name: "take", value: String(take)),
        ]

        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty {
            query.append(URLQueryItem(name: "search", value: term))
        }

        return try await get("albums", query: query, token: token)
    }

    func album(id: String, token: String) async throws -> AlbumDetail {
        try await get("albums/" + id, token: token)
    }

    func logout(refreshToken: String?, token: String?) async {
        struct Body: Encodable { let refreshToken: String }
        struct Empty: Decodable { let message: String? }

        let body = refreshToken.map(Body.init(refreshToken:))
        _ = try? await post("auth/logout", body: body, token: token, decode: Empty.self)
    }

    // MARK: - URLs auxiliares

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

    // MARK: - Transporte

    private func get<T: Decodable>(
        _ path: String,
        query: [URLQueryItem] = [],
        token: String? = nil
    ) async throws -> T {
        try await send(method: "GET", path: path, query: query, bodyData: nil, token: token)
    }

    private func post<B: Encodable, T: Decodable>(_ path: String, body: B, token: String? = nil) async throws -> T {
        let data = try JSONEncoder().encode(body)
        return try await send(method: "POST", path: path, bodyData: data, token: token)
    }

    /// POST com corpo opcional (o logout pode ir sem refresh token).
    private func post<B: Encodable, T: Decodable>(
        _ path: String,
        body: B?,
        token: String?,
        decode: T.Type
    ) async throws -> T {
        let data = try body.map { try JSONEncoder().encode($0) }
        return try await send(method: "POST", path: path, bodyData: data, token: token)
    }

    private func send<T: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
        bodyData: Data?,
        token: String?
    ) async throws -> T {
        var components = URLComponents(
            url: apiBase.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )

        if !query.isEmpty {
            components?.queryItems = query
        }

        guard let url = components?.url else {
            throw APIError.transport("endereço inválido")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let bodyData {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = bodyData
        }

        do {
            let (data, response) = try await Self.session.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport("resposta inesperada")
            }

            guard (200..<300).contains(http.statusCode) else {
                throw APIError.http(http.statusCode, Self.message(from: data))
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
        configuration.timeoutIntervalForRequest = 20
        configuration.waitsForConnectivity = false
        configuration.httpAdditionalHeaders = ["User-Agent": "Gramofone-iOS/0.2"]
        return URLSession(configuration: configuration)
    }()

    /// Extrai `message` do corpo de erro do backend (`{ error, message }`).
    private static func message(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        if let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data), let message = payload.message {
            return message
        }

        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(160))
    }

    private struct ErrorPayload: Decodable {
        let message: String?
    }
}
