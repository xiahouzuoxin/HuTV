import SwiftUI

struct DoubanPosterView: View {
    let url: URL?
    @State private var image: UIImage?

    var body: some View {
        Rectangle().fill(.quaternary)
            .aspectRatio(2.0 / 3.0, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    Group {
                        if let image { Image(uiImage: image).resizable().scaledToFill() }
                        else { Image(systemName: "film").font(.title2).foregroundStyle(.secondary) }
                    }.frame(width: geometry.size.width, height: geometry.size.height)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
            .task(id: url) {
                image = nil
                guard let url else { return }
                let loaded = try? await DoubanPosterLoader.shared.image(for: url)
                guard !Task.isCancelled else { return }
                image = loaded
            }
    }
}
