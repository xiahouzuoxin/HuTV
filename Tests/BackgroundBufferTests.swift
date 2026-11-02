import XCTest
import UIKit
@testable import HuTV

final class BackgroundBufferTests: XCTestCase {
    @MainActor func testExpirationAndReturnReleaseEachTokenOnce() {
        var handlers: [@MainActor () -> Void] = []
        var ended: [UIBackgroundTaskIdentifier] = []
        var completions = 0
        let lease = BackgroundBufferLease(begin: { handler in
            handlers.append(handler)
            return UIBackgroundTaskIdentifier(rawValue: handlers.count)
        }, end: { ended.append($0) })
        lease.start { completions += 1 }
        lease.start { XCTFail("Duplicate start") }
        XCTAssertEqual(handlers.count, 1)
        lease.finish()
        lease.finish()
        XCTAssertEqual(ended.count, 1)
        XCTAssertEqual(completions, 1)
        lease.start { completions += 1 }
        handlers[0]() // An old expiration must not stop the new lease.
        XCTAssertTrue(lease.isActive)
        handlers[1]()
        XCTAssertFalse(lease.isActive)
        XCTAssertEqual(ended.count, 2)
        XCTAssertEqual(completions, 2)
    }

    @MainActor func testDeniedAndSynchronousExpiration() {
        var ended = 0
        var completions = 0
        let denied = BackgroundBufferLease(begin: { _ in .invalid }, end: { _ in ended += 1 })
        denied.start { completions += 1 }
        XCTAssertFalse(denied.isActive)
        XCTAssertEqual(ended, 0)
        let expired = BackgroundBufferLease(begin: { expiration in
            expiration()
            return UIBackgroundTaskIdentifier(rawValue: 1)
        }, end: { _ in ended += 1 })
        expired.start { completions += 1 }
        XCTAssertFalse(expired.isActive)
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(completions, 2)
    }

    @MainActor func testLocalTimeLimitReleasesTask() async throws {
        var ended = 0
        let lease = BackgroundBufferLease(begin: { _ in UIBackgroundTaskIdentifier(rawValue: 1) }, end: { _ in ended += 1 })
        lease.start(duration: .milliseconds(10)) {}
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(lease.isActive)
        XCTAssertEqual(ended, 1)
    }
}
