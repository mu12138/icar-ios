import Foundation
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    @Published var loggedIn = ChangAnAPI.loggedIn
    @Published var carName = Store.get("carName") ?? "我的车"
    @Published var status: CarStatus?
    @Published var busy = false
    @Published var toast: String?
    @Published var error: String?
    @Published var update: UpdateCheck.Info?

    func sendCode(_ phone: String) async {
        busy = true
        defer { busy = false }
        do {
            try await ChangAnAPI.sendCode(phone: phone)
            toast = "验证码已发送"
        } catch {
            self.error = error.localizedDescription
        }
    }

    func login(phone: String, code: String) async {
        busy = true
        defer { busy = false }
        do {
            carName = try await ChangAnAPI.login(phone: phone, code: code)
            loggedIn = true
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func refresh() async {
        do {
            status = try await ChangAnAPI.status()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func run(_ cmd: String, open: Bool = false) async {
        busy = true
        defer { busy = false }
        do {
            if open {
                toast = try await ChangAnAPI.openExec(cmd)
            } else {
                toast = try await ChangAnAPI.exec(cmd)
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await refresh()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func checkUpdate() async {
        guard let info = await UpdateCheck.fetch() else { return }
        let cur = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        if info.code > (Int(cur) ?? 0) { update = info }
    }

    func logout() {
        ChangAnAPI.logout()
        loggedIn = false
        status = nil
    }
}
