import SwiftUI

/// Escolhe uma playlist existente para a música atual. Não cria playlists.
struct AddToListSheet: View {
    let songId: String
    let onAdded: (String) -> Void

    @EnvironmentObject private var session: Session
    @Environment(\.dismiss) private var dismiss

    @State private var lists: [SongListSummary] = []
    @State private var isLoading = true
    @State private var loadError: String?
    @State private var addError: String?
    @State private var addingTo: String?

    var body: some View {
        NavigationView {
            content
                .navigationTitle("Adicionar à playlist")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Fechar") { dismiss() }
                    }
                }
                .task { await load() }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView("Carregando playlists…")
        } else if let loadError {
            VStack(spacing: 10) {
                Text(loadError)
                    .foregroundColor(.zinc400)
                    .multilineTextAlignment(.center)
                Button("Tentar novamente") {
                    Task { await load() }
                }
            }
            .padding(32)
        } else if lists.isEmpty {
            Text("Você ainda não tem playlists de músicas.")
                .foregroundColor(.zinc400)
                .multilineTextAlignment(.center)
                .padding(32)
        } else {
            List {
                if let addError {
                    Text(addError)
                        .font(.footnote)
                        .foregroundColor(.orange)
                }

                ForEach(lists) { list in
                    Button {
                        Task { await add(to: list) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                    .foregroundColor(.primary)
                                Text("\(list.itemCount) música(s)")
                                    .font(.caption)
                                    .foregroundColor(.zinc400)
                            }

                            Spacer()

                            if addingTo == list.id {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(addingTo != nil)
                }
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil

        do {
            let all: [SongListSummary] = try await session.authorized { client, token in
                try await client.songLists(token: token)
            }
            lists = all.filter { $0.system != true }
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
    }

    private func add(to list: SongListSummary) async {
        addingTo = list.id
        addError = nil
        defer { addingTo = nil }

        do {
            try await session.authorized { client, token in
                try await client.addSong(songId, toList: list.id, token: token)
            }
            onAdded(list.name)
            dismiss()
        } catch {
            if let apiError = error as? APIError, case .http(409, _) = apiError {
                addError = "Esta música já está em \(list.name)."
            } else {
                addError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
