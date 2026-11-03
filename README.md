# AI Service Hub

一个 macOS 原生的多服务控制台：把本机上的若干服务放进同一个窗口里管理——状态、日志、端口、WebUI，以及启停。

不是通用进程守护器，而是给「一台机器上跑着几个互相配合的服务」这种场景用的控制台。

## 两种生命周期模式

顶层只区分一件事：**本程序要不要负责这个服务的生命周期**。

| 模式 | 行为 | 界面 |
|---|---|---|
| **纯监控** `observed` | 只读取状态、日志、端口，不启动、不停止、不持有任何进程 | 详情页无启停按钮 |
| **可管理** `managed` | 由本程序负责启停 | 详情页有启停 / 重启 |

「可管理」再按驱动方式细分：

| 驱动 | 行为 |
|---|---|
| **持有子进程** `process` | 本程序 `posix_spawn` 启动并持有 PID，可停止/重启 |
| **委托容器** `container` | 本程序只执行 `docker start/stop`，进程由 dockerd 托管 |

持有子进程时还有两个独立开关：

- `detached`：是否 daemon 化（脱离会话与进程组，本程序退出后继续运行）
- `stopOnAppQuit`：本程序退出时是否终止它

## 内置预设

| 预设 | 模式 | 说明 |
|---|---|---|
| **AstrBot** | 可管理 · 持有子进程 | 通过 `uv` 部署的 AI 机器人框架，daemon 化 |
| **Hermes Agent** | 纯监控 | 消息网关；读取 `gateway_state.json`、动态反查端口、显示各平台连接状态 |
| **DeepSeek Harness** | 纯监控 | Web 控制台；进程、`--port`、会话与启动日志 |

NapCat / Shipyard 这类 Docker 服务**不做预设**，直接「添加服务 → 委托 Docker 容器」从容器列表里选。

## 主要功能

- **服务列表**：可管理服务 + 纯监控服务并列，模式一眼可辨
- **实时日志**：每个服务独立常驻采集，切换服务不中断、不重复；支持搜索 / 暂停 / 复制 / 清空 / 全屏
- **WebUI 地址发现**：从日志里提取带 token 的地址，不依赖你是否正在看那个服务
- **探测结果**：进程、端口、HTTP 可达性、JSON 状态文件，统一渲染成明细表
- **启动时自动拉起**：总开关 + 逐项勾选，只对可管理服务生效
- **菜单栏常驻**：左键显示/隐藏窗口，右键服务快捷菜单
- **配置即文件**：`~/Library/Application Support/AI Service Hub/config.json`

## 环境要求

- **macOS 26 (Tahoe)** 或更高（UI 使用 Liquid Glass）
- **Xcode**（仅 CommandLineTools 不够：缺少 SwiftUI 的宏插件，编译会失败）
- 可选：`docker`（Docker Desktop）、`uv`（安装 AstrBot）

## 构建 / 运行

```bash
bash build.sh          # 产出 AiServiceHub.app（默认 release）
CONFIG=debug bash build.sh
bash run.sh            # 开发模式，直接跑二进制（不含窗口级系统集成）
swift test             # 单元测试
```

`build.sh` 会自动定位可用的 Xcode；也可以用 `DEVELOPER_DIR` 显式指定。

## 首次启动

由于未做 Apple Developer 签名，`build.sh` 只做 ad-hoc 签名，首次启动会被 Gatekeeper 拦截：

- Finder 中右键 `AiServiceHub.app` → 打开 → 再次确认，或
- `xattr -dr com.apple.quarantine AiServiceHub.app`

### 从旧版（AstrBot Launcher）升级

Bundle ID 从 `com.djx.astrbotlauncher` 变为 `com.djx.aiservicehub`，UserDefaults 因此换域。
新版在首次启动时会**显式读取旧域**并迁移：

- AstrBot 的启动模式 / 路径 / 端口 → 「可管理 · 持有子进程」
- NapCat / Shipyard 的容器名 → 「可管理 · 委托容器」
- 主题、轮询间隔、自启、侧边栏顺序 → 偏好设置

迁移完成后旧配置仍留在磁盘上（不再读取）。建议删除 `/Applications` 里的旧 app，
再在新版设置中重新开启「开机自动启动」。

## 项目结构

```
Sources/
├── AiServiceHubCore/         纯逻辑层，不依赖 SwiftUI，可单测
│   ├── Model/                生命周期、服务描述符、探测、日志、快照
│   ├── Runtime/              命令执行、进程/端口探测、spawn、Docker CLI
│   ├── Services/             进程驱动、派生探测、所有权账本
│   ├── Presets/              AstrBot / Hermes / DSH
│   ├── Logs/                 LogHub、LogTailer
│   ├── Config/               JSON 配置与旧版迁移
│   └── Support/              日志、路径、shell 解析、compose 端口解析
└── AiServiceHub/             SwiftUI 应用层
    ├── App/                  入口、AppDelegate
    ├── State/                AppModel（协调器）、AppSettings
    ├── Views/                主窗口、详情、日志、设置、菜单栏
    └── Utilities/            主题、通知名
Tests/AiServiceHubCoreTests/  单元测试
```

## 许可

[MIT License](LICENSE)
