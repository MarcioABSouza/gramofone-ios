import SwiftUI

/// Conta e sessão (folha aberta pelo botão de perfil na Biblioteca).
struct AccountView: View {
    @ObservedObject var session: Session
    let user: PublicUser

    @Environment(\.dismiss) private var dismiss
    @State private var isSigningOut = false

    var body: some View {
        NavigationView {
            List {
                Section("Sessão") {
                    row("Usuário", user.name ?? user.email)
                    row("E-mail", user.email)
                    row("Papel", user.role == "manager" ? "manager (admin)" : "viewer")
                    row("Servidor", session.serverURL)
                }

                Section("Last.fm") {
                    row("Conta", user.lastfmUsername ?? "não conectada")
                    row("Scrobble", user.lastfmConfigured ? "configurado" : "não configurado")
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            isSigningOut = true
                            await session.logout()
                            isSigningOut = false
                        }
                    } label: {
                        HStack {
                            Text("Sair")
                            Spacer()
                            if isSigningOut { ProgressView() }
                        }
                    }
                    .disabled(isSigningOut)
                }

                Section {
                    Text("Gramofone iOS 0.3.0 — fase 2")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Conta")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") { dismiss() }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
