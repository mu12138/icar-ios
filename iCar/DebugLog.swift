import Foundation

/// 简单的环形日志，出问题时把内容截图给开发者
final class DebugLog: ObservableObject {
    static let shared = DebugLog()
    @Published private(set) var lines: [String] = []
    private let lock = NSLock()

    func add(_ s: String) {
        let t = DateFormatter()
        t.dateFormat = "HH:mm:ss"
        let line = "[\(t.string(from: Date()))] \(s)"
        lock.lock()
        lines.append(line)
        if lines.count > 120 { lines.removeFirst(lines.count - 120) }
        lock.unlock()
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    func clear() {
        lock.lock(); lines.removeAll(); lock.unlock()
        DispatchQueue.main.async { self.objectWillChange.send() }
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

/// 数值解析：车端可能给数字、字符串或 null
func num(_ v: Any?) -> Double {
    if let n = v as? NSNumber { return n.doubleValue }
    if let s = v as? String {
        let t = s.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.lowercased() == "null" { return 0 }
        return Double(t) ?? 0
    }
    return 0
}
