import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        if app.loggedIn {
            HomeView()
        } else {
            LoginView()
        }
    }
}
