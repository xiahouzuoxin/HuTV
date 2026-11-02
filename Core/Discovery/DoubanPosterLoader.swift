import Foundation
import ImageIO
import UIKit

actor DoubanPosterLoader {
    static let shared = DoubanPosterLoader()
    private let client: any HTTPDataLoading
    private let cache = NSCache<NSURL, UIImage>()

    init(client: any HTTPDataLoading = BoundedHTTPClient()) {
        self.client = client
        cache.countLimit = 60
        cache.totalCostLimit = 12 * 1024 * 1024
    }

    func image(for url: URL) async throws -> UIImage {
        guard url.scheme == "https", let host = url.host,
              host == "doubanio.com" || host.hasSuffix(".doubanio.com") else {
            throw HTTPClientError.invalidResponse
        }
        if let image = cache.object(forKey: url as NSURL) { return image }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://movie.douban.com/", forHTTPHeaderField: "Referer")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        let (data, response) = try await client.data(for: request, maximumBytes: 2 * 1024 * 1024)
        try Task.checkCancellation()
        // Some CDN responses have status 200 but contain a verification script.
        guard response.mimeType?.hasPrefix("image/") == true,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: 512
              ] as CFDictionary) else { throw HTTPClientError.invalidResponse }
        let image = UIImage(cgImage: thumbnail)
        cache.setObject(image, forKey: url as NSURL, cost: thumbnail.bytesPerRow * thumbnail.height)
        return image
    }
}
