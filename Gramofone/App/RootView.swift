import SwiftUI

/// Fase 0 — valida a cadeia inteira (CI → IPA → TrollStore → rede): só testa o servidor.
struct RootView: View {
    private enum Status: Equatable {
        case idle
        case loading
        case ok(String)
        case failure(String)
    }

    @State private var serverURL: String = Settings.serverURL
    @State private var status: Status = .idle

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("http://192.168.0.100:8998", text: $serverURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onChange(of: serverURL) { _ in
                            status = .idle
                        }
                } header: {
                    Text("Servidor")
                } footer: {
                    Text("Endereço do Gramofone na sua rede, sem /api no final.")
                }

                Section {
                    Button {
                        Task { await testConnection() }
                    } label: {
                        HStack {
                            Text("Testar conexão")
                            Spacer()
                            if case .loading = status {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoading)
                }

                Section("Resultado") {
                    switch status {
                    case .idle:
                        Text("Ainda não testado.")
                            .foregroundColor(.secondary)
                    case .loading:
                        Text("Conectando…")
                            .foregroundColor(.secondary)
                    case .ok(let message):
                        Label(message, systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    case .failure(let message):
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }

                Section("Gramofone iOS 0.1.0 — fase 0") {
                    Text("Próximas fases: login, biblioteca, player, download offline e fila de scrobble.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Gramofone")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var isLoading: Bool {
        if case .loading = status { return true }
        return false
    }

    private func testConnection() async {
        status = .loading

        do {
            let client = try APIClient(serverURL: serverURL)
            let health = try await client.health()
            let uptime = Int(health.uptime.rounded())
            Settings.serverURL = serverURL
            status = .ok("\(health.service) respondeu ok (uptime \(uptime) s)")
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            status = .failure(message)
        }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
    }
}
