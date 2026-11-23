import SwiftUI

/// Conta e sessão (folha aberta pelo botão de perfil na Biblioteca).
struct AccountView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var scrobbles: ScrobbleQueue

    @Environment(\.dismiss) private var dismiss
    @State private var isSigningOut = false
    @State private var isFlushing = false
    @State private var confirmRemoveAll = false

    var body: some View {
        NavigationView {
            List {
                if let user = session.currentUser {
                    Section("Sessão") {
                        row("Usuário", user.name ?? user.email)
                        row("E-mail", user.email)
                        row("Papel", user.role == "manager" ? "manager (admin)" : "viewer")
                        row("Servidor", session.serverURL)
                    }

                    Section("Last.fm") {
                        row("Conta", user.lastfmUsername ?? "não conectada")
                        row("Scrobble", user.lastfmConfigured ? "configurado" : "não configurado")
                        row("Na fila", "\(scrobbles.count) pendente(s)")

                        Button {
                            Task {
                                isFlushing = true
                                await scrobbles.flush()
                                isFlushing = false
                            }
                        } label: {
                            HStack {
                                Text("Enviar scrobbles agora")
                                Spacer()
                                if isFlushing { ProgressView() }
                            }
                        }
                        .disabled(isFlushing || scrobbles.count == 0)
                    }
                }

                Section("Offline") {
                    row("Álbuns baixados", "\(downloads.downloaded.count)")
                    row("Espaço usado", downloads.totalBytesLabel)

                    if unreadableCount > 0 {
                        row("Manifestos ilegíveis", "\(unreadableCount)")
                    }

                    if !downloads.downloaded.isEmpty {
                        Button("Remover todos os downloads", role: .destructive) {
                            confirmRemoveAll = true
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            isSigningOut = true
                            player.stop()
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
                    Text("Gramofone iOS 0.6.0")
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
            .confirmationDialog(
                "Remover todos os downloads?",
                isPresented: $confirmRemoveAll,
                titleVisibility: .visible
            ) {
                Button("Remover tudo", role: .destructive) {
                    downloads.removeAll()
                }
                Button("Cancelar", role: .cancel) {}
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var unreadableCount: Int {
        OfflineStore.unreadableCount()
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
    }
}
