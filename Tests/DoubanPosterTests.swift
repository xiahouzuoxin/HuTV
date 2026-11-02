import XCTest
import UIKit
@testable import HuTV

private actor PosterClient: HTTPDataLoading {
    let data: Data
    let mime: String
    private(set) var calls = 0
    private(set) var request: URLRequest?
    init(data: Data, mime: String) { self.data = data; self.mime = mime }
    func data(for request: URLRequest, maximumBytes: Int, additionalValidStatusCodes: Set<Int>) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        self.request = request
        return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": mime])!)
    }
}
final class DoubanPosterTests: XCTestCase {
    @MainActor func testHeadersDownsamplingAndCache() async throws {
        let data = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 900)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 600, height: 900))
        }.pngData()!
        let client = PosterClient(data: data, mime: "image/png")
        let loader = DoubanPosterLoader(client: client)
        let url = URL(string: "https://img3.doubanio.com/test.png")!
        let image = try await loader.image(for: url)
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 512)
        _ = try await loader.image(for: url)
        let count = await client.calls
        let request = await client.request
        XCTAssertEqual(count, 1)
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Referer"), "https://movie.douban.com/")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "User-Agent"), "Mozilla/5.0")
    }
    func testHTMLAndBrokenImageAreRejected() async {
        for mime in ["text/html", "image/jpeg"] {
            let loader = DoubanPosterLoader(client: PosterClient(data: Data("<script>verification</script>".utf8), mime: mime))
            do {
                _ = try await loader.image(for: URL(string: "https://img9.doubanio.com/test.jpg")!)
                XCTFail("A status 200 verification page must not be accepted as an image")
            } catch { }
        }
    }
}
