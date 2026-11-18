import Foundation

/// Sessão do app: login, renovação do token e restauração no boot.
///
/// O access token (1 h) fica só em memória; o **refresh token** (365 dias) vai
/// para o Keychain e é rotacionado a cada renovação — por isso aplicamos o novo
/// sempre que o backend responde.
@MainActor
final class Session: ObservableObject {
    enum State: Equatable {
        case loading
        case signedOut(message: String?)
        case signedIn(PublicUser)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var serverURL: String = Settings.serverURL

    var currentUser: PublicUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    private(set) var client: APIClient?
    private(set) var accessToken: String?
    private var refreshToken: String?
    private var didRestore = false

    private static let refreshAccount = "refresh-token"

    // MARK: - Ciclo de vida

    func restoreOnce() async {
        guard !didRestore else { return }
        didRestore = true
        await restore()
    }

    private func restore() async {
        guard let client = try? APIClient(serverURL: Settings.serverURL) else {
            state = .signedOut(message: "Endereço do servidor inválido. Ajuste abaixo.")
            return
        }

        self.client = client

        guard let stored = Keychain.get(Self.refreshAccount) else {
            state = .signedOut(message: nil)
            return
        }

        do {
            let refreshed = try await client.refresh(refreshToken: stored)
            apply(tokens: refreshed)
            let user = try await client.me(token: refreshed.token)
            state = .signedIn(user)
        } catch let error as APIError where error.isUnauthorized {
            clearSession()
            state = .signedOut(message: "Sessão expirada. Entre novamente.")
        } catch {
            // Servidor fora do ar: mantém o refresh token para tentar no próximo boot.
            state = .signedOut(message: error.localizedDescription)
        }
    }

    // MARK: - Ações

    func login(serverURL raw: String, email: String, password: String) async throws {
        let client = try APIClient(serverURL: raw)
        let auth = try await client.login(email: email.trimmingCharacters(in: .whitespaces), password: password)

        self.client = client
        Settings.serverURL = raw
        serverURL = raw

        apply(tokens: RefreshResponse(token: auth.token, refreshToken: auth.refreshToken))
        state = .signedIn(auth.user)
    }

    func logout() async {
        let currentRefresh = refreshToken
        let currentToken = accessToken

        await client?.logout(refreshToken: currentRefresh, token: currentToken)

        clearSession()
        state = .signedOut(message: nil)
    }

    /// Executa uma chamada autenticada; em 401 renova a sessão e tenta de novo **uma vez**.
    func authorized<T>(_ operation: (APIClient, String) async throws -> T) async throws -> T {
        guard let client, let token = accessToken else {
            throw APIError.http(401, "Sessão não iniciada")
        }

        do {
            return try await operation(client, token)
        } catch let error as APIError where error.isUnauthorized {
            let renewed = try await renew()
            return try await operation(client, renewed)
        }
    }

    // MARK: - Interno

    private func renew() async throws -> String {
        guard let client, let refresh = refreshToken else {
            throw APIError.http(401, "Sessão não iniciada")
        }

        let refreshed = try await client.refresh(refreshToken: refresh)
        apply(tokens: refreshed)
        return refreshed.token
    }

    private func apply(tokens: RefreshResponse) {
        accessToken = tokens.token
        refreshToken = tokens.refreshToken
        Keychain.set(tokens.refreshToken, for: Self.refreshAccount)
    }

    private func clearSession() {
        accessToken = nil
        refreshToken = nil
        Keychain.remove(Self.refreshAccount)
    }
}
