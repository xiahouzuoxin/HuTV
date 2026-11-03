import SwiftUI

enum PlayerControlsInteraction {
    case activity, began, ended
}

private struct PlayerControlsInteractionKey: EnvironmentKey {
    static let defaultValue: (PlayerControlsInteraction) -> Void = { _ in }
}

extension EnvironmentValues {
    var playerControlsInteraction: (PlayerControlsInteraction) -> Void {
        get { self[PlayerControlsInteractionKey.self] }
        set { self[PlayerControlsInteractionKey.self] = newValue }
    }
}

private struct PlayerFullscreenKey: EnvironmentKey {
    static let defaultValue = true
}
private struct PlayerToggleFullscreenKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}
extension EnvironmentValues {
    var playerFullscreen: Bool {
        get { self[PlayerFullscreenKey.self] }
        set { self[PlayerFullscreenKey.self] = newValue }
    }
    var playerToggleFullscreen: () -> Void {
        get { self[PlayerToggleFullscreenKey.self] }
        set { self[PlayerToggleFullscreenKey.self] = newValue }
    }
}

private struct PlayerReloadRevisionKey: EnvironmentKey { static let defaultValue = 0 }
extension EnvironmentValues {
    var playerReloadRevision: Int {
        get { self[PlayerReloadRevisionKey.self] }
        set { self[PlayerReloadRevisionKey.self] = newValue }
    }
}

private struct PlayerLockedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var playerLocked: Bool {
        get { self[PlayerLockedKey.self] }
        set { self[PlayerLockedKey.self] = newValue }
    }
}
