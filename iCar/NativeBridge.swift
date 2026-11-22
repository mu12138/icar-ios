import Foundation
import UIKit
import WebKit

/// 安卓那套网页界面的原生桥（对应安卓的 Ui.java）。
///
/// 分工：
/// - 同步调用（state / kvGet / version / pinCode / accepted …）走 `prompt("icar:{…}")`，
///   在 WKUIDelegate 里当场返回字符串，JS 拿到的就是返回值。
/// - 异步调用（status / exec / trips …）走 `window.webkit.messageHandlers.icar`，
///   干完活再 `window.__cb(id, ok, msg)` 回调，和安卓的 evaluateJavascript(cb + "(...)") 等价。
final class NativeBridge: NSObject {

    static let shared = NativeBridge()

    weak var webView: WKWebView?

    /// 空调诊断：上一次尝试的逐条结果，页面点失败提示能看
    private(set) var lastAcLog = ""

    private let kvSuite = "icar_web"
    private let gateSuite = "gate"
    private var kv: UserDefaults { UserDefaults(suiteName: kvSuite) ?? .standard }
    private var gate: UserDefaults { UserDefaults(suiteName: gateSuite) ?? .standard }

    // MARK: - 注入给页面的 window.Native

    static let shimJS = """
    (function () {
      if (window.Native) return;
      var send = function (m, a) {
        return window.webkit.messageHandlers.icar.postMessage({ m: m, a: a || [] });
      };
      var call = function (m, a) {
        try { return prompt('icar:' + JSON.stringify({ m: m, a: a || [] })) || ''; }
        catch (e) { return ''; }
      };
      window.Native = {
        state:    function () { return call('state'); },
        kvGet:    function (k) { return call('kvGet', [k]); },
        kvSet:    function (k, v) { send('kvSet', [k, v]); },
        version:  function () { return call('version'); },
        pinCode:  function () { return call('pinCode'); },
        setPinCode: function (v) { send('setPinCode', [v]); },
        acDiag:   function () { return call('acDiag'); },
        accepted: function () { return call('accepted') === 'true'; },
        accept:   function () { send('accept', []); },
        ntfState: function () { return call('ntfState'); },
        ntfLog:   function () { return call('ntfLog'); },
        ntfCmds:  function () { return call('ntfCmds'); },
        ntfLast:  function () { return call('ntfLast'); },
        ntfClearLog: function () { send('ntfClearLog', []); },
        ntfOpen:  function () { send('ntfOpen', []); },
        ntfCopyCmd: function (c) { send('ntfCopyCmd', [c]); },
        toast:    function (t) { send('toast', [t]); },
        openUrl:  function (u) { send('openUrl', [u]); },
        openMap:  function (la, ln) { send('openMap', [la, ln]); },
        openAppSettings: function () { send('openAppSettings', []); },
        keepAlive: function (on) { send('keepAlive', [!!on]); },
        pickBg:   function (cb) { send('pickBg', [cb]); },
        clearBg:  function () { send('clearBg', []); },
        carMeta:  function (cb) { send('carMeta', [cb]); },
        status:   function (cb) { send('status', [cb]); },
        rawStatus: function (cb) { send('rawStatus', [cb]); },
        exec:     function (cmd, cb) { send('exec', [cmd, cb]); },
        sendCode: function (p, cb) { send('sendCode', [p, cb]); },
        login:    function (p, c, cb) { send('login', [p, c, cb]); },
        logout:   function () { send('logout', []); },
        air:      function (t, w, m, cb) { send('air', [t, w, m, cb]); },
        airOff:   function (cb) { send('airOff', [cb]); },
        location: function (cb) { send('location', [cb]); },
        actions:  function (p, n, cb) { send('actions', [p, n, cb]); },
        trips:    function (a, b, cb) { send('trips', [a, b, cb]); },
        photos:   function (cb) { send('photos', [cb]); },
        deletePhoto: function (id, name, taskId, cb) { send('deletePhoto', [id, name, taskId, cb]); },
        capture:  function (cb) { send('capture', [cb]); },
        updateInfo: function (cb) { send('updateInfo', [cb]); }
      };
    })();
    """

