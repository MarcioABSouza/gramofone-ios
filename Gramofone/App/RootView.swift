import SwiftUI

struct RootView: View {
    @EnvironmentObject private var session: Session
    @EnvironmentObject private var player: PlayerController
    @EnvironmentObject private var downloads: DownloadManager
    @EnvironmentObject private var scrobbles: ScrobbleQueue
    @EnvironmentObject private var network: NetworkMonitor

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView("Abrindo…")
            case .signedOut(let message):
                LoginView(initialMessage: message)
            case .signedIn:
                MainView()
            }
        }
        .task {
            // A sessão vem primeiro: o player precisa do client para montar as
            // URLs de streaming ao restaurar a fila.
            scrobbles.configure(session: session)
            downloads.configure(session: session)
            await session.restoreOnce()
            player.configure(session: session, scrobbles: scrobbles, network: network)
            await scrobbles.flush()
        }
        .onChange(of: network.isOnline) { online in
            if online {
                Task { await scrobbles.flush() }
            }
        }
    }
}
