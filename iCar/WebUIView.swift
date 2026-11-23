import SwiftUI
import UIKit
import WebKit

/// 主界面：直接用安卓那套网页界面（index.html + app.css + app.js），
/// 这样两边 UI 天然一模一样；原生只负责数据（NativeBridge）和本地 HTTP 服务。
struct WebUIView: UIViewRepresentable {
    func makeUIView(context: Context) -> WKWebView {
        CarWebServer.shared.start()

        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []

        let uc = WKUserContentController()
        uc.add(NativeBridge.shared, name: "icar")
        uc.addUserScript(WKUserScript(source: NativeBridge.shimJS,
                                      injectionTime: .atDocumentStart,
                                      forMainFrameOnly: true))
        cfg.userContentController = uc

        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.bounces = false
        wv.uiDelegate = NativeBridge.shared
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = false

        NativeBridge.shared.webView = wv
        context.coordinator.webView = wv
        context.coordinator.startLoading()
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }



    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var loaded = false

        /// 本地服务是随机端口、异步就绪，起好了再加载页面
        func startLoading() {
            Task { @MainActor in
                for _ in 0..<100 {
                    if let u = CarWebServer.shared.uiURL() {
                        if !self.loaded, let wv = self.webView {
                            self.loaded = true
                            wv.load(URLRequest(url: u))
                        }
                        return
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }

        /// 页面里的外链（抖音、更新包）交给系统浏览器
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let u = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if u.scheme == "http" || u.scheme == "https" {
                if u.host == "127.0.0.1" || u.host == "localhost" {
                    decisionHandler(.allow)
                } else {
                    UIApplication.shared.open(u)
                    decisionHandler(.cancel)
                }
            } else {
                UIApplication.shared.open(u)
                decisionHandler(.cancel)
            }
        }
    }
}
