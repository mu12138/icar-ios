import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var pin = Store.get("pinCode") ?? ""
    @State private var confirm = Store.get("confirm") == "1"
    @State private var logs: [ChangAnAPI.ActionRecord] = []
    @State private var loadingLogs = false
    @State private var accent = Store.get("accent") ?? "#5B9EFF"

    private let accents: [(String, Color)] = [
        ("#5B9EFF", Color(red: 0.36, green: 0.62, blue: 1.0)),
        ("#8B6BFF", Color(red: 0.55, green: 0.42, blue: 0.98)),
        ("#34C759", Color(red: 0.20, green: 0.78, blue: 0.35)),
        ("#FF9F0A", Color(red: 1.0, green: 0.62, blue: 0.04)),
        ("#FF6B81", Color(red: 1.0, green: 0.42, blue: 0.51)),
        ("#40C8E0", Color(red: 0.25, green: 0.78, blue: 0.88)),
    ]

    var body: some View {
        ZStack {
            Backdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack {
                        Text("设置")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    .padding(.top, 8)

                    GlassCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("控车码")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            TextField("6 位数字，部分车型需要", text: $pin)
                                .keyboardType(.numberPad)
                                .textFieldStyle(.plain)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(Color.white.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .foregroundStyle(.white)
                                .onChange(of: pin) { _, v in
                                    let clean = String(v.filter(\.isNumber).prefix(8))
                                    if clean != v { pin = clean }
                                    Store.set(clean, for: "pinCode")
                                }
                        }
                    }

                    GlassCard(padding: 4) {
                        Toggle(isOn: $confirm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("操作二次确认")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(.white)
                                Text("点快捷指令前先问一句")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.45))
                            }
                        }
                        .tint(Theme.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .onChange(of: confirm) { _, v in
                            Store.set(v ? "1" : "0", for: "confirm")
                        }
                    }

                    GlassCard(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("强调色")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.8))
                            HStack(spacing: 12) {
                                ForEach(accents, id: \.0) { item in
                                    Circle()
                                        .fill(item.1)
                                        .frame(width: 26, height: 26)
                                        .overlay(
                                            Circle().strokeBorder(
                                                accent == item.0 ? Color.white : Color.clear,
                                                lineWidth: 2)
                                        )
                                        .onTapGesture {
                                            accent = item.0
                                            Store.set(item.0, for: "accent")
                                        }
                                }
                            }
                        }
                    }

                    operationLogs

                    GlassCard(padding: 4) {
                        Button {
                            app.logout()
                        } label: {
                            Text("退出登录")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .foregroundStyle(Theme.danger)
                        }
                    }

                    GlassCard(padding: 4) {
                        Button {
                            if let u = URL(string: "https://v.douyin.com/V-ceQdCsRA4/") {
                                UIApplication.shared.open(u)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "play.rectangle.fill")
                                    .foregroundStyle(.white.opacity(0.7))
                                Text("加入抖音群看教程")
                                    .font(.system(size: 13.5, weight: .medium))
                                    .foregroundStyle(.white)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.3))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 13)
                        }
                    }

                    Text("岁岁长安 · iOS 原生版 0.3")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.top, 6)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await loadLogs() }
        }
        .preferredColorScheme(.dark)
        .task { await loadLogs() }
    }

    private var operationLogs: some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("操作记录")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    if loadingLogs { ProgressView().scaleEffect(0.7).tint(.white) }
                }
                if logs.isEmpty {
                    Text("暂无记录")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.35))
                } else {
                    ForEach(logs.prefix(8)) { r in
                        HStack {
                            Text(r.name)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(1)
                            Spacer()
                            Text(r.status)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.45))
                                .lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private func loadLogs() async {
        loadingLogs = true
        defer { loadingLogs = false }
        logs = (try? await ChangAnAPI.actions()) ?? []
    }
}
