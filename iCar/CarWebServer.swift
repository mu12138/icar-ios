import Foundation
import Network

/// 给 3D 车模用的本机 HTTP 服务。
///
/// 为什么需要它：WKWebView 用 file:// 打开页面时，three.js 的 GLTFLoader / RGBELoader
/// 走的是 fetch，WebKit 会拦掉（跨源 + file 协议），结果就是「背景有、车是空的」。
/// 安卓版也是靠本机 HTTP 服务喂 three.js 的，这里照同一套做。
final class CarWebServer {
    static let shared = CarWebServer()

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "cn.icar.carweb.server")
    private(set) var port: UInt16 = 0

    /// 车模资源目录（bundle 里的 CarWeb）
    private var rootDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("CarWeb")
    }

    /// 安卓那套网页界面（bundle 里的 WebUI）；3D 模型仍从 CarWeb 取，避免仓库里存两份
    private var uiDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("WebUI")
    }

    func start() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            params.requiredInterfaceType = .loopback
            let l = try NWListener(using: params, on: .any)
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.stateUpdateHandler = { [weak self] state in
                if case .ready = state, let p = l.port?.rawValue {
                    self?.port = p
                    NSLog("CarWebServer ready on 127.0.0.1:\(p)")
                }
            }
            l.start(queue: queue)
            listener = l
        } catch {
            NSLog("CarWebServer start failed: \(error)")
        }
    }

    /// 网页版车控界面地址（index.html）
    func uiURL() -> URL? {
        guard port > 0 else { return nil }
        var c = URLComponents()
        c.scheme = "http"
        c.host = "127.0.0.1"
        c.port = Int(port)
        c.path = "/index.html"
        return c.url
    }

    /// 页面地址；服务还没起来返回 nil
    func pageURL(model: String) -> URL? {
        guard port > 0 else { return nil }
        var c = URLComponents()
        c.scheme = "http"
        c.host = "127.0.0.1"
        c.port = Int(port)
        c.path = "/carview.html"
        c.queryItems = [URLQueryItem(name: "model", value: model)]
        return c.url
    }

    // MARK: - 连接处理

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        readRequest(conn, buffer: Data())
    }

    private func readRequest(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isDone, err in
            guard let self = self else { conn.cancel(); return }
            if err != nil { conn.cancel(); return }
            var buf = buffer
            if let d = data { buf.append(d) }
            // 头部收全了（\r\n\r\n）就够判断请求行了
            if let headEnd = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(data: buf.subdata(in: 0..<headEnd.lowerBound), encoding: .utf8) ?? ""
                self.respond(conn, head: head)
            } else if isDone || buf.count > 256 * 1024 {
                conn.cancel()
            } else {
                self.readRequest(conn, buffer: buf)
            }
        }
    }

    private func respond(_ conn: NWConnection, head: String) {
        let first = head.split(separator: "\r\n").first.map(String.init) ?? ""
        let parts = first.split(separator: " ")
        guard parts.count >= 2 else { send(conn, status: "400 Bad Request", mime: "text/plain", body: Data()); return }
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        // 防目录穿越
        let clean = path.removingPercentEncoding ?? path
        var rel = clean.hasPrefix("/") ? String(clean.dropFirst()) : clean
        if rel.isEmpty { rel = "index.html" }
        if rel.contains("..") { send(conn, status: "403 Forbidden", mime: "text/plain", body: Data()); return }

        // 先找网页界面目录，再退回车模目录（3D/*.glb 在 CarWeb 里）
        var file: URL?
        for dir in [uiDir, rootDir].compactMap({ $0 }) {
            let f = dir.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: f.path) { file = f; break }
        }
        // 网页里写的是 3D/xxx.glb，但模型只放了一份在 CarWeb/3D
        if file == nil, rel.hasPrefix("3D/") {
            let f = rootDir?.appendingPathComponent(rel)
            if let f = f, FileManager.default.fileExists(atPath: f.path) { file = f }
        }
        if file == nil, rel == "carview.html" {
            let f = rootDir?.appendingPathComponent("carview.html")
            if let f = f, FileManager.default.fileExists(atPath: f.path) { file = f }
        }
        guard let file = file, let body = try? Data(contentsOf: file) else {
            send(conn, status: "404 Not Found", mime: "text/plain", body: Data("not found".utf8)); return
        }
        send(conn, status: "200 OK", mime: mime(for: file.pathExtension), body: body)
    }

    private func send(_ conn: NWConnection, status: String, mime: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(mime)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Connection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func mime(for ext: String) -> String {
        switch ext.lowercased() {
        case "html", "htm": return "text/html; charset=utf-8"
        case "js", "mjs": return "application/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json"
        case "glb": return "model/gltf-binary"
        case "gltf": return "model/gltf+json"
        case "hdr": return "application/octet-stream"
        case "bin": return "application/octet-stream"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        case "wasm": return "application/wasm"
        default: return "application/octet-stream"
        }
    }
}
