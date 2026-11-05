# AI Service Hub — Release Notes

macOS 端的发布记录。最新版本在顶部，历史变更在下方按时间倒序排列。

---

## 📥 Latest Release

### v2.0.2 — 2026-11-05 · 🐛 勾选自动拉起立即生效

**最低系统**: macOS 26 Tahoe (Apple Silicon) · **架构**: arm64

**下载**

| 文件 | 大小 | SHA256 |
|------|------|--------|
| `AiServiceHub-2.0.2.dmg` | 1.5 MB | `ce0f4eb283cf1722d8a079631bd58a18527ecaf1be70da348a7b5b122d681e7a` |
| `AiServiceHub-2.0.2-macOS.zip` | 1.1 MB | `830515923d76b9f3ff5fcd598facdb90382b54498b9eb224df5925804722c6d8` |

下载：[GitHub Releases · macos-v2.0.2](https://github.com/DuJunxi1993/AI-Service-Hub/releases/tag/macos-v2.0.2)

> v2.0.2 是 v2.0.1 的 bug 修复版，配置格式向后兼容，**直接覆盖安装即可**。
> 变更详情见下方 [Changelog → v2.0.2](#v202--2026-11-05--勾选自动拉起立即生效)。

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

### v2.0.2 — 2026-11-05 · 勾选自动拉起立即生效

#### 🐛 勾选了「启动时自动拉起」但服务没被拉起

容器启动逻辑本身没问题，坏的是**时机**：自动拉起只在 app 启动那一刻跑一次。
用户在 app 已经运行的时候勾选这个框，这个设置要等到下次启动 app 才生效 ——
看上去就像坏了。

典型场景：系统重启后容器被停掉 → app 启动（此时还没勾选，自动拉起跳过了它）→
用户勾上「启动时自动拉起」→ 什么都没发生。

**改动**

- 勾上某个可管理服务的「启动时自动拉起」，若它现在没在跑 → **立刻启动**
- 打开总开关 → 把勾选了且没在跑的服务都拉起来（先刷新一次拿准确状态，
  避免对着已经停掉的服务重复拉起）
- 设置面板的服务列表里显示**运行状态**（色点 + 文字），
  一眼能看出勾选到底生效没有
- tooltip 说明新行为

#### 🧪 顺带修一个定时炸弹测试

`PlatformRowColorTests` 用了硬编码时间戳（2026-11-03，相差 1 小时 17 分），
断言两者的相对时间描述不同。日历一翻篇，两个时刻都落进「1 天前」，断言失效 ——
与功能改动无关，但会让 CI 莫名变红。改成相对当前时间计算。

---

### v2.0.1 — 2026-11-04 · UI 修复与布局重构

一批用户反馈的修复。

#### 📁 打开数据目录指向真实目录

之前「打开数据目录」总是打开主目录 —— 它只认 AstrBot 的 `workingDirectory`（那是 `~/`），
而且与当前选中的服务无关。

- 服务新增 `dataDirectory` 字段，内置预设分别填 `~/data`、`~/.hermes`、`~/.dsh`
- 旧配置启动时自动补齐
- 顶栏按钮改为打开**当前选中服务**的数据目录；详情页另有「数据目录」按钮
- 目录不存在时退回报打开所在目录，不静默失败

#### 🛑 纯监控服务也能一键停止

Hermes / DSH 是只读监控，没有驱动也没有进程所有权，常规「停止」不适用 ——
但确实可能想一键停掉它们。

- 新增 `ProcessDriver.terminateAll()`：SIGTERM → 3 秒 → SIGKILL
- 停止用的进程匹配规则与**探测规则分开**：探测要精确（PID 决定端口反查对象），
  停止要全面 —— Hermes 的进程散落在 supervisor / python / 桌面端，只按探测规则会漏掉一大半
- 停止前有确认对话框，列出规则与匹配到的进程数
- DSH 的对话框额外提示：Web 控制台进程也在其中，停止后会失去连接

#### 🧹 移除 Shipyard 预设

不再迁移 Shipyard 服务；已有配置启动时自动移除。

#### 🪟 窄窗口下面板被遮挡

根因是宽度预算超了：窗口最小 760 − 侧栏最小 200 = 560，而详情区要 340 + 300 = 640，
内容溢出后被**两侧**裁掉，看起来像被居中截断。

- 窗口最小宽度 760 → 820，侧栏最小 200 → 170，详情区子面板最小 340/300 → 260/220
- 新增流式布局（`FlowLayout`）：按钮放不下就换行，不再撑破容器
- 详情区宽度不足 560 时，日志自动改为横向铺满
- 窄面板下元数据行改为标签在上、值在下（最多 3 行）

#### 📜 长命令行不再撑爆详情页

「同名进程」区块显示完整命令行，而 Hermes 的 osascript 包装器里内嵌了几百行 Python 代码。
现压成单行并截断到 160 字符。

#### 📜 日志自动跟随最新

之前监听的是 `cachedLines.count`，而缓冲区上限 2000 行 —— 满了之后行数不再变化，
回调再也不触发，**正好在日志最旺的时候失效**。

- 改为监听最后一行
- 新增「跟随最新」开关，默认开启；关闭后保持用户当前停留位置

#### 🔘 按钮位置

- 顶栏按钮（刷新 / WebUI / 数据目录 / 设置 / 启停）移到窗口**最右侧**
- 详情页操作按钮改为**居中**
- 窗口改用标准标题栏（原先的隐藏标题栏会让 SwiftUI 忽略工具栏的靠右对齐）

---

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