    // MARK: - 同步取值

    func syncValue(method: String, args: [Any]) -> String {
        switch method {
        case "state": return stateJSON()
        case "kvGet":
            let k = args.first as? String ?? ""
            return kv.string(forKey: k) ?? ""
        case "version": return versionString()
        case "pinCode": return Store.get("pinCode") ?? ""
        case "acDiag": return lastAcLog
        case "accepted": return gate.bool(forKey: "ok") ? "true" : "false"
        case "ntfState", "ntfLast": return "0"
        case "ntfLog", "ntfCmds": return ""
        default: return ""
        }
    }

    private func versionString() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private func stateJSON() -> String {
        var o: [String: Any] = [:]
        o["loggedIn"] = ChangAnAPI.loggedIn
        o["carName"] = Store.get("carName") ?? ""
        o["seriesCode"] = Store.get("seriesCode") ?? ""
        o["seriesName"] = Store.get("seriesName") ?? ""
        o["phone"] = Store.get("phone") ?? ""
        // 安卓那份 version.json 的 code 是安卓 versionCode，拿它比 iOS build 会误报更新
        o["versionCode"] = 0
        return Self.json(o)
    }

    // MARK: - 异步分发

    @MainActor
    func handle(message: String, args: [Any]) async {
        let cb = args.last as? String ?? ""
        let carId = args.first as? String ?? ""
        switch message {
        case "kvSet":
            let k = args.first as? String ?? ""
            var v = ""
            if args.count > 1 {
                if let str = args[1] as? String { v = str }
                else if let n = args[1] as? NSNumber { v = n.stringValue }
            }
            kv.set(v, forKey: k)
            return
        case "setPinCode":
            var s = (args.first as? String ?? "").filter(\.isNumber)
            if s.count > 8 { s = String(s.prefix(8)) }
            Store.set(s, for: "pinCode")
            return
        case "accept":
            gate.set(true, forKey: "ok")
            return
        case "logout":
            ChangAnAPI.logout()
            return
        case "carMeta":
            await reply(cb) {
                try await ChangAnAPI.refreshCarMeta()
                return self.stateJSON()
            }
        case "status":
            await reply(cb) {
                let d = try await ChangAnAPI.statusRaw()
                return Self.json(self.statusPayload(d))
            }
        case "rawStatus":
            await reply(cb) {
                let d = try await ChangAnAPI.statusRaw()
                return self.prettyRaw(d)
            }
        case "exec":
            await reply(cb) {
                var r = try await ChangAnAPI.exec(carId)
                if r.isEmpty { r = "已下发" }
                return r
            }
        case "sendCode":
            let phone = carId
            await reply(cb) {
                try await ChangAnAPI.sendCode(phone: phone)
                return "ok"
            }
        case "login":
            let phone = carId
            let code = args.count > 1 ? (args[1] as? String ?? "") : ""
            await reply(cb) { try await ChangAnAPI.login(phone: phone, code: code) }
        case "air":
            await reply(cb) {
                let r = try await ChangAnAPI.openExec("openAir")
                self.lastAcLog = "OPEN: " + r
                return r
            }
        case "airOff":
            await reply(cb) {
                let r = try await ChangAnAPI.openExec("closeAir")
                self.lastAcLog = "OPEN: " + r
                return r
            }
        case "location":
            await reply(cb) {
                let d = try await ChangAnAPI.locationRaw()
                return Self.json(d)
            }
        case "actions":
            let page = (args.count > 1 ? args[0] : nil).flatMap { ($0 as? NSNumber)?.intValue } ?? 0
            let size = (args.count > 2 ? args[1] : nil).flatMap { ($0 as? NSNumber)?.intValue } ?? 6
            await reply(cb) {
                let a = try await ChangAnAPI.actionsRaw(page: page, size: size)
                return Self.json(a)
            }
        case "trips":
            let start = carId
            let end = args.count > 1 ? (args[1] as? String ?? start) : start
            await reply(cb) {
                let a = try await ChangAnAPI.tripsRaw(start: start, end: end)
                return Self.json(a)
            }
        case "photos":
            await reply(cb) {
                let raw = try await ChangAnAPI.panoramaRaw()
                return Self.json(self.groupPhotos(raw))
            }
        case "deletePhoto":
            await reply(cb) {
                let id = carId
                try await ChangAnAPI.deletePhoto(id: id)
                return "ok"
            }
        case "capture":
            await reply(cb) {
                let r = try await ChangAnAPI.exec("photograph")
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                let raw = try await ChangAnAPI.panoramaRaw()
                return Self.json(self.groupPhotos(raw)) + "|" + r
            }
        case "updateInfo":
            await reply(cb) {
                let body = await self.fetchVersionJSON()
                return body ?? ""
            }
        case "openUrl":
            if let s = args.first as? String, let u = URL(string: s) {
                await MainActor.run { UIApplication.shared.open(u) }
            }
        case "openMap":
            let lat = (args.first as? NSNumber)?.doubleValue ?? 0
            let lng = (args.count > 1 ? (args[1] as? NSNumber)?.doubleValue : nil) ?? 0
            if let u = URL(string: "https://maps.apple.com/?ll=\(lat),\(lng)&q=我的车") {
                await MainActor.run { UIApplication.shared.open(u) }
            }
        case "openAppSettings":
            if let u = URL(string: UIApplication.openSettingsURLString) {
                await MainActor.run { UIApplication.shared.open(u) }
            }
        case "toast":
            break   // 网页自己有提示条，不再叠一层系统 toast
        case "keepAlive":
            let on = (args.first as? NSNumber)?.boolValue ?? false
            kv.set(on ? "1" : "0", forKey: "icar.keep")
        case "pickBg", "clearBg":
            break   // iOS 自定义背景图待做，先静默忽略，不打断主流程
        case "ntfOpen", "ntfCopyCmd", "ntfClearLog":
            break   // iOS 没有安卓那种通知使用权监听，设置页会显示未开启
        default:
            return
        }
    }

