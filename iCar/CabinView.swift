import SwiftUI

/// 车内视角：点阵车速 + 水温条（对应 Android 的 cabin 模式）
struct CabinView: View {
    let speed: Int
    let water: Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 26) {
                HStack {
                    Spacer()
                    Button("关闭") { dismiss() }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.top, 12)

                Spacer()

                VStack(spacing: 8) {
                    DotText(text: String(speed), dotSize: 7, spacing: 5)
                        .frame(height: 60)
                    Text("km/h")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }

                VStack(spacing: 8) {
                    DotText(text: "\(water)", dotSize: 4.5, spacing: 3)
                        .frame(height: 36)
                    Text("℃")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.accent, .cyan],
                                                     startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(0, min(1, Double(water) / 120)) * g.size.width)
                        }
                    }
                    .frame(height: 4)
                    .padding(.horizontal, 60)
                }

                Spacer()
                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .preferredColorScheme(.dark)
    }
}

/// 5×7 点阵数字
struct DotText: View {
    let text: String
    var dotSize: CGFloat = 6
    var spacing: CGFloat = 4

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                DotDigit(ch: ch, dotSize: dotSize)
            }
        }
    }
}

struct DotDigit: View {
    let ch: Character
    var dotSize: CGFloat

    // 5 宽 × 7 高，每个字符用 7 行字符串表示
    private static let font: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
    ]

    var body: some View {
        let rows = Self.font[ch] ?? Self.font["-"]!
        Canvas { ctx, size in
            let w = size.width / 5
            let h = size.height / 7
            let r = min(w, h) * 0.34
            for (y, row) in rows.enumerated() {
                for (x, c) in row.enumerated() where c == "1" {
                    let rect = CGRect(x: CGFloat(x) * w + w / 2 - r,
                                      y: CGFloat(y) * h + h / 2 - r,
                                      width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.92)))
                }
            }
        }
        .frame(width: dotSize * 5, height: dotSize * 7)
    }
}
