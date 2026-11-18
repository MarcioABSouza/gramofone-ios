import SwiftUI
import UIKit

/// Capa do álbum: arquivo baixado (`file://`), cache do servidor ou placeholder.
struct CoverImage: View {
    let url: URL?
    var cornerRadius: CGFloat = 8

    var body: some View {
        Group {
            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
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
            }
        }
        .background(Color.zinc800)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    private var localImage: UIImage? {
        guard let url, url.isFileURL else { return nil }
        return UIImage(contentsOfFile: url.path)
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
