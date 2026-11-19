import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        if app.loggedIn {
            TabView {
                HomeView()
                    .tabItem { Label("车控", systemImage: "car.side.fill") }
                TripsView()
                    .tabItem { Label("轨迹", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                PanoramaView()
                    .tabItem { Label("全景", systemImage: "camera.viewfinder") }
                SettingsView()
                    .tabItem { Label("设置", systemImage: "gearshape.fill") }
            }
            .tint(Theme.accent)
        } else {
            LoginView()
        }
    }
}
