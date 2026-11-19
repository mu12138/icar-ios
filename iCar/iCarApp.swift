import SwiftUI

@main
struct iCarApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(app)
        }
    }
}
