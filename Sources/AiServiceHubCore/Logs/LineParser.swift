import Foundation

/// 把字节流按 \n 切分为完整行，保留未完成的半行
///
/// 线程安全：可在后台线程调用。
public final class LineParser: @unchecked Sendable {
    private var buffer = Data()
    private let lock = NSLock()

    public init() {}

    /// 喂入字节，返回完整行列表（剩余半行留在 buffer）
    public func feed(_ data: Data) -> [String] {
        guard !data.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        buffer.append(data)
        return drainCompleteLinesLocked()
    }

    /// 强制 flush 剩余 buffer（如 EOF）
    public func flushRemaining() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return nil }
        let line = String(data: buffer, encoding: .utf8) ?? ""
        buffer.removeAll(keepingCapacity: true)
        return line.isEmpty ? nil : line
    }

    private func drainCompleteLinesLocked() -> [String] {
        var lines: [String] = []
        var lastNewlineIndex: Int?
        for index in 0..<buffer.count where buffer[index] == 0x0A {
            lastNewlineIndex = index
        }
        guard let lastIdx = lastNewlineIndex else { return [] }

        let completeData = buffer.prefix(lastIdx + 1)
        buffer = Data(buffer.suffix(from: lastIdx + 1))

        var start = 0
        for index in 0..<completeData.count where completeData[index] == 0x0A {
            let lineData = completeData.subdata(in: start..<index)
            if let str = String(data: lineData, encoding: .utf8) {
                lines.append(str)
            }
            start = index + 1
        }
        return lines
    }
}
