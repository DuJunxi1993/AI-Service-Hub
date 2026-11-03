import XCTest
@testable import AiServiceHubCore

final class WebUIURLDetectorTests: XCTestCase {
    func testAstrBotStartingWebUI() {
        let line = "[Core] [INFO] Starting WebUI at http://127.0.0.1:6185/dashboard"
        let url = WebUIURLDetector.extract(from: line, for: .astrbot)
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:6185/dashboard")
    }

    func testAstrBotLocalLine() {
        let line = "[Core] [INFO] Local: http://127.0.0.1:6185"
        let url = WebUIURLDetector.extract(from: line, for: .astrbot)
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:6185")
    }

    func testAstrBotIgnoresNetworkLine() {
        let line = "[Core] [INFO] Network: http://192.168.1.10:6185"
        XCTAssertNil(WebUIURLDetector.extract(from: line, for: .astrbot))
    }

    func testNapCatUserPanelURL() {
        let line = "[NapCat] WebUi User Panel Url: http://127.0.0.1:6099/webui?token=abc123"
        let url = WebUIURLDetector.extract(from: line, for: .napCat)
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:6099/webui?token=abc123")
    }

    func testNapCatPrefersIPv4OverIPv6() {
        let line = "WebUi User Panel Url: http://[::1]:6099/webui http://127.0.0.1:6099/webui?token=t"
        let url = WebUIURLDetector.extract(from: line, for: .napCat)
        XCTAssertEqual(url?.host, "127.0.0.1")
    }

    func testUnrelatedLineYieldsNil() {
        XCTAssertNil(WebUIURLDetector.extract(from: "hello world", for: .astrbot))
        XCTAssertNil(WebUIURLDetector.extract(from: "hello world", for: .napCat))
    }
}
