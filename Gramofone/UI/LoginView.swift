import SwiftUI

struct LoginView: View {
    @ObservedObject var session: Session
    let initialMessage: String?

    @State private var serverURL: String = Settings.serverURL
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var error: String?
    @State private var notice: String?
    @State private var isBusy = false
    @State private var isTesting = false
    @State private var needsSetup = false

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("http://192.168.0.100:8998", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    Button {
                        Task { await testServer() }
                    } label: {
                        HStack {
                            Text("Testar servidor")
                            Spacer()
                            if isTesting { ProgressView() }
                        }
                    }
                    .disabled(isTesting)
                } header: {
                    Text("Servidor")
                } footer: {
                    if let notice {
                        Text(notice)
                    } else if needsSetup {
                        Text("Este servidor ainda não tem usuário. Faça o setup pelo navegador antes de entrar.")
                    } else {
                        Text("Endereço do Gramofone na sua rede, sem /api no final.")
                    }
                }

                Section {
                    TextField("voce@exemplo.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)

                    SecureField("Senha", text: $password)
                        .textContentType(.password)
                } header: {
                    Text("Conta")
                }

                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Text("Entrar").bold()
                            Spacer()
                            if isBusy { ProgressView() }
                        }
                    }
                    .disabled(isBusy || email.isEmpty || password.isEmpty)
                    .listRowBackground(Color.brand.opacity(0.18))
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }

                Section {
                    Text("Gramofone iOS 0.2.0 — fase 1")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Gramofone")
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            if error == nil { error = initialMessage }
            Task { await loadConfig() }
        }
    }

    private func signIn() async {
        isBusy = true
        error = nil

        do {
            try await session.login(serverURL: serverURL, email: email, password: password)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isBusy = false
    }

    private func testServer() async {
        isTesting = true
        notice = nil
        error = nil

        do {
            let client = try APIClient(serverURL: serverURL)
            let health = try await client.health()
            notice = "\(health.service) respondeu ok (uptime \(Int(health.uptime.rounded())) s)"
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isTesting = false
    }

    private func loadConfig() async {
        guard let client = try? APIClient(serverURL: serverURL) else { return }

        if let config = try? await client.authConfig() {
            needsSetup = config.needsSetup
        }
    }
}
