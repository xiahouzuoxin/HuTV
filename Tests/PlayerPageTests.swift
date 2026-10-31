import XCTest
import SwiftUI
@testable import HuTV

@MainActor private final class PlayerPageProbe {
    var appearances = 0
    var disappearances = 0
    var height = 0.0
    var width = 0.0
    var toggle: (() -> Void)?
    var portraitRequests = 0
}
private struct PlayerPageProbeView: View {
    let probe: PlayerPageProbe
    @Environment(\.playerToggleFullscreen) private var toggle
    var body: some View {
        GeometryReader { geometry in
            Color.black
                .onAppear {
                    probe.appearances += 1
                    probe.height = geometry.size.height
                    probe.width = geometry.size.width
                    probe.toggle = toggle
                }
                .onChange(of: geometry.size) { _, value in probe.height = value.height; probe.width = value.width }
                .onDisappear { probe.disappearances += 1 }
        }
    }
}

private struct EmbeddedPlayerProbe: View {
    let probe: PlayerPageProbe
    @State private var fullscreen = true
    var size = CGSize(width: 390, height: 780)
    var body: some View {
        PlaybackDetailLayout(isPlaying: true, fullscreen: $fullscreen) {
            PlayerPage(title: "测试影片", subtitle: "第一集", kind: .onDemand,
                       onSwitchSource: {}, fullscreen: $fullscreen, onClose: {},
                       onExitFullscreen: { probe.portraitRequests += 1 }) { _ in
                PlayerPageProbeView(probe: probe)
            }
        } detail: {
            Text("原剧集详情和全部线路")
        }.frame(width: size.width, height: size.height)
    }
}

final class PlayerPageTests: XCTestCase {
    @MainActor func testFullscreenToggleKeepsPlaybackViewMounted() async throws {
        let probe = PlayerPageProbe()
        let host = UIHostingController(rootView: EmbeddedPlayerProbe(probe: probe))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 1000))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(150))
        let fullHeight = probe.height
        XCTAssertGreaterThan(fullHeight, 0)
        XCTAssertEqual(probe.appearances, 1)
        let toggle = try XCTUnwrap(probe.toggle)
        toggle()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertLessThan(probe.height, fullHeight)
        XCTAssertEqual(probe.appearances, 1)
        XCTAssertEqual(probe.disappearances, 0)
        toggle()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(probe.height, fullHeight, accuracy: 1)
        XCTAssertEqual(probe.appearances, 1)
        XCTAssertEqual(probe.disappearances, 0)
    }
    @MainActor func testExitingLandscapeRequestsPortraitWithoutCreatingSidePanel() async throws {
        let probe = PlayerPageProbe()
        let host = UIHostingController(rootView: EmbeddedPlayerProbe(probe: probe, size: CGSize(width: 800, height: 350)))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 350))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(150))
        let fullHeight = probe.height, fullWidth = probe.width
        try XCTUnwrap(probe.toggle)()
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertEqual(probe.portraitRequests, 1)
        XCTAssertLessThan(probe.height, fullHeight)
        XCTAssertEqual(probe.width, fullWidth, accuracy: 1)
        XCTAssertEqual(probe.appearances, 1)
        XCTAssertEqual(probe.disappearances, 0)
    }

    @MainActor func testRotatingInlinePlaybackToLandscapeEntersFullscreen() async throws {
        let probe = PlayerPageProbe()
        let host = UIHostingController(rootView: EmbeddedPlayerProbe(probe: probe))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 800, height: 900))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(150))
        try XCTUnwrap(probe.toggle)()
        try await Task.sleep(for: .milliseconds(150))
        host.rootView = EmbeddedPlayerProbe(probe: probe, size: CGSize(width: 800, height: 350))
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(probe.width, 800, accuracy: 1)
        XCTAssertEqual(probe.height, 350, accuracy: 1)
        XCTAssertEqual(probe.appearances, 1)
        XCTAssertEqual(probe.disappearances, 0)
    }

    @MainActor func testPortraitRequestRotatesWindowScene() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive }))
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
        for _ in 0..<60 {
            if scene.interfaceOrientation.isLandscape { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertTrue(scene.interfaceOrientation.isLandscape)
        PlaybackOrientation.returnToPortrait()
        for _ in 0..<60 {
            if scene.interfaceOrientation == .portrait { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(scene.interfaceOrientation, .portrait)
    }

}
