import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        // 主界面改成安卓同款网页界面；登录、免责声明、车况、指令都由页面自己管，
        // 原生只提供 NativeBridge（数据 + 系统能力）。
        WebUIView()
            .ignoresSafeArea()
    }
}
