import Foundation

enum AppMaintenance {
    static let didReset = Notification.Name("HuTV.didReset")
    static let preferenceKeys = [
        "playback.engine", "playback.autoAdvance", "playback.forwardBufferSeconds",
        "playback.volume", "playback.rate", "playback.scaling",
        "subscriptions.autoRefresh", "subscriptions.refreshHours", "search.concurrency"
    ]
    static func resetPreferences(defaults: UserDefaults = .standard) {
        for key in preferenceKeys { defaults.removeObject(forKey: key) }
    }
    static func cacheBytes(cache: URLCache = .shared) -> Int {
        cache.currentDiskUsage + cache.currentMemoryUsage
    }
    static func clearCache(cache: URLCache = .shared) { cache.removeAllCachedResponses() }
}
