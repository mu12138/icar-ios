import SwiftUI

/// 车况明细（对应 Android 的「详情」面板）
struct DetailSheet: View {
    let s: CarStatus?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Backdrop()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    HStack {
                        Text("车况详情")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Button("关闭") { dismiss() }
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 8)

                    group("基本", rows: [
                        ("剩余油量", "\(s?.fuel ?? 0) %"),
                        ("续航里程", "\(s?.range ?? 0) km"),
                        ("总里程", "\(Int(s?.odo ?? 0)) km"),
                        ("本次里程", String(format: "%.1f km", s?.tripMileage ?? 0)),
                        ("车外温度", "\(s?.tempOut ?? 0) ℃"),
                        ("车内温度", "\(s?.tempIn ?? 0) ℃"),
                        ("水温", (s?.waterTemp ?? 0) > 0 ? "\(Int(s!.waterTemp)) ℃" : "--"),
                        ("车速", "\(Int(s?.speed ?? 0)) km/h"),
                        ("电瓶电压", (s?.voltage ?? 0) > 0 ? String(format: "%.1f V", s!.voltage) : "--"),
                    ])

                    group("状态", rows: [
                        ("车锁", (s?.locked ?? false) ? "已锁车" : "未锁车"),
                        ("空调", (s?.acOn ?? false) ? "已开启 · \(s?.acTemp ?? "--")℃" : "已关闭"),
                        ("天窗", (s?.sunroof ?? false) ? "打开" : "关闭"),
                        ("后备箱", (s?.trunk ?? false) ? "打开" : "关闭"),
                        ("网络", (s?.online ?? false) ? "在线" : "离线"),
                        ("主驾门", onOff(s?.doors[0])),
                        ("副驾门", onOff(s?.doors[1])),
                        ("左后门", onOff(s?.doors[2])),
                        ("右后门", onOff(s?.doors[3])),
                        ("左前窗", onOff(s?.windows[0])),
                        ("右前窗", onOff(s?.windows[1])),
                        ("左后窗", onOff(s?.windows[2])),
                        ("右后窗", onOff(s?.windows[3])),
                    ])

                    group("胎压", rows: [
                        ("左前", tire(s?.tires[0])),
                        ("右前", tire(s?.tires[1])),
                        ("左后", tire(s?.tires[2])),
                        ("右后", tire(s?.tires[3])),
                    ])
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func tire(_ v: Double?) -> String {
        guard let v = v, v > 0 else { return "--" }
        return "\(Int(v)) kPa"
    }

    private func onOff(_ b: Bool?) -> String { (b ?? false) ? "打开" : "关闭" }

    private func group(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .padding(.leading, 4)
            GlassCard(padding: 14) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                        HStack {
                            Text(r.0)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white.opacity(0.5))
                            Spacer()
                            Text(r.1)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.vertical, 7)
                        if i < rows.count - 1 {
                            Divider().overlay(Color.white.opacity(0.07))
                        }
                    }
                }
            }
        }
    }
}
