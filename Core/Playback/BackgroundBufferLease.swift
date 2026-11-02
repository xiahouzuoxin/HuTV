import UIKit

/// A bounded, best-effort opportunity to finish buffering, not a background download.
@MainActor
final class BackgroundBufferLease {
    typealias Begin = (@escaping @MainActor () -> Void) -> UIBackgroundTaskIdentifier
    private let begin: Begin
    private let end: (UIBackgroundTaskIdentifier) -> Void
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    private var generation = UUID()
    private var timeout: Task<Void, Never>?
    private var completion: (() -> Void)?
    var isActive: Bool { identifier != .invalid }

    init(begin: @escaping Begin = { expiration in
        UIApplication.shared.beginBackgroundTask(withName: "HuTV buffering") {
            MainActor.assumeIsolated { expiration() }
        }
    }, end: @escaping (UIBackgroundTaskIdentifier) -> Void = {
        UIApplication.shared.endBackgroundTask($0)
    }) {
        self.begin = begin; self.end = end
    }

    func start(duration: Duration = .seconds(20), onEnd: @escaping () -> Void) {
        guard !isActive else { return }
        let run = UUID()
        generation = run
        completion = onEnd
        let token = begin { [weak self] in
            guard let self, self.generation == run else { return }
            self.finish()
        }
        // Also handle an expiration invoked synchronously by a task provider.
        guard generation == run else {
            if token != .invalid { end(token) }
            return
        }
        identifier = token
        guard token != .invalid else { finish(); return }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: duration) } catch { return }
            guard let self, self.generation == run else { return }
            self.finish()
        }
    }

    func finish() {
        generation = UUID()
        timeout?.cancel(); timeout = nil
        let token = identifier
        identifier = .invalid
        let callback = completion
        completion = nil
        callback?()
        if token != .invalid { end(token) }
    }
}
