import Foundation

/// 配置的 JSON 落盘
///
/// - 写入采用「先写临时文件再原子替换」，避免中途崩溃留下半个文件
/// - 每次写入前把上一份留作 `.bak`
/// - 读取失败时自动回退 `.bak`
public final class ConfigStore: @unchecked Sendable {
    /// 默认配置目录：`~/Library/Application Support/AI Service Hub`
    public static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("AI Service Hub", isDirectory: true)
    }

    public let fileURL: URL
    private let lock = NSLock()

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ConfigStore.defaultDirectory().appendingPathComponent("config.json")
    }

    /// 备份文件地址
    public var backupURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    /// 读取配置
    ///
    /// - Returns: 配置；文件不存在或损坏且无备份时返回 nil
    public func load() -> AppConfig? {
        lock.lock()
        defer { lock.unlock() }

        if let data = try? Data(contentsOf: fileURL),
           let config = try? Self.decoder.decode(AppConfig.self, from: data) {
            return config
        }

        // 主文件不可用时回退备份
        if let data = try? Data(contentsOf: backupURL),
           let config = try? Self.decoder.decode(AppConfig.self, from: data) {
            AppLog.warn("配置文件损坏，已回退到备份：\(backupURL.path)")
            return config
        }
        return nil
    }

    /// 保存配置
    public func save(_ config: AppConfig) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            AppLog.error("无法创建配置目录：\(error.localizedDescription)")
            return
        }

        // 旧文件留作备份
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: backupURL)
            try? FileManager.default.copyItem(at: fileURL, to: backupURL)
        }

        do {
            let data = try Self.encoder.encode(config)
            let tempURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent(".config-\(UUID().uuidString).tmp")
            try data.write(to: tempURL, options: .atomic)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: tempURL)
            } else {
                try FileManager.default.moveItem(at: tempURL, to: fileURL)
            }
        } catch {
            AppLog.error("配置保存失败：\(error.localizedDescription)")
        }
    }

    /// 删除配置文件
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: fileURL)
        try? FileManager.default.removeItem(at: backupURL)
    }

    // MARK: - 编解码

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
