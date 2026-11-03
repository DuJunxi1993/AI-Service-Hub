import Foundation

/// 路径工具
public enum PathExpander {
    /// 展开路径中的 ~ 与环境变量
    public static func expand(_ path: String) -> String {
        let tildeExpanded = (path as NSString).expandingTildeInPath
        return expandEnvironmentVariables(in: tildeExpanded)
    }

    /// 展开 $VAR 与 ${VAR}
    public static func expandEnvironmentVariables(in path: String) -> String {
        guard path.contains("$") else { return path }
        let environment = ProcessInfo.processInfo.environment

        var result = ""
        var index = path.startIndex
        while index < path.endIndex {
            let character = path[index]
            guard character == "$" else {
                result.append(character)
                index = path.index(after: index)
                continue
            }

            let afterDollar = path.index(after: index)
            guard afterDollar < path.endIndex else {
                result.append(character)
                index = afterDollar
                continue
            }

            if path[afterDollar] == "{" {
                let closing = path[afterDollar...].firstIndex(of: "}")
                guard let closing else {
                    result.append(character)
                    index = afterDollar
                    continue
                }
                let name = String(path[path.index(after: afterDollar)..<closing])
                result.append(environment[name] ?? "")
                index = path.index(after: closing)
            } else {
                // $NAME 形式：读取连续的字母数字下划线
                var end = afterDollar
                while end < path.endIndex,
                      path[end].isLetter || path[end].isNumber || path[end] == "_" {
                    end = path.index(after: end)
                }
                let name = String(path[afterDollar..<end])
                if name.isEmpty {
                    result.append(character)
                    index = afterDollar
                } else {
                    result.append(environment[name] ?? "")
                    index = end
                }
            }
        }
        return result
    }

    /// 展开路径并取其父目录
    public static func parentDirectory(of path: String) -> String {
        (expand(path) as NSString).deletingLastPathComponent
    }

    /// 文件是否存在
    public static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: expand(path))
    }
}
