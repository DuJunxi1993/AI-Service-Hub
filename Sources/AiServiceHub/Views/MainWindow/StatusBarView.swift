import SwiftUI

/// 状态栏 - 底部 capsule 玻璃
struct StatusBarView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            // 运行统计
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 9))
                Text("\(appState.runningCount) / \(appState.totalCount) 运行中")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.primary)

            Divider().frame(height: 12).opacity(0.3)

            // 轮询间隔
            HStack(spacing: 4) {
                Image(systemName: "timer")
                    .font(.system(size: 9))
                Text("轮询 \(settings.pollingInterval)s")
                    .font(.system(size: 10))
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)

            Spacer()

            // 三个状态点
            HStack(spacing: 8) {
                ForEach(ServiceType.allCases) { type in
                    if let svc = appState.services[type] {
                        HStack(spacing: 3) {
                            StatusDot(status: svc.status)
                            Text(type.displayName)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
