import Foundation
import SwiftUI

/// 日志批处理器 - 把高频日志合并为低频更新
///
/// 设计目标：
/// - 减少 @Published lines 的赋值次数
/// - 减少主线程 Task 调度次数
/// - 支持线程安全的累积
@MainActor
final class LogBatcher {
    private var pending: [LogLine] = []
    private var flushTask: Task<Void, Never>?
    private let flushInterval: TimeInterval
    private let maxBatchSize: Int
    private let onFlush: ([LogLine]) -> Void

    init(
        flushInterval: TimeInterval = 0.1,
        maxBatchSize: Int = 500,
        onFlush: @escaping ([LogLine]) -> Void
    ) {
        self.flushInterval = flushInterval
        self.maxBatchSize = maxBatchSize
        self.onFlush = onFlush
    }

    /// 追加一行（带节流）
    func append(_ line: LogLine) {
        pending.append(line)
        if pending.count >= maxBatchSize {
            flush()
        } else {
            scheduleFlush()
        }
    }

    /// 批量追加多行（单次任务调度，比循环调用 append 效率高得多）
    func appendBatch(_ lines: [LogLine]) {
        guard !lines.isEmpty else { return }
        pending.append(contentsOf: lines)
        if pending.count >= maxBatchSize {
            flush()
        } else {
            scheduleFlush()
        }
    }

    /// 立即 flush 所有待处理行
    func flush() {
        flushTask?.cancel()
        flushTask = nil
        guard !pending.isEmpty else { return }
        let batch = pending
        pending.removeAll(keepingCapacity: true)
        onFlush(batch)
    }

    /// 重置（用于切换数据源时清空 pending）
    func reset() {
        flushTask?.cancel()
        flushTask = nil
        pending.removeAll(keepingCapacity: true)
    }

    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(flushInterval * 1_000_000_000))
            if !Task.isCancelled {
                flush()
            }
        }
    }
}

// MARK: - 背景累积器（线程安全）

/// 背景线程安全的日志累积器
/// 接收高频 append，1 秒由 Timer flush 一次到主线程
final class BackgroundLogAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: [LogLine] = []
    private let maxBufferSize: Int

    /// 主线程上调用，1 秒一次
    var onFlush: (@MainActor ([LogLine]) -> Void)?

    private var timer: Timer?
    private let flushInterval: TimeInterval

    init(maxBufferSize: Int = 2000, flushInterval: TimeInterval = 1.0) {
        self.maxBufferSize = maxBufferSize
        self.flushInterval = flushInterval
    }

    /// 启动定时 flush（主线程上调用）
    @MainActor
    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: flushInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.flushNow()
            }
        }
    }

    /// 停止
    @MainActor
    func stop() {
        timer?.invalidate()
        timer = nil
        flushNow()
    }

    /// 立即 flush（主线程）
    @MainActor
    private func flushNow() {
        let batch = takeAll()
        guard !batch.isEmpty else { return }
        onFlush?(batch)
    }

    /// 背景线程调用：追加单条
    func append(_ line: LogLine) {
        lock.lock()
        buffer.append(line)
        if buffer.count > maxBufferSize {
            // 防止无限增长
            buffer.removeFirst(buffer.count - maxBufferSize)
        }
        lock.unlock()
    }

    /// 背景线程调用：批量追加
    func appendBatch(_ lines: [LogLine]) {
        guard !lines.isEmpty else { return }
        lock.lock()
        buffer.append(contentsOf: lines)
        if buffer.count > maxBufferSize {
            buffer.removeFirst(buffer.count - maxBufferSize)
        }
        lock.unlock()
    }

    /// 主线程或背景线程调用：取出并清空所有
    private func takeAll() -> [LogLine] {
        lock.lock()
        defer { lock.unlock() }
        guard !buffer.isEmpty else { return [] }
        let batch = buffer
        buffer.removeAll(keepingCapacity: true)
        return batch
    }
}
