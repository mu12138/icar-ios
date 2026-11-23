import SwiftUI

@main
struct iCarApp: App {
    init() {
        // 照片缩略图 / 3D 资源走本地服务，但不是每次都值得重下；给个更大的缓存
        URLCache.shared = URLCache(memoryCapacity: 32 << 20,
                                   diskCapacity: 256 << 20,
                                   diskPath: "icar-cache")
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
