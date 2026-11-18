import Foundation

/// Configurações persistidas (por enquanto só o endereço do servidor).
enum Settings {
    private static let serverURLKey = "gramofone.serverURL"

    /// Padrão da instância da casa; o usuário pode trocar na tela de login.
    static let defaultServerURL = "http://192.168.0.100:8998"

    static var serverURL: String {
        get { UserDefaults.standard.string(forKey: serverURLKey) ?? defaultServerURL }
        set { UserDefaults.standard.set(newValue, forKey: serverURLKey) }
    }
}
