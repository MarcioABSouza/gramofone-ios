import SwiftUI

struct RootView: View {
    @StateObject private var session = Session()

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView("Abrindo…")
            case .signedOut(let message):
                LoginView(session: session, initialMessage: message)
            case .signedIn(let user):
                HomeView(session: session, user: user)
            }
        }
        .task { await session.restoreOnce() }
    }
}

struct RootView_Previews: PreviewProvider {
    static var previews: some View {
        RootView()
            .preferredColorScheme(.dark)
    }
}
