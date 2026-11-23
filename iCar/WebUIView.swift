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
        wv.isOpaque = true
        wv.backgroundColor = .black
        wv.scrollView.backgroundColor = .black
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.keyboardDismissMode = .interactive      // 打字时上滑就能收键盘
        wv.scrollView.bounces = true
        wv.uiDelegate = NativeBridge.shared
        wv.navigationDelegate = context.coordinator
        wv.allowsBackForwardNavigationGestures = false

        NativeBridge.shared.webView = wv
        context.coordinator.webView = wv
        context.coordinator.startLoading()
        context.coordinator.observeForeground()
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var loaded = false
        private var retries = 0
        private var foregroundToken: NSObjectProtocol?

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

        /// 从后台切回来：车况可能已经变了，让页面自己刷一次
        func observeForeground() {
            foregroundToken = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil, queue: .main) { [weak self] _ in
                    guard let wv = self?.webView else { return }
                    wv.evaluateJavaScript(
                        "if (window.loadStatus) loadStatus(true);",
                        completionHandler: nil)
            }
        }

        deinit {
            if let t = foregroundToken { NotificationCenter.default.removeObserver(t) }
        }

        /// 页面顶栏要给状态栏让位：把 iOS 的安全区高度塞进 --sat / --sab
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            retries = 0
            let win = webView.window
            let top = max(win?.safeAreaInsets.top ?? 0, 44)
            let bottom = max(win?.safeAreaInsets.bottom ?? 0, 20)
            webView.evaluateJavaScript(
                "document.documentElement.style.setProperty('--sat','\(top)px');" +
                "document.documentElement.style.setProperty('--sab','\(bottom)px');",
                completionHandler: nil)
        }

        /// 首屏加载失败（服务还没起、被系统掐）自动重试，最多 3 次
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            guard retries < 3 else { return }
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.startLoading()
            }
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            guard retries < 3 else { return }
            retries += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.startLoading()
            }
        }

        /// 网页进程被系统回收（内存吃紧常见）：直接把页面重新拉起来
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            retries = 0
            startLoading()
        }

        /// 页面里的外链（抖音、下载包）交给系统浏览器
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
