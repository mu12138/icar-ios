import Foundation

/// 构建时由 scripts/gen-web-hashes.py 生成。启动时拿它和包里的网页文件比对。
enum WebHashes {
    static let map: [String: String] = [
        "index.html": "a735a9dd8b2cb8dfde3f9e7c190a4f93a3d71ca8d1c6df9e7613b2eaeb704215",
        "js/app.js": "fbcd4848348de9e1ba0960cbee74424dca9eb6f986588fc9eeda8bc49c63d1b2",
        "js/viewer3d.js": "73ac6644a0f438f1edea4ace06f3d6678ff567c404f0f08ddd2dccb933f9fda9",
        "js/overlay.js": "19c3bf575bae8adbcb9862c63e24eec089163f6a85178880a739d4d3bded951f",
        "css/app.css": "aeec8140b5d9de03e318e014c6e49a16599a9a35778a71521aa00cb2b33c6f5c",
    ]
}
