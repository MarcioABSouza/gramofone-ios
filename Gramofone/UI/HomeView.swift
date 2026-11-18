import SwiftUI

/// Placeholder da fase 1: confirma a sessão e permite sair.
/// A biblioteca e o player entram na fase 2/3.
struct HomeView: View {
    @ObservedObject var session: Session
    let user: PublicUser

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

                Section("Próximas fases") {
                    Label("Biblioteca e álbum", systemImage: "square.grid.2x2")
                    Label("Player com tela bloqueada", systemImage: "play.circle")
                    Label("Download para offline", systemImage: "arrow.down.circle")
                    Label("Fila de scrobble offline", systemImage: "arrow.triangle.2.circlepath")
                }
                .foregroundColor(.secondary)
            }
            .navigationTitle("Gramofone")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}
