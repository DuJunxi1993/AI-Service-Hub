import SwiftUI
import AiServiceHubCore

/// 状态栏 - 底部 capsule 玻璃
struct StatusBarView: View {
    @EnvironmentObject var appModel: AppModel
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 12) {
            // 运行统计
            HStack(spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 9))
                Text("\(appModel.runningCount) / \(appModel.totalCount) 运行中")
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

            // 各个服务的状态点
            HStack(spacing: 8) {
                ForEach(settings.orderedServices) { descriptor in
                    if let snapshot = appModel.snapshots[descriptor.id] {
                        HStack(spacing: 3) {
                            StatusDot(status: snapshot.status)
                            Text(descriptor.name)
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
