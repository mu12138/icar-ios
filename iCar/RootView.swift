import SwiftUI

struct RootView: View {
    var body: some View {
        // 整个界面就是安卓那套网页（iCar/WebUI），原生只提供 NativeBridge（数据 + 系统能力）。
        WebUIView()
            .ignoresSafeArea()
    }
}
