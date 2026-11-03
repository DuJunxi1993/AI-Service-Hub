# AI Service Hub

一个 macOS 原生应用，用于集中启动、管理 AstrBot（通过 `uv` 部署）以及通过 `docker compose` 部署的 NapCat、Shipyard 等容器。
<img width="927" height="651" alt="iShot_2026-06-22_13 15 48" src="https://github.com/user-attachments/assets/ca05290f-47c9-4f3f-acf7-eb84620f535c" />

## 功能特性

- 🚀 **一键管理**：启动 / 停止 / 全部启动 / 全部停止
- 📊 **实时状态**：服务状态轮询 + 事件驱动
- 📜 **日志查看**：分服务来源、实时 tail、错误高亮
- ⚙️ **灵活配置**：
  - AstrBot 支持 4 种启动模式（uv tool run / 自定义命令 / 可执行文件 / shell 脚本）
  - Docker compose 路径自动检测 + 手动添加
  - 容器列表动态刷新
- 🪟 **macOS 集成**：
  - 菜单栏常驻
  - 登录项自启
  - 系统通知
  - 启动时最小化

## 环境要求

- macOS 26.0+ (Taho)
- Swift 6.0+ 工具链（Xcode Command Line Tools 已包含）
- 需要安装：`uv` (AstrBot)、`docker` (NapCat / Shipyard)

## 构建

```bash
bash build.sh
```

产物：`AiServiceHub.app`

## 运行开发版

```bash
bash run.sh
```

## 首次启动注意

由于未进行 Apple Developer 签名，首次启动可能被 Gatekeeper 拦截。处理方法：
- 在 Finder 中右键 `AiServiceHub.app` → 打开 → 在弹窗中再次点击"打开"
- 或执行：`xattr -dr com.apple.quarantine AiServiceHub.app`

## 项目结构

```
AiServiceHub/
├── Sources/AiServiceHub/
│   ├── App/                    入口
│   ├── Models/                 数据模型
│   ├── Managers/               业务管理
│   ├── Views/                  界面
│   │   ├── MainWindow/         主窗口（服务、日志）
│   │   ├── Settings/           设置面板
│   │   ├── Components/         通用组件
│   │   └── MenuBar/            菜单栏
│   └── Utilities/              工具
├── Resources/
│   ├── Info.plist
│   └── ai_service_hub.icns
├── Package.swift               SwiftPM 配置
├── build.sh                    打包脚本
└── run.sh                      开发运行脚本
```

## 许可

本项目基于 [MIT License](LICENSE) 开源。详见根目录的 `LICENSE` 文件。
