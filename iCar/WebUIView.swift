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
        uc.addUserScript(WKUserScript(source: Self.iosHideJS,
                                      injectionTime: .atDocumentEnd,
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

    /// iOS 上没有的东西：通知触发（安卓靠通知使用权监听）、语音触发入口、后台常驻、
    /// 自启动/省电策略、指令写法列表。网页是安卓共用的那份，所以在这里藏掉，不动原文件。
    static let iosHideJS = """
    (function () {
      function hide(el) { if (el) el.style.display = 'none'; }
      function apply() {
        // 通知触发 / 后台常驻 / 锁屏保护 / 小组件自动刷新（iOS 没有）
        ['ntf', 'keep', 'ntfSafe', 'widgetNet'].forEach(function (k) {
          hide(document.querySelector('[data-k="' + k + '"]'));
        });
        // 通知使用权、通知记录、自启动、省电策略
        document.querySelectorAll('[data-act="auth"],[data-act="ntflog"],[data-act="perm"]').forEach(hide);
        // 「语音触发 · 加入抖音群」标题（带抖音主页按钮）
        document.querySelectorAll('.set-hd.hd-row').forEach(hide);
        // 「后台权限 · 建议开启」「指令写法 · 点一下复制」标题和它下面的列表
        document.querySelectorAll('.set-hd').forEach(function (h) {
          var t = h.textContent || '';
          if (t.indexOf('后台权限') >= 0 || t.indexOf('指令写法') >= 0) {
            hide(h);
            hide(h.nextElementSibling);
          }
        });
        // 整块都被藏空的列表，连留白也去掉
        document.querySelectorAll('.set-list').forEach(function (list) {
          var vis = Array.prototype.filter.call(list.children, function (c) {
            return c.style.display !== 'none';
          });
          if (!vis.length) hide(list);
        });
        hide(document.getElementById('cmd-list'));
      }
      apply();
      document.addEventListener('DOMContentLoaded', apply);
      try {
        var pending = false;
        new MutationObserver(function () {
          if (pending) return;
          pending = true;
          requestAnimationFrame(function () { pending = false; apply(); });
        }).observe(document.documentElement, { childList: true, subtree: true });
      } catch (e) {}
    })();
    """


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
