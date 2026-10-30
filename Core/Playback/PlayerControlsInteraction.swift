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
