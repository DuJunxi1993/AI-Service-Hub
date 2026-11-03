import SwiftUI

/// 服务状态指示点（带脉冲动画）
struct StatusDot: View {
    let status: ServiceStatus
    @State private var isPulsing: Bool = false

    var body: some View {
        ZStack {
            // 脉冲外圈（仅运行中时显示）
            if status == .running {
                Circle()
                    .fill(status.color.opacity(0.4))
                    .frame(width: 12, height: 12)
                    .scaleEffect(isPulsing ? 1.8 : 1.0)
                    .opacity(isPulsing ? 0 : 0.8)
                    .animation(
                        Animation.easeOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
            }

            // 主体
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
        }
        .onAppear {
            isPulsing = status == .running
        }
        .onChange(of: status) { _, newValue in
            isPulsing = newValue == .running
        }
    }
}
