import Foundation

/// 调试日志：内存留最近 120 行，同时落一份到 `Documents/bridge.log`。
/// 出问题直接去 Files App 里取这个文件，比截图快。
final class DebugLog {
    static let shared = DebugLog()

    private let lock = NSLock()
    private var lines: [String] = []
    private let fileQueue = DispatchQueue(label: "cn.icar.debuglog.file")

    static var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("bridge.log")
    }

    func add(_ s: String) {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        let line = "[\(f.string(from: Date()))] \(s)"
        lock.lock()
        lines.append(line)
        if lines.count > 120 { lines.removeFirst(lines.count - 120) }
        lock.unlock()
        appendToFile(line)
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    func clear() {
        lock.lock(); lines.removeAll(); lock.unlock()
        fileQueue.async { try? FileManager.default.removeItem(at: Self.fileURL) }
    }

    /// 超过 400KB 只留后半段，别把手机撑爆
    private func appendToFile(_ line: String) {
        let url = Self.fileURL
        let data = Data((line + "\n").utf8)
        fileQueue.async {
            let fm = FileManager.default
            if let attrs = try? fm.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber, size.intValue > 400_000,
               let old = try? Data(contentsOf: url) {
                try? Data(old.suffix(200_000)).write(to: url)
            }
            if let h = try? FileHandle(forWritingTo: url) {
                h.seekToEndOfFile()
                h.write(data)
                try? h.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
