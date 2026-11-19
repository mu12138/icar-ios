import SwiftUI

struct PanoramaView: View {
    @State private var photos: [ChangAnAPI.PanoPhoto] = []
    @State private var loading = false
    @State private var capturing = false
    @State private var err: String?
    @State private var preview: ChangAnAPI.PanoPhoto?
    @State private var action: ChangAnAPI.PanoPhoto?
    @State private var toast: String?

    private var hidden: [String] {
        (try? JSONDecoder().decode([String].self,
            from: (Store.get("panoHidden") ?? "[]").data(using: .utf8) ?? Data())) ?? []
    }

    private var visible: [ChangAnAPI.PanoPhoto] {
        photos.filter { !hidden.contains($0.id) }
    }

    var body: some View {
        ZStack {
            Backdrop()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    HStack {
                        Text("360 全景")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                            .onLongPressGesture(minimumDuration: 0.8) { restore() }
                        Spacer()
                        Button {
                            Task { await capture() }
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: capturing ? "hourglass" : "camera.fill")
                                Text(capturing ? "拍摄中" : "车外拍照")
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(Theme.accent)
                        }
                        .disabled(capturing)
                    }
                    .padding(.top, 8)

                    if loading && photos.isEmpty {
                        ProgressView().tint(.white).padding(.top, 40)
                    } else if let e = err {
                        Text(e).font(.system(size: 13)).foregroundStyle(Theme.danger).padding(.top, 30)
                    } else if visible.isEmpty {
                        Text("暂无照片，点右上角拍一张")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 40)
                    } else {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
                            ForEach(visible) { p in
                                cell(p)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await load() }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
        .overlay(alignment: .top) {
            if let t = toast { ToastView(text: t, ok: true) }
        }
        .onChange(of: toast) { _, v in
            guard v != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                toast = nil
            }
        }
        .sheet(item: $preview) { p in
            ZStack {
                Color.black.ignoresSafeArea()
                AsyncImage(url: URL(string: p.url)) { img in
                    img.resizable().scaledToFit()
                } placeholder: {
                    ProgressView().tint(.white)
                }
            }
        }
        .confirmationDialog("这张照片", isPresented: Binding(
            get: { action != nil },
            set: { if !$0 { action = nil } }
        ), titleVisibility: .visible) {
            Button("删除（服务端）", role: .destructive) {
                if let p = action { Task { await del(p) } }
                action = nil
            }
            Button("隐藏（仅本机）") {
                if let p = action { hide(p) }
                action = nil
            }
            Button("取消", role: .cancel) { action = nil }
        }
    }

    private func cell(_ p: ChangAnAPI.PanoPhoto) -> some View {
        Button {
            preview = p
        } label: {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: p.thumb)) { img in
                    img.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(Color.white.opacity(0.06))
                }
                .frame(height: 118)
                .frame(maxWidth: .infinity)
                .clipped()

                Text(p.dirName)
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.ultraThinMaterial, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(8)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.75).onEnded { _ in action = p }
        )
    }

    private func hide(_ p: ChangAnAPI.PanoPhoto) {
        var h = hidden
        if !h.contains(p.id) { h.append(p.id) }
        if let d = try? JSONEncoder().encode(h), let s = String(data: d, encoding: .utf8) {
            Store.set(s, for: "panoHidden")
        }
        toast = "已隐藏这张照片"
    }

    private func restore() {
        Store.set("[]", for: "panoHidden")
        toast = "已恢复全部照片"
    }

    private func del(_ p: ChangAnAPI.PanoPhoto) async {
        do {
            try await ChangAnAPI.deletePhoto(id: p.id)
            toast = "已删除"
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await load()
        } catch {
            toast = "删除失败：\(error.localizedDescription)"
        }
    }

    private func capture() async {
        capturing = true
        defer { capturing = false }
        do {
            photos = try await ChangAnAPI.capture()
            toast = "已拍照"
        } catch {
            err = error.localizedDescription
        }
    }

    private func load() async {
        loading = true; err = nil
        defer { loading = false }
        do { photos = try await ChangAnAPI.panorama() }
        catch { err = error.localizedDescription }
    }
}
