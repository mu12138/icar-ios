import Foundation

/// 构建时由 scripts/gen-web-hashes.py 生成。启动时拿它和包里的网页文件比对。
enum WebHashes {
    static let map: [String: String] = [
        "index.html": "74b260b5ff0ed832e0a7b3ee3a595735a6d717bba90798715cc0c279a8e4e4aa",
        "js/app.js": "10e682a719c3a6848a55e5a79ec94e2684fb43e437e6971b2827613d1a1756e8",
        "js/viewer3d.js": "73ac6644a0f438f1edea4ace06f3d6678ff567c404f0f08ddd2dccb933f9fda9",
        "js/overlay.js": "19c3bf575bae8adbcb9862c63e24eec089163f6a85178880a739d4d3bded951f",
        "css/app.css": "aeec8140b5d9de03e318e014c6e49a16599a9a35778a71521aa00cb2b33c6f5c",
    ]
}
