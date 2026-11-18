import SwiftUI

@main
struct GramofoneApp: App {
    @StateObject private var session = Session()
    @StateObject private var player = PlayerController()
    @StateObject private var downloads = DownloadManager()
    @StateObject private var scrobbles = ScrobbleQueue()
    @StateObject private var network = NetworkMonitor()

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
                .environmentObject(player)
                .environmentObject(downloads)
                .environmentObject(scrobbles)
                .environmentObject(network)
                .preferredColorScheme(.dark)
                .onChange(of: scenePhase) { phase in
                    switch phase {
                    case .background:
                        // Garante a posição da fila no snapshot antes de suspender.
                        player.persistNow()
                    case .active:
                        Task { await scrobbles.flush() }
                    default:
                        break
                    }
                }
        }
    }
}
