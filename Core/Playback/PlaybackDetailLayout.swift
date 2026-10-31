import SwiftUI

/// Keeps the player and the original detail list mounted while changing their layout.
struct PlaybackDetailLayout<Player: View, Detail: View>: View {
    let isPlaying: Bool
    @Binding var fullscreen: Bool
    @ViewBuilder let player: () -> Player
    @ViewBuilder let detail: () -> Detail

    var body: some View {
        GeometryReader { geometry in
            let landscape = geometry.size.width > geometry.size.height
            VStack(spacing: 0) {
                if isPlaying {
                    player()
                        .frame(width: geometry.size.width,
                               height: fullscreen ? geometry.size.height : min(geometry.size.height * 0.55, max(240, geometry.size.width * 9 / 16)))
                        .clipped()
                }
                detail()
                    .frame(width: geometry.size.width,
                           height: isPlaying && fullscreen ? 0 : nil)
                    .opacity(isPlaying && fullscreen ? 0 : 1)
                    .allowsHitTesting(!isPlaying || !fullscreen)
                    .accessibilityHidden(isPlaying && fullscreen)
            }
            .onChange(of: landscape) { wasLandscape, isLandscape in
                if isPlaying && !wasLandscape && isLandscape { fullscreen = true }
            }
        }
    }
}
