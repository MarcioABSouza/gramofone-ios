import SwiftUI

/// Contêiner da área logada: biblioteca + mini player + player em tela cheia.
struct MainView: View {
    @EnvironmentObject private var player: PlayerController

    var body: some View {
        LibraryView()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if player.hasQueue {
                    MiniPlayer()
                }
            }
            .fullScreenCover(isPresented: $player.isExpanded) {
                PlayerView()
            }
    }
}
