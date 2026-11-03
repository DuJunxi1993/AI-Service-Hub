# AI Service Hub — Release Notes

macOS 端的发布记录。最新版本在顶部，历史变更在下方按时间倒序排列。

---

## 📥 Latest Release

### v2.0.0 — 2026-11-03 · 🏷️ 更名 + 架构重构

**最低系统**: macOS 26 Tahoe (Apple Silicon) · **架构**: arm64

**下载**

| 文件 | 大小 | SHA256 |
|------|------|--------|
| `AiServiceHub-2.0.0.dmg` | 1.5 MB | `138994729abf509d208aac1c1905289b64ab941983adeb0a4ca09cb90392dc50` |
| `AiServiceHub-2.0.0-macOS.zip` | 1.0 MB | `46c954f62d93db7000392e5ab394a011f776d27a7f6c3dfea99cb41dae682b94` |

下载：[GitHub Releases · macos-v2.0.0](https://github.com/DuJunxi1993/AstrbotLauncher/releases/tag/macos-v2.0.0)

> v2.0.0 为架构性变更，**不兼容旧版配置格式**（会自动迁移）。
> 变更详情见下方 [Changelog → v2.0.0](#v200--2026-11-03--更名--架构重构)。

---

## ✨ 主要功能

- **两种生命周期模式** — 纯监控（只读）/ 可管理（本程序负责启停）
- **三种驱动方式** — 持有子进程、委托 Docker 容器、只读探测
- **内置预设** — AstrBot（可管理）、Hermes Agent 与 DeepSeek Harness（纯监控）
- **任意服务** — Docker 容器从列表选取；自定义进程服务可配置可执行文件、参数、工作目录、daemon 化与退出行为
- **常驻日志中心** — 每个服务独立采集，切换服务不中断、不重复；支持搜索 / 暂停 / 复制 / 清空 / 全屏
- **WebUI 地址发现** — 从日志提取带 token 的地址，不依赖当前选中哪个服务
- **探测结果面板** — 进程、监听端口、HTTP 可达性、Gateway 平台状态
- **启动时自动拉起** — 总开关 + 逐项勾选，只对可管理服务生效
- **菜单栏常驻** — app 关闭后菜单栏图标仍可访问
- **Liquid Glass** UI — SwiftUI 原生 Liquid Glass 设计

---

## 🚀 安装

### DMG（推荐）
1. 双击 `AiServiceHub-{VERSION}.dmg`
2. 拖拽 `AiServiceHub.app` 到 `/Applications`
3. 在 Launchpad 打开 "AI Service Hub"
4. 首次启动如遇 Gatekeeper 拦截，在"系统设置 → 隐私与安全性"点击"仍要打开"

### ZIP
1. 解压 `AiServiceHub-{VERSION}-macOS.zip`
2. 移动 `AiServiceHub.app` 到 `/Applications`
3. 启动 app

> ⚠️ **从 v1.0.0 / v1.0.1 升级**：先删除 `/Applications` 中的旧版 `AiServiceHub.app`（避免旧 UserDefaults 残留导致崩溃）。

---

## 📋 首次使用

1. 启动 AI Service Hub
2. 打开 ⚙️ 设置
3. 在 "Docker 容器" 部分选择 NapCat / Shipyard 容器
4. 设置 AstrBot WebUI 端口（默认 6185）
5. 配置 AstrBot 日志路径（默认 `~/data/logs/astrbot.log`）
6. 返回主窗口，点工具栏 ▶ **启动** 即可一键启动全部服务
7. 在 sidebar 拖动服务项可调整顺序

---

## 🔧 系统要求

- **macOS 26 Tahoe** 或更高
- **Apple Silicon** (M1/M2/M3/M4)
- **Docker Desktop** 已安装并运行
- **AstrBot** 通过 `uv tool install astrbot` 安装
- **NapCat / Shipyard** 通过 `docker compose` 部署

---

## 📜 Changelog

### v2.0.0 — 2026-11-03 · 更名 + 架构重构

**更名**

项目不再只服务于 AstrBot，改为通用多服务控制台，因此更名 **AI Service Hub**。

- 可执行文件 / SPM 模块：`AstrbotLauncher` → `AiServiceHub`
- Bundle ID：`com.djx.astrbotlauncher` → `com.djx.aiservicehub`
- 显示名：`AstrBot Launcher` → `AI Service Hub`

**两种生命周期模式**

顶层只区分「本程序要不要负责它的生命周期」：

- `observed` 纯监控 — 只读取状态、日志、端口，不启动、不停止、不持有任何进程
- `managed` 可管理 — 再按驱动方式细分：
  - `process` 持有子进程 — 本程序 spawn 并持有 PID
  - `container` 委托容器 — 只发 `docker start/stop`，进程由 dockerd 托管

持有子进程时提供两个独立开关：`detached`（daemon 化）与 `stopOnAppQuit`（退出时终止）。

**新增监控板块**

- **Hermes Agent**（纯监控）：读取 `~/.hermes/gateway_state.json`，显示 Gateway 运行状态、活跃 Agent 数、版本、各消息平台连接状态与最后更新时间；端口是动态分配的，按 pid 反查；可实时查看 gateway / agent 日志。
- **DeepSeek Harness**（纯监控）：显示 `dsh web` 进程与 `--port`、DSHShell 进程、HTTP 可达性（DSH 全部路径需鉴权，401 视为可达）、最近启动日志与会话数量。

**任意服务**

- Docker 服务不再写死。NapCat / Shipyard 不再是预设，从容器列表直接选取。
- 自定义进程服务：可配置可执行文件、参数、工作目录、是否经 shell、存活检测、日志来源、daemon 化与退出行为。

**启动时自动拉起**

- 总开关 + 每个服务独立勾选，只对可管理服务生效。
- 单个服务启动失败不阻断其余服务。

**架构重构**

- 抽出 `AiServiceHubCore`（纯 Foundation，编译期禁止 import SwiftUI），配 57 个单元测试。
- `AppState`（上帝对象）拆分为 `AppModel`（编排）+ Core 内的驱动与探测器。
- `ServiceDescriptor` 描述符 + 两档生命周期取代写死的三枚举。
- 配置从 UserDefaults 平铺 key 改为版本化 JSON，写入保留 `.bak`，损坏自动回退。
- `LogHub` 取代 `LogWatcher`：tailer 常驻，与视图生命周期解耦。
- 进程身份改用 `pid + 启动时间` 双条件，避免 PID 复用误杀；新增所有权账本用于回收孤儿进程。
- 命令执行改为并发读取 stdout/stderr + 超时 + 取消。
- 探测统一走 `ps -A` 枚举（macOS 27 的 `pgrep -f` 会漏掉由 GUI app 派生的进程）。

**迁移**

新版首次启动会显式读取旧域 `com.djx.astrbotlauncher`：

- AstrBot 的启动模式 / 路径 / 端口 → 「可管理 · 持有子进程」
- NapCat / Shipyard 的容器名 → 「可管理 · 委托容器」
- 主题、轮询间隔、自启、侧边栏顺序 → 偏好设置

旧配置保留在磁盘上但不再读取。建议删除 `/Applications` 里的旧 app，
并在新版设置中重新开启「开机自动启动」。

**新图标**

- 全新品牌图形，浅色 / 深色两套
- Dock 图标跟随**系统**明暗：白天浅色、夜间深色
  （macOS 的 bundle 图标不随外观切换，只有运行中的 Dock 图标能变）
- 菜单栏改用品牌轮廓图（模板图，自动适配菜单栏明暗）

**构建**

- 新增 `scripts/xcode-env.sh` 自动定位可用 Xcode（CommandLineTools 缺少 SwiftUI 宏插件，无法编译本项目）。
- `build.sh` 只使用仓库内图标，不再依赖 `~/Downloads` 与 `~/Pictures`。
- CI 改为真实可跑的 `macos-26` workflow：跑测试、打包 zip + dmg、tag 时创建 Release。

---

### v1.0.3 — 2026-06-18

**改进**
- **工具栏布局** — 在启停按钮和右侧 4 个按钮之间增加可调间距
  - 实现方式：`ToolbarItem(placement: .principal) { Color.clear.frame(maxWidth: .infinity) }` 填充中间区域
  - 右侧 4 个按钮（刷新 / WebUI / 数据目录 / 设置）从 `.automatic` 改为 `.primaryAction`（挤在右侧）
  - 视觉效果：左侧启停按钮 + 中间大片空白 + 右侧 4 个按钮聚集

**保留 v1.0.2 修复**
- 彻底移除 `.toolbar(id:)` / `customizationBehavior()`，修复 macOS 26.5.1 启动崩溃
- 启动时主动清理 `NSNavToolbarCustomization-*` 和 `NSToolbar Identifier *` UserDefaults keys
- 5 个固定 toolbar items，无 customization

**保留 v1.0.1 功能**
- Sidebar 拖动排序 + 顺序持久化
- 启停 / 刷新 / WebUI / 数据目录 / 设置
- 日志查看 / 暂停 / 清空（只清当前 service）
- Liquid Glass UI
- daemon 化 AstrBot
- 菜单栏常驻

---

### v1.0.2 — 2026-06-18 · 🔴 紧急修复

**关键崩溃修复**

- **问题**：v1.0.0 / v1.0.1 启用 `.toolbar(id:)` + `customizationBehavior()` 尝试实现 Finder 风格工具栏自定义。**但 macOS 26.5.1 在应用启动时尝试应用旧版 UserDefaults 残留的 customization 状态，会触发 `AppKitToolbarStrategy.applyItemCustomizations` 内部断言崩溃**（`EXC_BREAKPOINT`）。
- **影响**：所有从 v1.0.0 / v1.0.1 升级的用户的 UserDefaults 都有残留，**必崩**。
- **修复**：
  - 彻底移除 `.toolbar(id:)` 和所有 `customizationBehavior()` 调用
  - 改用普通 `.toolbar { ... }`（5 个固定 items，无 customization）
  - 启动时主动清理 `NSNavToolbarCustomization-*` 和 `NSToolbar Identifier *` UserDefaults keys
  - 不再添加 `ToolbarCommands()` 到 scene commands

**妥协：Finder 风格工具栏自定义**

- v1.0.0/v1.0.1 的工具栏自定义功能（右键 → Customize Toolbar）已移除。这是 macOS 26.5.1 上 SwiftUI 的根本问题，强行使用会崩溃。
- 后续 v1.1.x 会用其他方式（自定义 NSToolbar 或纯 SwiftUI Layout）实现类似体验。

**保留的功能**（v1.0.1 → v1.0.2）

| 功能 | 状态 |
|------|------|
| 启停切换 | ✅ |
| 刷新 | ✅ |
| 打开 WebUI | ✅ |
| 数据目录 | ✅ |
| 设置 | ✅ |
| Sidebar 拖动排序 | ✅ |
| 日志查看 / 暂停 / 清空 | ✅ |
| 状态栏 + 详情头部状态指示 | ✅ |
| Sidebar 服务顺序持久化 | ✅ |

---

### v1.0.1 — 2026-06-18

**修复**
- **Sidebar 状态点重复** — 移除 sidebar 项目的红绿状态点（状态栏和详情头部已有指示）
- **Toolbar customization 崩溃** — 启动时清理旧 UserDefaults state（防崩溃 v1.0.0 已知问题再次发生）
- **Service selection tint** — 改用 `CustomizableToolbarContent` 协议 + `customizationBehavior()` modifier，正确的 macOS 26 API

**新增**
- **Sidebar 拖动排序** — `ForEach.onMove` 让服务项像 Finder 一样可拖动重排
- **Finder 风格工具栏自定义** — 菜单栏 View → Customize Toolbar，可拖入 / 拖出 / 重排工具栏 items
- **Service 顺序持久化** — 用户的 sidebar 顺序保存到 UserDefaults，重启后保持

**优化**
- **日志性能** — `filteredLines` 改 `@State` 缓存，避免每次 render O(n) 扫描
- **Pause 不丢失历史** — 用 `LogWatcher.isPaused` 标志，暂停时保留已显示的日志（旧版 `stop()` 会清空）
- **Per-service clear** — 清空按钮只清当前 service 的日志（不影响其他服务）
- **scrollTo 去掉 withAnimation** — 避免每行日志触发 layout pass

**改进**
- **设置页布局修复** — 修复 Docker Picker 宽度不一致、WebUI 端口显示格式
- **状态栏** — 移除矩形背景，与主内容在同一层
- **主题集成** — 完整 Liquid Glass 适配

---

### v1.0.0 — 2026-06-18 · Initial Release

**主要功能**
- **一键管理** 三个核心服务：AstrBot（QQ 机器人）、NapCat（QQ 协议端）、Shipyard（Agent 调度平台）
- **实时日志** 监听（文件 / docker logs 双模式，行缓冲 + 批量 flush）
- **智能 URL 检测** 从日志自动提取 WebUI URL（含 token）
- **daemon 化** AstrBot — 关闭 app 不影响 AstrBot 运行
- **菜单栏常驻** — app 关闭后菜单栏图标仍可访问
- **Liquid Glass** UI — SwiftUI 原生 Liquid Glass 设计

**已知问题（v1.0.0 时代）**
- 服务状态切换瞬时按钮图标可能闪烁
- WebUI 按钮位置在 ServiceDetailView（如需在工具栏加回，需手动开关，目前通过详情页访问）

---

## 📮 反馈

GitHub Issues：https://github.com/DuJunxi1993/AiServiceHub/issues

---

## 📝 增量更新约定

发布新版本时，按以下顺序更新本文档：

1. **顶部「Latest Release」**：更新版本号、发布日期、下载表、SHA256
2. **「Changelog」顶部**：插入新版本小节（保持时间倒序）
3. **稳定章节**（主要功能 / 安装 / 首次使用 / 系统要求）：仅在发生变化时更新
4. 提交并推送到 `macos` 分支