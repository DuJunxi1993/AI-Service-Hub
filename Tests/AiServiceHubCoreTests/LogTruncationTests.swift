import XCTest
@testable import AiServiceHubCore

/// 超长日志行的截断
///
/// AstrBot 的 `anthropic._base_client` DEBUG 日志会把整个 Anthropic 请求
/// （系统提示词 + 全部工具定义）dump 到一行，实测单行 1.3 MB。
/// 不截断的话 SwiftUI 渲染不出来（日志面板一片空白），而且环形缓冲
/// 2000 行 × 1.3 MB = 2.6 GB。
final class LogTruncationTests: XCTestCase {

    func testShortLineIsUntouched() {
        let line = "[2026-11-06 15:10:17.273] [Core] [INFO] 正常的一行"
        XCTAssertEqual(LogLine.truncateContent(line), line)
    }

    func testLineExactlyAtLimitIsUntouched() {
        let line = String(repeating: "a", count: LogLine.maxContentLength)
        XCTAssertEqual(LogLine.truncateContent(line), line)
    }

    func testOverlongLineIsTruncatedWithMarker() {
        let line = String(repeating: "x", count: LogLine.maxContentLength + 500)
        let result = LogLine.truncateContent(line)

        XCTAssertLessThan(result.count, line.count)
        XCTAssertTrue(result.hasPrefix(String(repeating: "x", count: 100)))
        XCTAssertTrue(result.contains("已截断"))
        // 标记里要带上原文长度，否则用户不知道丢了多少
        XCTAssertTrue(result.contains("\(line.count) 字符"))
    }

    func testTruncationKeepsOriginalCharacterCount() {
        // 中文按字符算，不能按 UTF-8 字节算（否则会被截成半个字）
        let line = String(repeating: "日", count: LogLine.maxContentLength + 100)
        let result = LogLine.truncateContent(line)
        XCTAssertTrue(result.hasPrefix(String(repeating: "日", count: 100)))
    }

    /// 真实场景：1.3 MB 的一行
    func testMegabyteLineIsBounded() {
        let line = String(repeating: "a", count: 1_330_930)
        let result = LogLine.truncateContent(line)
        XCTAssertLessThanOrEqual(result.count, LogLine.maxContentLength + 64)
    }
}
