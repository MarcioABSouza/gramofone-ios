import Foundation

/// Usuário público devolvido por `POST /api/auth` e `GET /api/auth/me`.
struct PublicUser: Codable, Identifiable, Equatable {
    let id: String
    let name: String?
    let email: String
    let role: String
    let lastfmUsername: String?
    let lastfmConfigured: Bool
}

struct AuthResponse: Decodable {
    let token: String
    let refreshToken: String
    let user: PublicUser
}

struct RefreshResponse: Decodable {
    let token: String
    let refreshToken: String
}

struct AuthConfig: Decodable {
    let needsSetup: Bool
    let registrationEnabled: Bool
}