    // MARK: - 回调 JS

    @MainActor
    private func reply(_ id: String, _ work: @escaping () async throws -> String) async {
        do {
            let out = try await work()
            send(id, ok: true, msg: out)
        } catch {
            send(id, ok: false, msg: error.localizedDescription)
        }
    }

    @MainActor
    private func send(_ id: String, ok: Bool, msg: String) {
        guard !id.isEmpty, let wv = webView else { return }
        let js = "window.__cb(\(Self.quote(id)),\(ok ? "true" : "false"),\(Self.quote(msg)))"
        wv.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - 车况组装（逐字段照抄安卓 statusJson）

    private func statusPayload(_ d: [String: Any]) -> [String: Any] {
        var o: [String: Any] = [:]
        let fuelL = num(d, "fuelLeftover")
        let reported = intVal(d, "remainingFuel")
        let tank = Double(kv.string(forKey: "icar.tankL") ?? "") ?? 50
        var fuelLocal = reported
        if fuelL > 0, tank > 0 { fuelLocal = Int((fuelL / tank * 100).rounded()) }
        fuelLocal = max(0, min(100, fuelLocal))
        o["fuelServer"] = max(0, min(100, reported))
        o["fuelLocal"] = fuelLocal
        o["fuelLiter"] = fuelL > 0 ? fuelL : 0
        let useLocal = (kv.string(forKey: "icar.dataSource") ?? "local") != "server"
        o["fuel"] = useLocal ? fuelLocal : max(0, min(100, reported))

        o["range"] = intVal(d, "remainedOilMile")
        o["odo"] = num(d, "totalOdometer")
        o["fuel100"] = num(d, "fuelConsumption100km")
        o["oilTrip"] = num(d, "igniteCumulativeOil")
        o["tripMileage"] = num(d, "igniteCumulativeMileage")
        o["tempIn"] = intVal(d, "vehicleTemperature")
        o["tempOut"] = intVal(d, "environmentalTemp")

        let locked = intVal(d, "driverDoorLock") == 0 && intVal(d, "passengerDoorLock") == 0
            && intVal(d, "leftRearDoorLock") == 0 && intVal(d, "rightRearDoorLock") == 0
        o["locked"] = locked

        if let air = d["air"] as? [String: Any] {
            o["acOn"] = strVal(air, "status") == "1"
            o["acTemp"] = strVal(air, "temperature", "26")
            o["acWind"] = strVal(air, "wind", "0")
        } else {
            o["acOn"] = false
            o["acTemp"] = "26"
            o["acWind"] = "0"
        }

        let tt = strVal(d, "terminalTime")
        o["time"] = tt.count >= 16 ? Self.slice(tt, 11, 16) : "--"
        o["online"] = fresh(tt)

        o["lat"] = num(d, "lat")
        o["lng"] = num(d, "lng")
        o["gps"] = boolVal(d, "validGps") || boolVal(d, "isValidGps")
        o["speed"] = num(d, "vehicleSpeed")

        // 车门/车窗：用官方那组字段，*DoorStatus 解锁后会误报
        o["doorFL"] = intVal(d, "leftFrontDoor")
        o["doorFR"] = intVal(d, "rightFrontDoor")
        o["doorBL"] = intVal(d, "leftRearDoor")
        o["doorBR"] = intVal(d, "rightRearDoor")
        o["winFL"] = intVal(d, "diverWindow")
        o["winFR"] = intVal(d, "passengerWindow")
        o["winBL"] = intVal(d, "leftRearWindow")
        o["winBR"] = intVal(d, "rightRearWindow")
        o["sunroof"] = intVal(d, "sunroof")
        o["trunk"] = intVal(d, "trunk")
        o["hood"] = intVal(d, "hood")
        o["winSlit"] = 0

        o["lowBeam"] = intVal(d, "lowBeam")
        o["highBeam"] = intVal(d, "highBeam")
        o["positionLight"] = intVal(d, "positionLight")
        o["leftTurnSignal"] = intVal(d, "leftTurnSignal")
        o["rightTurnSignal"] = intVal(d, "rightTurnSignal")

        o["voltage"] = num(d, "batteryVoltage")
        o["tireFL"] = num(d, "lfTyrePressure")
        o["tireFR"] = num(d, "rfTyrePressure")
        o["tireRL"] = num(d, "lrTyrePressure")
        o["tireRR"] = num(d, "rrTyrePressure")
        o["waterTemp"] = num(d, "engineWaterTemp")
        o["engineStatus"] = intVal(d, "engineStatus")
        var rpm = num(d, "engineSpeed")
        if rpm >= 60000 { rpm = 0 }   // 65535 = 无数据
        o["engineSpeed"] = rpm
        return o
    }

    /// 扩展行（详情面板里挖到的小字），页面需要哪个键就给哪个
    private func prettyRaw(_ d: [String: Any]) -> String {
        var lines: [String] = []
        for k in d.keys.sorted() {
            if d[k] is [String: Any] { continue }   // 嵌套的先不铺开
            let v = d[k] ?? NSNull()
            lines.append("\(k) = \(v)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 全景照片分组（照抄安卓 groupPhotos）

    private func groupPhotos(_ raw: [[String: Any]]) -> [[String: Any]] {
        var order: [String] = []
        var groups: [String: [[String: Any]]] = [:]
        var times: [String: String] = [:]
        for p in raw {
            let tid = (p["task_id"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (p["id"] as? String ?? "")
            if groups[tid] == nil { groups[tid] = []; order.append(tid) }
            let name = p["name"] as? String ?? ""
            let parts = name.components(separatedBy: "_")
            let dir = parts.count > 3 ? parts[3] : "?"
            var it: [String: Any] = [:]
            it["dir"] = dir
            it["name"] = name
            it["id"] = p["id"] as? String ?? ""
            it["taskId"] = tid
            it["thumb"] = p["thumbnail"] as? String ?? ""
            it["url"] = p["url"] as? String ?? ""
            groups[tid]?.append(it)
            if times[tid] == nil {
                times[tid] = (p["time"] as? String ?? "").replacingOccurrences(of: ".0", with: "")
            }
        }
        var out: [[String: Any]] = []
        for tid in order {
            let items = groups[tid] ?? []
            var sorted: [[String: Any]] = []
            for d in ["F", "D", "R", "P"] {
                sorted += items.filter { ($0["dir"] as? String) == d }
            }
            sorted += items.filter { ($0["dir"] as? String) == "?" }
            out.append(["time": times[tid] ?? "", "items": sorted])
        }
        return out
    }

    // MARK: - 小工具

    private func fetchVersionJSON() async -> String? {
        let urls = ["https://gitee.com/mu12138s/icar-update/raw/master/version.json"]
        for u in urls {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url, timeoutInterval: 4)
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            guard let (data, resp) = try? await URLSession.shared.data(for: req),
                  (resp as? HTTPURLResponse)?.statusCode == 200,
                  let s = String(data: data, encoding: .utf8) else { continue }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.hasPrefix("{") { return t }
        }
        return nil
    }

    private func num(_ d: [String: Any], _ k: String) -> Double {
        guard let v = d[k] else { return 0 }
        if v is NSNull { return 0 }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String {
            return Double(s.trimmingCharacters(in: .whitespaces)) ?? 0
        }
        return 0
    }

    private func intVal(_ d: [String: Any], _ k: String) -> Int { Int(num(d, k)) }

    private func boolVal(_ d: [String: Any], _ k: String) -> Bool {
        if let b = d[k] as? Bool { return b }
        if let n = d[k] as? NSNumber { return n.boolValue }
        if let s = d[k] as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    private func strVal(_ d: [String: Any], _ k: String, _ def: String = "") -> String {
        if let s = d[k] as? String { return s }
        if let n = d[k] as? NSNumber { return n.stringValue }
        return def
    }

    private func fresh(_ terminalTime: String) -> Bool {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        guard let t = f.date(from: terminalTime) else { return false }
        return Date().timeIntervalSince(t) < 3 * 60
    }

    private static func slice(_ s: String, _ a: Int, _ b: Int) -> String {
        let chars = Array(s)
        guard chars.count >= b else { return s }
        return String(chars[a..<b])
    }

    static func json(_ obj: Any) -> String {
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }

    /// 把字符串变成 JS 字符串字面量（带引号转义）
    static func quote(_ s: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[\"\"]".utf8)
        var str = String(data: data, encoding: .utf8) ?? "[\"\"]"
        if str.hasPrefix("[") { str.removeFirst() }
        if str.hasSuffix("]") { str.removeLast() }
        return str
    }
}

// MARK: - WebKit 回调

extension NativeBridge: WKScriptMessageHandler, WKUIDelegate {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "icar",
              let body = message.body as? [String: Any],
              let m = body["m"] as? String else { return }
        let args = body["a"] as? [Any] ?? []
        Task { @MainActor in
            await self.handle(message: m, args: args)
        }
    }

    /// 同步桥：window.Native 里的同步方法都走 prompt("icar:{…}")
    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard prompt.hasPrefix("icar:"),
              let data = String(prompt.dropFirst(5)).data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let m = obj["m"] as? String else {
            completionHandler(nil)
            return
        }
        let args = obj["a"] as? [Any] ?? []
        completionHandler(syncValue(method: m, args: args))
    }
}
