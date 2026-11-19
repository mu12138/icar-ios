import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @State private var pin = Store.get("pinCode") ?? ""
    @State private var confirm = Store.get("confirm") == "1"
    @State private var logs: [ChangAnAPI.ActionRecord] = []
    @State private var loadingLogs = false

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

                    Text("岁岁长安 · iOS 原生版 0.2")
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
