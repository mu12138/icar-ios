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
        // 网络慢时给个「还在下发」的提示；拿到结果就立刻撤掉，绝不让它盖住后面的状态
        let hint = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled, self.busy,
               self.toast == nil || self.toast == "正在下发 · \(name)" {
                self.toast = "下发中，网络慢 · \(name)"
            }
        }
        do {
            let r: String
            if open {
                r = try await ChangAnAPI.openExec(cmd)
            } else {
                // 先只下发：成功发出就马上亮「已下发」，再慢慢等车端回执
                let taskId = try await ChangAnAPI.dispatch(cmd)
                hint.cancel()
                DebugLog.shared.add("指令 \(cmd) 已下发 taskId=\(taskId.isEmpty ? "-" : taskId)")
                toast = "已下发 · \(name)，等车端回执"
                if taskId.isEmpty {
                    r = "已下发"
                } else {
                    r = try await ChangAnAPI.pollResult(taskId)
                }
            }
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
