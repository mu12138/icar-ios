import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @State private var pending: Command?
    @State private var loc: ChangAnAPI.CarLocation?
    @State private var confirmOn = Store.get("confirm") == "1"

    private var s: CarStatus? { app.status }

    var body: some View {
        ZStack {
            Backdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    header
                    statusGrid
                    if let l = loc { locationCard(l) }
                    commandGrid
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await reload() }
        }
        .preferredColorScheme(.dark)
        .task { await reload() }
        .alert("确定执行？", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        ), presenting: pending) { c in
            Button("取消", role: .cancel) { pending = nil }
            Button("执行") {
                let cmd = c
                pending = nil
                Task { await app.run(cmd.cmd, open: cmd.open) }
            }
        } message: { c in
            Text("「\(c.title)」会立刻下发到车端")
        }
        .overlay(alignment: .top) {
            if let t = app.toast { ToastView(text: t, ok: true) }
            else if let e = app.error { ToastView(text: e, ok: false) }
        }
        .onChange(of: app.toast) { _, v in clearSoon(v) }
        .onChange(of: app.error) { _, v in clearSoon(v) }
    }

    private func reload() async {
        await app.refresh()
        loc = try? await ChangAnAPI.location()
    }

    private func clearSoon(_ v: String?) {
        guard v != nil else { return }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            app.toast = nil
            app.error = nil
        }
    }

    private func fire(_ c: Command) {
        if confirmOn { pending = c }
        else { Task { await app.run(c.cmd, open: c.open) } }
    }

    // MARK: 头部

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Circle()
                        .fill((s?.online ?? false) ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                    Text((s?.online ?? false) ? "在线 · \(s?.time ?? "")" : "离线")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Text(app.carName)
                    .font(.system(size: 25, weight: .bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button { Task { await reload() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.top, 8)
    }

    // MARK: 车况

    private var statusGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                StatTile(title: "剩余油量", value: "\(s?.fuel ?? 0)", unit: "%", symbol: "fuelpump.fill")
                StatTile(title: "续航里程", value: "\(s?.range ?? 0)", unit: "km", symbol: "bolt.car.fill", tint: .yellow)
            }
            HStack(spacing: 12) {
                StatTile(title: "车速", value: "\(Int(s?.speed ?? 0))", unit: "km/h", symbol: "speedometer", tint: .green)
                StatTile(title: "车外温度", value: "\(s?.tempOut ?? 0)", unit: "℃", symbol: "thermometer.medium", tint: .orange)
            }
            GlassCard(padding: 14) {
                HStack {
                    chip("车锁", (s?.locked ?? false) ? "已锁" : "未锁",
                         (s?.locked ?? false) ? .green : .orange, "lock.fill")
                    divider
                    chip("空调", (s?.acOn ?? false) ? "开 \(s?.acTemp ?? "")℃" : "关",
                         (s?.acOn ?? false) ? Theme.accent : .gray, "snowflake")
                    divider
                    chip("里程", "\(Int(s?.odo ?? 0))", .white.opacity(0.8), "gauge.with.dots.needle.bottom.50percent")
                }
            }
            GlassCard(padding: 14) {
                VStack(spacing: 10) {
                    HStack {
                        chip("车门", doorText, (s?.doors.contains(true) ?? false) ? .orange : .green, "car.side")
                        divider
                        chip("车窗", winText, (s?.windows.contains(true) ?? false) ? .orange : .green, "rectangle.split.3x1")
                        divider
                        chip("天窗", (s?.sunroof ?? false) ? "开" : "关",
                             (s?.sunroof ?? false) ? .orange : .green, "sunroof")
                    }
                }
            }
        }
    }

    private var doorText: String {
        guard let d = s?.doors else { return "--" }
        return d.contains(true) ? "已开" : "全关"
    }
    private var winText: String {
        guard let w = s?.windows else { return "--" }
        return w.contains(true) ? "已开" : "全关"
    }

    private var divider: some View {
        Divider().frame(height: 26).overlay(Color.white.opacity(0.12))
    }

    private func chip(_ title: String, _ value: String, _ tint: Color, _ symbol: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                Text(title).font(.system(size: 10.5))
            }
            .foregroundStyle(.white.opacity(0.45))
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: 位置

    private func locationCard(_ l: ChangAnAPI.CarLocation) -> some View {
        GlassCard(padding: 14) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("车辆位置")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.45))
                    Text(l.address.isEmpty ? "已定位" : l.address)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer()
                Button {
                    openMap(l)
                } label: {
                    Text("导航")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.accent.opacity(0.2), in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private func openMap(_ l: ChangAnAPI.CarLocation) {
        guard l.lat != 0 || l.lng != 0 else { return }
        let url = "http://maps.apple.com/?daddr=\(l.lat),\(l.lng)&dirflg=d"
        if let u = URL(string: url) { UIApplication.shared.open(u) }
    }

    // MARK: 指令

    private var commandGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷控制")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .padding(.leading, 4)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                      spacing: 10) {
                ForEach(Command.all) { c in
                    GlassButton(title: c.title, symbol: c.symbol, danger: c.danger) { fire(c) }
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
