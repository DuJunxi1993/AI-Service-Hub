import Foundation

/// Shell 命令解析
///
/// 明确区分两种执行方式：
/// - **直接执行**（不经 shell）：命令被拆成 argv，第一个 token 是可执行文件。
///   `cd /x && astrbot run` 在这种方式下**不会**按用户预期工作。
/// - **经 shell**：整条命令交给 `/bin/sh -c`，`&&`、`|`、`>` 等语法才生效。
///
/// 因此提供 `requiresShell(_:)`，让上层在保存配置时就能提示用户。
public enum ShellArgumentParser {
    /// 需要 shell 才能生效的语法标记
    private static let shellMetacharacters: [Character] = ["&", "|", ";", "<", ">", "`", "$", "(", ")"]

    /// 判断命令是否必须经由 shell 执行
    /// - Returns: 需要 shell 时返回原因描述，否则返回 nil
    public static func requiresShell(_ command: String) -> String? {
        let trimmed = command.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // 显式的 shell 调用
        if trimmed.hasPrefix("bash ") || trimmed.hasPrefix("sh ") || trimmed.hasPrefix("zsh ") {
            return "命令已显式指定 shell"
        }
        // 重定向 / 管道 / 命令连接
        for token in ["&&", "||", ">>", "2>", ">&", "$(", "`"] where trimmed.contains(token) {
            return "命令包含 shell 语法 \(token)"
        }
        for ch in shellMetacharacters where trimmed.contains(ch) {
            return "命令包含 shell 元字符 \(String(ch))"
        }
        return nil
    }

    /// 把命令行拆成 (可执行文件, 参数)，**不经 shell**
    ///
    /// 支持单引号 / 双引号包裹的 token；不支持变量展开与通配符。
    public static func parse(_ command: String) -> (executable: String, arguments: [String]) {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasContent = false

        for ch in command {
            if let q = quote {
                if ch == q {
                    quote = nil
                } else {
                    current.append(ch)
                }
                continue
            }
            switch ch {
            case "\"", "'":
                quote = ch
                hasContent = true
            case " ", "\t":
                if !current.isEmpty || hasContent {
                    tokens.append(current)
                    current = ""
                    hasContent = false
                }
            default:
                current.append(ch)
                hasContent = true
            }
        }
        if !current.isEmpty || hasContent {
            tokens.append(current)
        }

        guard let first = tokens.first else {
            return ("/bin/echo", [])
        }

        // 第一个 token 解析为可执行文件
        let executable: String
        if first.hasPrefix("/") {
            executable = first
        } else if first.hasPrefix("~") {
            executable = PathExpander.expand(first)
        } else {
            executable = first  // 由调用方用 which 解析
        }

        return (executable, Array(tokens.dropFirst()))
    }
}
