import Foundation

/// 构建时由 scripts/gen-web-hashes.py 生成。启动时拿它和包里的网页文件比对。
enum WebHashes {
    static let map: [String: String] = [
        "index.html": "db2635e7bf5bcf7eeec0f2ec15a70383a3a925b4382f685c5d3c2190f5c0687c",
        "js/app.js": "c0f85d99689fb6a0ce94f9dee7ceed964f53051cce2eeef3ebfa2da94e597811",
        "js/viewer3d.js": "752c7b70fb4a14b180e44e31868f8a3a7123be3c411fc6e4e75b9f73d48922c8",
        "js/overlay.js": "19c3bf575bae8adbcb9862c63e24eec089163f6a85178880a739d4d3bded951f",
        "css/app.css": "aeec8140b5d9de03e318e014c6e49a16599a9a35778a71521aa00cb2b33c6f5c",
    ]
}
