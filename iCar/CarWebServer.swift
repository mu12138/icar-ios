import Foundation
import Network

/// 本机 HTTP 服务：喂 `iCar/WebUI` 那套网页界面，同时把 3D 模型（CarWeb/3D）也发出去。
///
/// 为什么需要它：WKWebView 用 file:// 打开页面时，three.js 的 GLTFLoader / RGBELoader
/// 走的是 fetch，WebKit 会拦掉（跨源 + file 协议），结果就是「背景有、车是空的」。
/// 安卓版也是靠本机 HTTP 服务喂 three.js 的，这里照同一套做。
///
/// 端口优先固定 17822：页面里的 localStorage 是按「IP:端口」隔离的，
/// 随机端口会让这份备份存储每次重启都换一份；固定端口被占用时才退回随机。
final class CarWebServer {
    static let shared = CarWebServer()

    /// 优先尝试的固定端口
    static let preferredPort: UInt16 = 17822

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "cn.icar.carweb.server")
    private(set) var port: UInt16 = 0

    /// 车模资源目录（bundle 里的 CarWeb，只剩 3D 模型）
    private var rootDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("CarWeb")
    }

    /// 安卓那套网页界面（bundle 里的 WebUI）
    private var uiDir: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("WebUI")
    }

    func start() {
        guard listener == nil else { return }
        startListener(port: NWEndpoint.Port(rawValue: Self.preferredPort))
    }

    private func startListener(port wanted: NWEndpoint.Port?) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback
        do {
            let l = try NWListener(using: params, on: wanted ?? .any)
            l.newConnectionHandler = { [weak self] conn in
                self?.handle(conn)
            }
            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    if let p = l.port?.rawValue {
                        self.port = p
                        NSLog("CarWebServer ready on 127.0.0.1:\(p)")
                    }
                case .failed:
                    // 固定端口被别的进程占了：换随机端口再来一次
                    l.cancel()
                    if wanted != nil {
                        self.listener = nil
                        self.startListener(port: nil)
                    }
                default:
                    break
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
        guard parts.count >= 2 else { sendText(conn, status: "400 Bad Request", text: ""); return }
        let rawPath = String(parts[1])
        let path = rawPath.split(separator: "?").first.map(String.init) ?? rawPath
        // 防目录穿越
        let clean = path.removingPercentEncoding ?? path
        var rel = clean.hasPrefix("/") ? String(clean.dropFirst()) : clean
        if rel.isEmpty { rel = "index.html" }
        if rel.contains("..") { sendText(conn, status: "403 Forbidden", text: ""); return }

        // 自定义背景图：页面里用 url("__bg.jpg?v=…")，图存在 App 沙盒里
        if rel == "__bg.jpg" || rel == "_bg.jpg" {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let f = docs.appendingPathComponent("bg.jpg")
            if FileManager.default.fileExists(atPath: f.path) {
                sendFile(conn, status: "200 OK", mime: "image/jpeg", url: f)
            } else {
                sendText(conn, status: "404 Not Found", text: "no bg")
            }
            return
        }

        // 先找网页界面目录，再退回车模目录（3D/*.glb 在 CarWeb 里）
        var file: URL?
        for dir in [uiDir, rootDir].compactMap({ $0 }) {
            let f = dir.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: f.path) { file = f; break }
        }
        guard let file = file else {
            sendText(conn, status: "404 Not Found", text: "not found")
            return
        }
        sendFile(conn, status: "200 OK", mime: mime(for: file.pathExtension), url: file)
    }

    // MARK: - 发送

    private func sendText(_ conn: NWConnection, status: String, text: String) {
        send(conn, status: status, mime: "text/plain; charset=utf-8", body: Data(text.utf8))
    }

    private func send(_ conn: NWConnection, status: String, mime: String, body: Data) {
        let head = header(status: status, mime: mime, length: body.count)
        var out = Data(head.utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }

    private func header(status: String, mime: String, length: Int) -> String {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(mime)\r\n"
        head += "Content-Length: \(length)\r\n"
        head += "Access-Control-Allow-Origin: *\r\n"
        head += "Cache-Control: no-cache\r\n"
        head += "Connection: close\r\n\r\n"
        return head
    }

    /// 大文件（3D 模型 25M）分块发，避免整个读进内存
    private func sendFile(_ conn: NWConnection, status: String, mime: String, url: URL) {
        guard let fh = try? FileHandle(forReadingFrom: url) else {
            sendText(conn, status: "404 Not Found", text: "not found")
            return
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        conn.send(content: Data(header(status: status, mime: mime, length: size).utf8),
                  completion: .contentProcessed { _ in })
        stream(fh, conn)
    }

    private func stream(_ fh: FileHandle, _ conn: NWConnection) {
        let chunk: Data
        do {
            chunk = try fh.read(upToCount: 64 * 1024) ?? Data()
        } catch {
            try? fh.close()
            conn.cancel()
            return
        }
        if chunk.isEmpty {
            try? fh.close()
            conn.cancel()
            return
        }
        conn.send(content: chunk, isComplete: false, completion: .contentProcessed { [weak self] err in
            if err != nil {
                try? fh.close()
                conn.cancel()
                return
            }
            self?.stream(fh, conn)
        })
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
