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

        guard let url = Bundle.main.url(forResource: "carview", withExtension: "html",
                                        subdirectory: "CarWeb") else {
            return wv
        }
        var comp = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comp?.queryItems = [URLQueryItem(name: "model", value: modelFile)]
        if let u = comp?.url {
            wv.loadFileURL(u, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        context.coordinator.web = wv
        return wv
    }

    func updateUIView(_ wv: WKWebView, context: Context) {
        context.coordinator.push(apiData)
    }

    final class Coordinator {
        weak var web: WKWebView?
        private var lastJSON = ""

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
