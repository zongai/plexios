import SwiftUI

/// Async image backed by ImagePipeline (memory + disk + downsample).
struct PlexImage: View {
    let url: URL?
    var pointSize: CGSize? = nil
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                AppColors.posterPlaceholder
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard let url else {
            image = nil
            return
        }
        let loaded = await ImagePipeline.shared.image(for: url, pointSize: pointSize)
        guard !Task.isCancelled else { return }
        image = loaded
    }
}

// MARK: - URL builders

enum PlexImageURL {
    static func resolve(
        path: String?,
        baseURL: URL?,
        token: String?,
        width: Int? = nil,
        height: Int? = nil
    ) -> URL? {
        guard let path, !path.isEmpty, let baseURL else { return nil }

        // Already absolute
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)
        }

        // Use photo transcoder when size requested
        if let width, let height {
            var components = URLComponents(
                url: baseURL.appendingPathComponent("photo/:/transcode"),
                resolvingAgainstBaseURL: false
            )
            var items: [URLQueryItem] = [
                URLQueryItem(name: "url", value: path),
                URLQueryItem(name: "width", value: "\(width)"),
                URLQueryItem(name: "height", value: "\(height)"),
                URLQueryItem(name: "minSize", value: "1")
            ]
            if let token {
                items.append(URLQueryItem(name: "X-Plex-Token", value: token))
            }
            components?.queryItems = items
            return components?.url
        }

        // Direct path
        var url = baseURL
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        for segment in cleaned.split(separator: "/") {
            url = url.appendingPathComponent(String(segment))
        }
        if let token {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "X-Plex-Token", value: token)]
            return components?.url
        }
        return url
    }
}
