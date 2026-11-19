import SwiftUI

@main
struct iCarApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if app.loggedIn {
                    HomeView().environmentObject(app)
                } else {
                    LoginView().environmentObject(app)
                }
            }
        }
    }
}
