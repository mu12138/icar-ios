import Foundation
import SwiftUI

/// 更新检查：从 Gitee 拉 version.json（和 Android 版同一个文件）
enum UpdateCheck {
    static let url = "https://gitee.com/mu12138s/icar-update/raw/master/version.json"

    struct Info {
        var code: Int
        var version: String
        var url: String
        var codeText: String
        var note: String
    }

    static func fetch() async -> Info? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = 6
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let code = (j["code"] as? NSNumber)?.intValue ?? 0
        guard code > 0 else { return nil }
        return Info(code: code,
                    version: j["version"] as? String ?? "",
                    url: j["url"] as? String ?? "",
                    codeText: j["code_text"] as? String ?? "",
                    note: j["note"] as? String ?? "")
    }
}

/// 顶部更新条
struct UpdateBar: View {
    let info: UpdateCheck.Info
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("有新版本 \(info.version)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                Text(info.note + (info.codeText.isEmpty ? "" : " · \(info.codeText)"))
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            Button {
                if let u = URL(string: info.url) { UIApplication.shared.open(u) }
            } label: {
                Text("去下载")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.white, in: Capsule())
                    .foregroundStyle(Theme.accent)
            }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            LinearGradient(colors: [Theme.accent, Theme.accent2],
                           startPoint: .leading, endPoint: .trailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .padding(.horizontal, 12)
    }
}
