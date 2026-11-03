import XCTest
@testable import AiServiceHubCore

/// 针对真实 NapCat 日志行的 URL 提取
///
/// NapCat 的日志带 ANSI 颜色码，且 WebUI 地址出现在两行里：
/// 一行是 IPv4（可用），另一行是 IPv6（[::]，浏览器打不开）。
final class NapCatWebUIExtractionTests: XCTestCase {
    /// 真实日志行（含 ANSI 颜色码）
    private let realIPv4Line = "11-03 16:52:50 [\u{1B}[32minfo\u{1B}[39m] [NapCat] [WebUi] WebUi User Panel Url: http://127.0.0.1:6099/webui?token=602f0ee34cfb"
    private let realIPv6Line = "11-03 16:52:50 [\u{1B}[32minfo\u{1B}[39m] [NapCat] [WebUi] WebUi User Panel Url: http://[::]:6099/webui?token=602f0ee34cfb"

    func testExtractsIPv4UrlFromRealLogLine() {
        let url = WebUIURLDetector.extract(from: realIPv4Line, for: .napCat)
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:6099/webui?token=602f0ee34cfb")
    }

    func testExtractsIPv4EvenWhenIPv6LineComesFirst() {
        // 真实日志里 IPv6 那行紧跟在 IPv4 后面，但顺序不保证
        let url = WebUIURLDetector.extract(from: realIPv6Line + "\n" + realIPv4Line, for: .napCat)
        XCTAssertEqual(url?.host, "127.0.0.1")
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:6099/webui?token=602f0ee34cfb")
    }

    func testIPv6OnlyLineYieldsNil() {
        // 只有 IPv6 时不该给出打不开的地址
        XCTAssertNil(WebUIURLDetector.extract(from: realIPv6Line, for: .napCat))
    }

    func testTokenIsPreserved() {
        let url = WebUIURLDetector.extract(from: realIPv4Line, for: .napCat)
        XCTAssertEqual(url?.query, "token=602f0ee34cfb")
    }
}
