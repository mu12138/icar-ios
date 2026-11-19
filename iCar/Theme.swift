import SwiftUI

/// 深色玻璃主题：背景用柔和光斑，卡片用系统材质，模糊才有东西可糊
enum Theme {
    static let accent = Color(red: 0.36, green: 0.62, blue: 1.0)
    static let accent2 = Color(red: 0.55, green: 0.42, blue: 0.98)
    static let danger = Color(red: 0.95, green: 0.38, blue: 0.36)
    static let bg = Color(red: 0.05, green: 0.06, blue: 0.09)
}

/// 背景：深色底 + 两团缓慢流动的光斑，给材质提供模糊内容
struct Backdrop: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            Circle()
                .fill(Theme.accent.opacity(0.55))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: -110 + phase * 30, y: -260)

            Circle()
                .fill(Theme.accent2.opacity(0.5))
                .frame(width: 300, height: 300)
                .blur(radius: 100)
                .offset(x: 130 - phase * 26, y: 250)

            Circle()
                .fill(Color(red: 0.2, green: 0.75, blue: 0.7).opacity(0.28))
                .frame(width: 240, height: 240)
                .blur(radius: 90)
                .offset(x: -60, y: 380 + phase * 20)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

/// 玻璃卡片：ultraThinMaterial + 细描边，iOS 原生质感
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 16
    // 必须是闭包：存 Content 的话尾随闭包对不上合成构造器
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 18, y: 10)
    }
}

/// 玻璃按钮
struct GlassButton: View {
    let title: String
    let symbol: String
    var danger: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 21, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 74)
            .foregroundStyle(danger ? Theme.danger : Color.white.opacity(0.92))
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 车况小卡
struct StatTile: View {
    let title: String
    let value: String
    let unit: String
    let symbol: String
    var tint: Color = Theme.accent

    var body: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.white.opacity(0.55))
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(value)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
