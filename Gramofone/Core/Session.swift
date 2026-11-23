import Foundation

/// Sessão do app: login, renovação do token e restauração no boot.
///
/// O access token (1 h) fica só em memória; o **refresh token** (365 dias) vai
/// para o Keychain e é rotacionado a cada renovação.
///
/// Sem rede o app entra em **sessão offline**: usa o último perfil salvo para
/// abrir a interface e tocar o que está baixado, em vez de mandar o usuário de
/// volta para o login. Nada além da UI/offline funciona até a rede voltar.
@MainActor
final class Session: ObservableObject {
    enum State: Equatable {
        case loading
        case signedOut(message: String?)
        case signedIn(PublicUser)
    }

    @Published private(set) var state: State = .loading
    @Published private(set) var serverURL: String = Settings.serverURL
    @Published private(set) var isOfflineSession = false

    private(set) var client: APIClient?
    private(set) var accessToken: String?
    private var refreshToken: String?
    private var renewTask: Task<String, Error>?
    private var didRestore = false

    private static let refreshAccount = "refresh-token"
    private static let cachedUserKey = "gramofone.cachedUser"

    var currentUser: PublicUser? {
        if case .signedIn(let user) = state { return user }
        return nil
    }

    // MARK: - Ciclo de vida

    func restoreOnce() async {
        guard !didRestore else { return }
        didRestore = true
        await restore()
    }

    /// Chamado quando a rede volta: valida a sessão que abriu em modo offline.
    func revalidate() async {
        guard isOfflineSession else { return }
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

        // Mantém o refresh token em memória mesmo se a renovação falhar offline:
        // é com ele que a fila de scrobble volta a andar quando a rede retornar.
        refreshToken = stored

        do {
            let refreshed = try await client.refresh(refreshToken: stored)
            apply(tokens: refreshed)
            let user = try await client.me(token: refreshed.token)
            cache(user: user)
            isOfflineSession = false
            state = .signedIn(user)
        } catch let error as APIError where error.isUnauthorized {
            endExpiredSession()
        } catch {
            if let cached = cachedUser() {
                isOfflineSession = true
                state = .signedIn(cached)
            } else {
                state = .signedOut(message: error.localizedDescription)
            }
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
        cache(user: auth.user)
        isOfflineSession = false
        state = .signedIn(auth.user)
    }

    func logout() async {
        let currentRefresh = refreshToken
        let currentToken = accessToken

        await client?.logout(refreshToken: currentRefresh, token: currentToken)

        clearSession()
        removeCachedUser()
        isOfflineSession = false
        state = .signedOut(message: nil)
    }

    /// Executa uma chamada autenticada; em 401 renova a sessão e tenta de novo **uma vez**.
    func authorized<T>(_ operation: (APIClient, String) async throws -> T) async throws -> T {
        guard let client, let token = accessToken else {
            throw APIError.http(401, isOfflineSession ? "Sem conexão" : "Sessão não iniciada")
        }

        do {
            return try await operation(client, token)
        } catch let error as APIError where error.isUnauthorized {
            // Outra chamada pode ter renovado o token enquanto esta esperava.
            if let current = accessToken, current != token {
                return try await operation(client, current)
            }

            let renewed = try await renew()
            return try await operation(client, renewed)
        }
    }

    // MARK: - Interno

    /// Uma renovação por vez: chamadas concorrentes esperam a mesma. O refresh é
    /// rotativo, então dois refresh com o mesmo token fazem o backend revogar
    /// **todas** as sessões do usuário.
    private func renew() async throws -> String {
        if let renewTask {
            return try await renewTask.value
        }

        guard let client, let refresh = refreshToken else {
            throw APIError.http(401, "Sessão não iniciada")
        }

        let task = Task<String, Error> { [weak self] in
            do {
                let refreshed = try await client.refresh(refreshToken: refresh)
                self?.apply(tokens: refreshed)
                self?.isOfflineSession = false
                return refreshed.token
            } catch let error as APIError where error.isUnauthorized {
                self?.endExpiredSession()
                throw error
            }
        }

        renewTask = task
        defer { renewTask = nil }
        return try await task.value
    }

    /// Só o 401 do refresh encerra a sessão. Falha de rede mantém o usuário logado.
    private func endExpiredSession() {
        clearSession()
        removeCachedUser()
        isOfflineSession = false
        state = .signedOut(message: "Sessão expirada. Entre novamente.")
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

    // MARK: - Perfil em cache (sessão offline)

    private func cache(user: PublicUser) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: Self.cachedUserKey)
    }

    private func cachedUser() -> PublicUser? {
        guard let data = UserDefaults.standard.data(forKey: Self.cachedUserKey) else { return nil }
        return try? JSONDecoder().decode(PublicUser.self, from: data)
    }

    private func removeCachedUser() {
        UserDefaults.standard.removeObject(forKey: Self.cachedUserKey)
    }
}
