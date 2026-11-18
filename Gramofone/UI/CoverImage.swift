import SwiftUI

/// Capa do álbum servida pelo backend (`/api/covers/:id`), com placeholder
/// enquanto carrega e quando o álbum não tem capa em cache.
struct CoverImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.15))) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .failure:
                placeholder
            case .empty:
                placeholder.opacity(0.45)
            @unknown default:
                placeholder
            }
        }
        .background(Color.zinc800)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            Color.zinc800
            Image(systemName: "opticaldisc")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.zinc500)
        }
    }
}

