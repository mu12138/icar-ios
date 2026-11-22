import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppModel
    @State private var pending: Command?
    @State private var confirmOn = Store.get("confirm") == "1"
    @State private var showSettings = false
    @State private var showTrips = false
    @State private var showPano = false
    @State private var loc: ChangAnAPI.CarLocation?
    @State private var trips: [ChangAnAPI.Trip] = []
    @State private var photos: [ChangAnAPI.PanoPhoto] = []
    @State private var logs: [ChangAnAPI.ActionRecord] = []
    @State private var showDetail = false
    @State private var showCabin = false

    private var s: CarStatus? { app.status }

    var body: some View {
        ZStack {
            Backdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    if let u = app.update {
                        UpdateBar(info: u) { app.update = nil }
                    }
                    brandRow
                    carTitle
                    chips
                    stage
                    stats
                    quickControl
                    panoCard
                    tripCard
                    logCard
                    locCard
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .refreshable { await reload() }
        }
        .preferredColorScheme(.dark)
        .task {
            await reload()
            await app.checkUpdate()
        }
        .sheet(isPresented: $showSettings) {
            SettingsView().environmentObject(app)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTrips) {
            TripsView()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPano) {
            PanoramaView()
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDetail) {
            DetailSheet(s: s)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCabin) {
            CabinView(speed: Int(s?.speed ?? 0), water: Int(s?.waterTemp ?? 0))
                .presentationDragIndicator(.visible)
        }
        .alert("确定执行？", isPresented: Binding(
            get: { pending != nil },
            set: { if !$0 { pending = nil } }
        ), presenting: pending) { c in
            Button("取消", role: .cancel) { pending = nil }
            Button("执行") {
                let cmd = c
                pending = nil
                Task { await app.run(cmd.cmd, title: cmd.title, open: cmd.open) }
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

    // MARK: - 顶部

    private var brandRow: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.accent).frame(width: 6, height: 6)
            Text("岁岁长安").font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
            Spacer()
            Button { Task { await reload() } } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white.opacity(0.85))
            }
            Button { showSettings = true } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(.ultraThinMaterial, in: Circle())
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .padding(.top, 6)
    }

    private var carTitle: some View {
        HStack {
            Text(app.carName)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Spacer()
        }
    }

    private var chips: some View {
        HStack(spacing: 7) {
            pill((s?.locked ?? false) ? "已锁车" : "未锁车",
                 (s?.locked ?? false) ? .green : .orange)
            pill((s?.online ?? false) ? "在线" : "离线",
                 (s?.online ?? false) ? .green : .gray)
            pill(s?.time ?? "--", .white.opacity(0.6))
            pill("\(Int(s?.odo ?? 0)) km", .white.opacity(0.6))
            Spacer()
        }
    }

    private func pill(_ t: String, _ c: Color) -> some View {
        Text(t)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(c.opacity(0.35), lineWidth: 1))
            .foregroundStyle(c)
    }

    // MARK: - 3D 车模

    private var stage: some View {
        ZStack {
            if let st = s {
                CarStageView(modelFile: modelFile, apiData: st.apiData)
                    .frame(height: 210)
                    .onTapGesture(count: 2) { showDetail = true }
                    .onLongPressGesture(minimumDuration: 0.8) { showCabin = true }
            } else {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 210)
                    .overlay(ProgressView().tint(.white))
            }
        }
    }

    private var modelFile: String {
        let code = Store.get("seriesCode") ?? ""
        let map: [String: String] = [
            "C211": "C211.glb", "C236": "C236.glb", "C281": "C281.glb",
            "C589": "C589.glb", "CD569": "CD569.glb", "S202": "S202.glb",
            "S203": "S203.glb", "S311": "S311.glb",
        ]
        for (k, v) in map where code.hasPrefix(k) { return v }
        return "C211.glb"
    }

    // MARK: - 四宫格

    private var stats: some View {
        HStack(spacing: 8) {
            statTile("剩余油量", "\(s?.fuel ?? 0)", "%", "fuelpump.fill", Theme.accent,
                     progress: Double(s?.fuel ?? 0) / 100)
            statTile("续航里程", "\(s?.range ?? 0)", "km", "bolt.car.fill", .yellow)
            statTile("平均油耗", s?.avgOilText ?? "--", "L", "drop.fill", .orange)
            statTile("车外温度", "\(s?.tempOut ?? 0)", "℃", "thermometer.medium", .cyan)
        }
    }

    private func statTile(_ title: String, _ value: String, _ unit: String,
                          _ symbol: String, _ tint: Color, progress: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 19, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(.system(size: 9.5))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            if let p = progress {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(tint.opacity(0.8))
                            .frame(width: max(0, min(1, p)) * g.size.width)
                    }
                }
                .frame(height: 3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
        )
    }

    // MARK: - 快捷控制

    private var quickControl: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("快捷控制", nil)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 4),
                      spacing: 9) {
                ForEach(Command.all) { c in
                    GlassButton(title: c.title, symbol: c.symbol, danger: c.danger) { fire(c) }
                        .disabled(app.busy)
                        .opacity(app.busy ? 0.55 : 1)
                }
            }
        }
        .padding(.top, 4)
    }

    private func sectionTitle(_ t: String, _ right: String?) -> some View {
        HStack {
            Text(t).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
            Spacer()
            if let r = right {
                Text(r).font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 4)
    }

    // MARK: - 卡片

    private var panoCard: some View {
        VStack(spacing: 8) {
            sectionTitle("360 全景", photos.isEmpty ? nil : "全部")
            GlassCard(padding: 10) {
                if photos.isEmpty {
                    Text("暂无照片").font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity).padding(.vertical, 18)
                } else {
                    HStack(spacing: 6) {
                        ForEach(photos.prefix(3)) { p in
                            AsyncImage(url: URL(string: p.thumb)) { img in
                                img.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(Color.white.opacity(0.06))
                            }
                            .frame(height: 62)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }
            .onTapGesture { showPano = true }
        }
    }

    private var tripCard: some View {
        VStack(spacing: 8) {
            sectionTitle("我的轨迹", trips.isEmpty ? nil : "全部")
            GlassCard(padding: 14) {
                if trips.isEmpty {
                    Text("暂无记录").font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                } else {
                    VStack(spacing: 8) {
                        ForEach(trips.prefix(2)) { t in
                            HStack {
                                Text("\(hm(t.start)) - \(hm(t.end))")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                Spacer()
                                Text(String(format: "%.1f km", t.mileage))
                                    .font(.system(size: 11.5))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                }
            }
            .onTapGesture { showTrips = true }
        }
    }

    private var logCard: some View {
        VStack(spacing: 8) {
            sectionTitle("操作记录", nil)
            GlassCard(padding: 14) {
                if logs.isEmpty {
                    Text("暂无记录").font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.4))
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                } else {
                    VStack(spacing: 7) {
                        ForEach(logs.prefix(3)) { r in
                            HStack {
                                Text(r.name).font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.8)).lineLimit(1)
                                Spacer()
                                Text(r.status).font(.system(size: 11))
                                    .foregroundStyle(.white.opacity(0.4)).lineLimit(1)
                            }
                        }
                    }
                }
            }
        }
    }

    private var locCard: some View {
        VStack(spacing: 8) {
            sectionTitle("车辆位置", nil)
            GlassCard(padding: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 20)).foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(loc?.address.isEmpty == false ? loc!.address : "已定位")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white).lineLimit(1)
                        if let l = loc, l.lat != 0 || l.lng != 0 {
                            Text(String(format: "%.5f, %.5f", l.lat, l.lng))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    Spacer()
                    Button {
                        if let l = loc, l.lat != 0 || l.lng != 0,
                           let u = URL(string: "http://maps.apple.com/?daddr=\(l.lat),\(l.lng)&dirflg=d") {
                            UIApplication.shared.open(u)
                        }
                    } label: {
                        Text("导航").font(.system(size: 11.5, weight: .semibold))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.2), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
    }

    private var footer: some View {
        Text(app.busy ? "执行中…" : "数据来自长安车联网")
            .font(.system(size: 10.5))
            .foregroundStyle(.white.opacity(0.28))
            .padding(.top, 4)
    }

    private func hm(_ t: String) -> String {
        let parts = t.split(separator: " ")
        return parts.count >= 2 ? String(parts[1].prefix(5)) : "--"
    }

    // MARK: - 动作

    private func fire(_ c: Command) {
        if confirmOn { pending = c }
        else { Task { await app.run(c.cmd, title: c.title, open: c.open) } }
    }

    private func reload() async {
        await app.refresh()
        async let l = try? ChangAnAPI.location()
        async let t = try? ChangAnAPI.trips(days: 7)
        async let p = try? ChangAnAPI.panorama()
        async let g = try? ChangAnAPI.actions()
        loc = await l
        trips = await t ?? []
        photos = await p ?? []
        logs = await g ?? []
    }

    private func clearSoon(_ v: String?) {
        guard v != nil else { return }
        Task {
            try? await Task.sleep(nanoseconds: 2_400_000_000)
            app.toast = nil
            app.error = nil
        }
    }
}
