import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @State private var showSettings = false

    private var s: CarStatus? { app.status }

    var body: some View {
        ZStack {
            Backdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    statusGrid
                    commandGrid
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await app.refresh() }
        }
        .preferredColorScheme(.dark)
        .task { await app.refresh() }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(app)
                .presentationDetents([.medium])
                .presentationBackground(.ultraThinMaterial)
        }
        .overlay(alignment: .top) {
            if let t = app.toast { ToastView(text: t, ok: true) }
            else if let e = app.error { ToastView(text: e, ok: false) }
        }
        .onChange(of: app.toast) { _, v in clearSoon(v) }
        .onChange(of: app.error) { _, v in clearSoon(v) }
    }

    private func clearSoon(_ v: String?) {
        guard v != nil else { return }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            app.toast = nil
            app.error = nil
        }
    }

    // MARK: - 头部

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill((s?.online ?? false) ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                    Text((s?.online ?? false) ? "在线" : "离线")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text(app.carName)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button {
                Task { await app.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white.opacity(0.85))
            }
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.top, 8)
    }

    // MARK: - 车况

    private var statusGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "剩余油量", value: "\(s?.fuel ?? 0)", unit: "%",
                         symbol: "fuelpump.fill")
                StatTile(title: "续航里程", value: "\(s?.range ?? 0)", unit: "km",
                         symbol: "bolt.car.fill", tint: .yellow)
            }
            HStack(spacing: 12) {
                StatTile(title: "车速", value: "\(Int(s?.speed ?? 0))", unit: "km/h",
                         symbol: "speedometer", tint: .green)
                StatTile(title: "车外温度", value: "\(s?.tempOut ?? 0)", unit: "℃",
                         symbol: "thermometer.medium", tint: .orange)
            }
            GlassCard(padding: 14) {
                HStack {
                    chip("车锁", (s?.locked ?? false) ? "已锁" : "未锁",
                         (s?.locked ?? false) ? .green : .orange,
                         "lock.fill")
                    Divider().frame(height: 26).overlay(Color.white.opacity(0.12))
                    chip("空调", (s?.acOn ?? false) ? "开" : "关",
                         (s?.acOn ?? false) ? Theme.accent : .gray, "snowflake")
                    Divider().frame(height: 26).overlay(Color.white.opacity(0.12))
                    chip("数据", s?.time ?? "--", .gray, "clock")
                }
            }
        }
    }

    private func chip(_ title: String, _ value: String, _ tint: Color, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 10.5))
            }
            .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 快捷指令

    private var commandGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷控制")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.leading, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: 10) {
                ForEach(Command.all) { c in
                    GlassButton(title: c.title, symbol: c.symbol, danger: c.danger) {
                        Task { await app.run(c.cmd) }
                    }
                    .disabled(app.busy)
                    .opacity(app.busy ? 0.55 : 1)
                }
            }
        }
    }

    private var footer: some View {
        Text(app.busy ? "执行中…" : "下拉刷新车况")
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.3))
            .padding(.top, 6)
    }
}

struct ToastView: View {
    let text: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
            Text(text).font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder((ok ? Color.green : Theme.danger).opacity(0.5), lineWidth: 1))
        .padding(.top, 6)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

struct SettingsView: View {
    @EnvironmentObject var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pin = Store.get("pinCode") ?? ""

    var body: some View {
        NavigationStack {
            List {
                Section("控车码") {
                    TextField("6 位数字，部分车型需要", text: $pin)
                        .keyboardType(.numberPad)
                        .onChange(of: pin) { _, v in
                            let clean = String(v.filter(\.isNumber).prefix(8))
                            if clean != v { pin = clean }
                            Store.set(clean, for: "pinCode")
                        }
                }
                Section {
                    Button("退出登录", role: .destructive) {
                        app.logout()
                        dismiss()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
