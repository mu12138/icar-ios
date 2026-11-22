import SwiftUI

struct TripsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var trips: [ChangAnAPI.Trip] = []
    @State private var days = 1
    @State private var loading = false
    @State private var err: String?

    var body: some View {
        ZStack {
            Backdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack {
                        Text("我的轨迹")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                        Spacer()
                        Picker("", selection: $days) {
                            Text("今天").tag(1)
                            Text("7 天").tag(7)
                            Text("30 天").tag(30)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                        .onChange(of: days) { _, _ in Task { await load() } }
                        CloseButton { dismiss() }
                    }
                    .padding(.top, 8)

                    if loading && trips.isEmpty {
                        ProgressView().tint(.white).padding(.top, 40)
                    } else if let e = err {
                        Text(e).font(.system(size: 13)).foregroundStyle(Theme.danger).padding(.top, 30)
                    } else if trips.isEmpty {
                        Text("这段时间没有行驶记录")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 40)
                    } else {
                        summary
                        ForEach(trips) { t in tripCard(t) }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await load() }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var summary: some View {
        let km = trips.reduce(0) { $0 + $1.mileage }
        let oil = trips.reduce(0) { $0 + $1.oil }
        return GlassCard(padding: 14) {
            HStack {
                VStack(spacing: 3) {
                    Text(String(format: "%.1f", km))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("里程 km").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                }.frame(maxWidth: .infinity)
                Divider().frame(height: 30).overlay(Color.white.opacity(0.12))
                VStack(spacing: 3) {
                    Text("\(trips.count)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("行程").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                }.frame(maxWidth: .infinity)
                Divider().frame(height: 30).overlay(Color.white.opacity(0.12))
                VStack(spacing: 3) {
                    Text(String(format: "%.1f", oil))
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("油耗 L").font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                }.frame(maxWidth: .infinity)
            }
        }
    }

    private func tripCard(_ t: ChangAnAPI.Trip) -> some View {
        GlassCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("\(hm(t.start)) - \(hm(t.end))")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(String(format: "%.1f L", t.oil))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                HStack(spacing: 6) {
                    Text(t.from.isEmpty ? "未知" : t.from)
                        .lineLimit(1)
                    Image(systemName: "arrow.right").font(.system(size: 9))
                    Text(t.to.isEmpty ? "未知" : t.to)
                        .lineLimit(1)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.5))

                HStack(spacing: 14) {
                    tag("里程", String(format: "%.1f km", t.mileage))
                    tag("均速", "\(Int(t.speed)) km/h")
                }
            }
        }
    }

    private func tag(_ k: String, _ v: String) -> some View {
        HStack(spacing: 4) {
            Text(k).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.4))
            Text(v).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.white.opacity(0.8))
        }
    }

    private func hm(_ t: String) -> String {
        let parts = t.split(separator: " ")
        guard parts.count >= 2 else { return "--" }
        return String(parts[1].prefix(5))
    }

    private func load() async {
        loading = true; err = nil
        defer { loading = false }
        do { trips = try await ChangAnAPI.trips(days: days) }
        catch { err = error.localizedDescription }
    }
}
