import Foundation
import os

/// 内部调试日志（os.Logger）
public enum AppLog {
    private static let logger = Logger(subsystem: "com.djx.aiservicehub", category: "general")

    public static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public static func warn(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    public static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
