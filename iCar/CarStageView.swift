import SwiftUI
import WebKit

/// 用 WKWebView 跑和 Android 同一套 three.js 车模，保证外观一致
struct CarStageView: UIViewRepresentable {
    let modelFile: String
    let apiData: [String: Any]

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .clear
        wv.scrollView.isScrollEnabled = false
        wv.scrollView.backgroundColor = .clear
        wv.scrollView.isUserInteractionEnabled = true

        context.coordinator.web = wv
        context.coordinator.modelFile = modelFile
        // 走本机 HTTP 服务：file:// 下 three.js 的 fetch 会被 WebKit 拦掉，车模加载不出来
        CarWebServer.shared.start()
        context.coordinator.load(wv)
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.push(apiData)
    }

    final class Coordinator {
        weak var web: WKWebView?
        var modelFile: String = "C211.glb"
        private var lastJSON = ""
        private var tries = 0

        /// 服务端口可能还没就绪，最多等 2 秒
        func load(_ wv: WKWebView) {
            if let u = CarWebServer.shared.pageURL(model: modelFile) {
                wv.load(URLRequest(url: u))
                return
            }
            tries += 1
            if tries > 20 { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                self.load(wv)
            }
        }

        func push(_ data: [String: Any]) {
            guard let wv = web else { return }
            guard let d = try? JSONSerialization.data(withJSONObject: data),
                  let s = String(data: d, encoding: .utf8) else { return }
            if s == lastJSON { return }          // 没变化就别反复推
            lastJSON = s
            let js = "window.setCarStatus(\(s));"
            // 页面可能还没加载完，延迟再试
            wv.evaluateJavaScript(js) { _, _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    wv.evaluateJavaScript(js, completionHandler: nil)
                }
            }
        }
    }
}
