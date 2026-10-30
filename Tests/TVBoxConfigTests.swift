import XCTest
@testable import HuTV

final class TVBoxConfigTests: XCTestCase {
    func testWrappedConfigWithCommentsAndTrailingCommas() throws {
        let json = #"""
        {
          // A disabled source must not be imported.
          // {"key":"disabled","api":"csp_Disabled","type":3},
          "sites": [{"key":"spider","api":"csp_Demo","type":3,
            "ext":"https://example.com/a//b?value=/*keep*/",},],
          /* other settings */ "lives": [],
        }
        """#
        var wrapped = Data([0xFF, 0xD8, 0x00, 0xFF, 0xD9])
        wrapped.append(Data(("tag**" + Data(json.replacingOccurrences(of: "\n", with: "\r\n").utf8).base64EncodedString()).utf8))
        let config = try TVBoxConfigDecoder().decode(wrapped)
        XCTAssertEqual(config.sites.map(\.key), ["spider"])
        XCTAssertEqual(config.sites.first?.runtime, .gatewayRequired)
        XCTAssertEqual(config.sites.first?.ext, .string("https://example.com/a//b?value=/*keep*/"))
    }

    func testDecoderPreservesEscapedStringsAndBOM() throws {
        let json = #"{"sites":[{"key":"a","type":1,"api":"https://example.com/api","ext":"quote: \" // text"}]}"#
        let config = try TVBoxConfigDecoder().decode(Data(("\u{FEFF}" + json).utf8))
        XCTAssertEqual(config.sites.first?.ext, .string("quote: \" // text"))
    }

    func testDecoderRejectsHTMLBrokenWrappersAndUnterminatedComments() {
        for data in [Data("<html>navigation</html>".utf8),
                     Data([0xFF, 0xD8, 0xFF, 0xD9]) + Data("tag**???".utf8),
                     Data("{ /* unfinished".utf8)] {
            XCTAssertThrowsError(try TVBoxConfigDecoder().decode(data))
        }
    }

    func testLossySitesKeepValidEntriesAndAcceptStringNumbers() throws {
        let json = #"""
        {
          "sites": [
            {"key":"cms","name":"CMS","type":"1","api":"https://example.com/api.php","searchable":"1"},
            {"name":"broken","type":1}
          ],
          "lives": [{"name":"直播","url":"https://example.com/live.txt"}]
        }
        """#.data(using: .utf8)!

        let config = try JSONDecoder().decode(TVBoxConfig.self, from: json)
        XCTAssertEqual(config.sites.count, 1)
        XCTAssertEqual(config.sites[0].type, 1)
        XCTAssertEqual(config.sites[0].runtime, .nativeAPI)
        XCTAssertEqual(config.lives.count, 1)
    }

    func testM3UHeadersAndTVBoxNamedLines() throws {
        let m3u = """
        #EXTM3U
        #EXTINF:-1 group-title="新闻",CCTV 1
        #EXTVLCOPT:http-user-agent=TVBoxTest
        #EXTHTTP:{"Referer":"https://example.com/"}
        https://media.example.com/live.m3u8
        """
        let channels = LivePlaylistLoader().parseM3U(m3u)
        XCTAssertEqual(channels.first?.streams.first?.headers["User-Agent"], "TVBoxTest")
        XCTAssertEqual(channels.first?.streams.first?.headers["Referer"], "https://example.com/")

        let text = "央视频道,#genre#\nCCTV 1,https://a.example/live.m3u8$主线#https://b.example/live.m3u8|User-Agent=TVBox%20iOS"
        let tvbox = LivePlaylistLoader().parseTVBoxText(text)
        XCTAssertEqual(tvbox.first?.streams.count, 2)
        XCTAssertEqual(tvbox.first?.streams.first?.name, "主线")
        XCTAssertEqual(tvbox.first?.streams.last?.headers["User-Agent"], "TVBox iOS")
    }

    func testTypeZeroIsNotClaimedAsJSONNativeAndFragmentsStayIntact() throws {
        let data = #"{"sites":[{"key":"xml","name":"XML","type":0,"api":"https://example.com/api"}]}"#.data(using: .utf8)!
        let config = try JSONDecoder().decode(TVBoxConfig.self, from: data)
        XCTAssertEqual(config.sites.first?.runtime, .unsupported)

        let text = "频道,#genre#\n测试,https://a.example/live.m3u8#token-fragment#https://b.example/live.m3u8"
        let channel = LivePlaylistLoader().parseTVBoxText(text).first
        XCTAssertEqual(channel?.streams.count, 2)
        XCTAssertEqual(channel?.streams.first?.url.fragment, "token-fragment")
    }
}
