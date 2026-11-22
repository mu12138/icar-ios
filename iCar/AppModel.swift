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

    func run(_ cmd: String, title: String = "", open: Bool = false) async {
        if busy { return }
        busy = true
        defer { busy = false }
        let name = title.isEmpty ? cmd : title
        // 先给个即时反馈，别让用户以为没点上
        error = nil
        toast = "正在下发 · \(name)"
        DebugLog.shared.add("指令 \(cmd) 开始下发")
        // 5 秒还没回来就提示一句，长轮询时界面不会像卡死
        let hint = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled, self.busy { self.toast = "等待车端确认 · \(name)" }
        }
        do {
            let r = try await (open ? ChangAnAPI.openExec(cmd) : ChangAnAPI.exec(cmd))
            hint.cancel()
            DebugLog.shared.add("指令 \(cmd) 返回：\(r)")
            toast = "\(name) · \(r)"
            try? await Task.sleep(nanoseconds: 800_000_000)
            await refresh()
        } catch {
            hint.cancel()
            let msg = error.localizedDescription
            DebugLog.shared.add("指令 \(cmd) 失败：\(msg)")
            self.error = "\(name) 失败：\(msg)"
            toast = nil
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
