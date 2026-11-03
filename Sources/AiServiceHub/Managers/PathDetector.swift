import Foundation

/// 自动检测 docker compose 文件路径
enum PathDetector {
    struct DetectedCompose {
        let path: String
        let directoryName: String
        let matchedKeyword: String  // napcat / shipyard / astrbot
        let serviceName: String    // compose 中第一个 service 名
    }

    /// 扫描 $HOME 下深度 ≤3 包含 compose 文件的目录
    static func scanHome() -> [DetectedCompose] {
        let home = NSHomeDirectory()
        let maxDepth = 3
        let keywords = ["napcat", "shipyard", "astrbot"]
        let composeFileNames = ["compose.yml", "compose.yaml", "docker-compose.yml", "docker-compose.yaml"]

        var results: [DetectedCompose] = []
        let fm = FileManager.default

        func scan(_ dir: String, depth: Int) {
            guard depth <= maxDepth else { return }
            guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { return }

            // 先检查当前目录是否有 compose 文件
            for name in composeFileNames {
                let path = "\(dir)/\(name)"
                if fm.fileExists(atPath: path) {
                    let dirName = (dir as NSString).lastPathComponent.lowercased()
                    let matched = keywords.first { dirName.contains($0) }
                    let serviceName = parseServiceName(from: path) ?? "default"
                    results.append(DetectedCompose(
                        path: path,
                        directoryName: (dir as NSString).lastPathComponent,
                        matchedKeyword: matched ?? "other",
                        serviceName: serviceName
                    ))
                    break // 一个目录只取一个 compose
                }
            }

            // 递归子目录
            if depth < maxDepth {
                for name in contents {
                    // 跳过隐藏目录和常见的大目录
                    if name.hasPrefix(".") { continue }
                    if ["node_modules", "Pods", "build", ".build", "venv", ".venv"].contains(name) { continue }
                    let subdir = "\(dir)/\(name)"
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: subdir, isDirectory: &isDir), isDir.boolValue {
                        scan(subdir, depth: depth + 1)
                    }
                }
            }
        }

        scan(home, depth: 0)
        return results
    }

    /// 从 compose 文件中解析第一个 service 名
    private static func parseServiceName(from path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        // 简单字符串解析：找第一个 "image:" 或 "build:" 之前的顶级 key
        guard let content = String(data: data, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: "\n")
        var inServices = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("services:") {
                inServices = true
                continue
            }
            if inServices {
                // 顶级 key: 2 空格缩进 + 名称 + :
                if line.hasPrefix("  ") && !line.hasPrefix("    ") && trimmed.hasSuffix(":") {
                    return String(trimmed.dropLast())
                }
            }
        }
        return nil
    }

    /// 合并自动检测和手动添加的路径
    static func allCandidatePaths(manual: [String]) -> [DetectedCompose] {
        var seen = Set<String>()
        var all: [DetectedCompose] = []

        for detected in scanHome() {
            if seen.insert(detected.path).inserted {
                all.append(detected)
            }
        }

        for path in manual {
            let expanded = (path as NSString).expandingTildeInPath
            if seen.insert(expanded).inserted, ShellExecutor.exists(expanded) {
                let dirName = (expanded as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? "manual"
                let serviceName = parseServiceName(from: expanded) ?? "default"
                let lowercased = dirName.lowercased()
                let keyword = ["napcat", "shipyard", "astrbot"].first { lowercased.contains($0) } ?? "manual"
                all.append(DetectedCompose(
                    path: expanded,
                    directoryName: dirName,
                    matchedKeyword: keyword,
                    serviceName: serviceName
                ))
            }
        }
        return all
    }
}
