import Foundation
import PhotosUI
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

    /// 正在等选图结果的 JS 回调 id
    private var bgCbId = ""

    override init() {
        super.init()
        // 切后台前把防抖里的偏好全部落盘，别丢
        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil, queue: .main) { [weak self] _ in
                self?.flushKV()
            }
    }

    private let kvSuite = "icar_web"
    private let gateSuite = "gate"
    private var kv: UserDefaults { UserDefaults(suiteName: kvSuite) ?? .standard }

    /// 偏好写盘防抖：拖滑块时 JS 每帧都在 kvSet，攒 250ms 再一次性落盘
    private var kvPending: [String: String] = [:]
    private var kvFlushWork: DispatchWorkItem?

    private func kvSet(_ key: String, _ value: String) {
        kvPending[key] = value
        kvFlushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flushKV() }
        kvFlushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func kvValue(_ key: String) -> String {
        if let v = kvPending[key] { return v }
        return kv.string(forKey: key) ?? ""
    }

    func flushKV() {
        guard !kvPending.isEmpty else { return }
        let snap = kvPending
        kvPending.removeAll()
        let d = kv
        snap.forEach { d.set($0.value, forKey: $0.key) }
    }
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
            return kvValue(k)
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
        // iOS 有自己那份 version.json（icar-ios 仓库 update/version.json），code 就是 iOS build
        o["versionCode"] = Int(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0") ?? 0
        return Self.json(o)
    }

    // MARK: - 异步分发

    @MainActor
    func handle(message: String, args: [Any]) async {
        let cb = args.last as? String ?? ""
        let carId = args.first as? String ?? ""
        let argDesc = args.map { "\($0)" }.joined(separator: ",")
        DebugLog.shared.add("JS·\(message) [\(argDesc.prefix(60))]")

        // 网页资源被改过（换包/改指令）：界面照常，但控车类指令一律失败
        if Hardening.assetsTampered, ["exec", "air", "airOff", "capture"].contains(message) {
            send(cb, ok: false, msg: "执行失败，请稍后重试")
            return
        }
        switch message {
        case "kvSet":
            let k = args.first as? String ?? ""
            var v = ""
            if args.count > 1 {
                if let str = args[1] as? String { v = str }
                else if let n = args[1] as? NSNumber { v = n.stringValue }
            }
            kvSet(k, v)
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
                // 拍照不跟着指令轮询走：下发完就先去拉列表（车端上传要几秒），
                // 列表空就再等一轮，避免 iOS 上一直卡在「拍摄中…」二十秒。
                var msg = "已下发"
                do {
                    let tid = try await ChangAnAPI.dispatch("photograph")
                    msg = tid.isEmpty ? "已下发" : "已下发，等车端上传"
                } catch {
                    msg = "指令返回：" + error.localizedDescription
                }
                var raw: [[String: Any]] = []
                var listErr = ""
                for i in 0..<4 {
                    try? await Task.sleep(nanoseconds: UInt64(i == 0 ? 4 : 3) * 1_000_000_000)
                    do {
                        raw = try await ChangAnAPI.panoramaRaw()
                        if !raw.isEmpty { break }
                    } catch {
                        listErr = error.localizedDescription
                    }
                }
                let tail = (raw.isEmpty && !listErr.isEmpty) ? "；照片列表：\(listErr)" : ""
                return Self.json(self.groupPhotos(raw)) + "|" + msg + tail
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
            await MainActor.run { self.presentMapOptions(lat: lat, lng: lng) }
        case "openAppSettings":
            if let u = URL(string: UIApplication.openSettingsURLString) {
                await MainActor.run { UIApplication.shared.open(u) }
            }
        case "toast":
            break   // 网页自己有提示条，不再叠一层系统 toast
        case "keepAlive":
            let on = (args.first as? NSNumber)?.boolValue ?? false
            kvSet("icar.keep", on ? "1" : "0")
        case "pickBg":
            await MainActor.run { self.presentBgPicker(cb: cb) }
        case "clearBg":
            Self.deleteBackground()
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
        let tank = Double(kvValue("icar.tankL")) ?? 50
        var fuelLocal = reported
        if fuelL > 0, tank > 0 { fuelLocal = Int((fuelL / tank * 100).rounded()) }
        fuelLocal = max(0, min(100, fuelLocal))
        o["fuelServer"] = max(0, min(100, reported))
        o["fuelLocal"] = fuelLocal
        o["fuelLiter"] = fuelL > 0 ? fuelL : 0
        let useLocal = (kvValue("icar.dataSource").isEmpty ? "local" : kvValue("icar.dataSource")) != "server"
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
        // iOS 专用：仓库里的 update/version.json（跟安卓的 icar-update 互不影响）
        // 带时间戳参数绕开 CDN 缓存，推送后打开就能看到最新的公告/更新
        let stamp = Int(Date().timeIntervalSince1970)
        let urls = [
            "https://raw.githubusercontent.com/mu12138/icar-ios/main/update/version.json?t=\(stamp)",
            "https://cdn.jsdelivr.net/gh/mu12138/icar-ios@main/update/version.json?t=\(stamp)",
        ]
        for u in urls {
            guard let url = URL(string: u) else { continue }
            var req = URLRequest(url: url,
                                 cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                                 timeoutInterval: 4)
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


// MARK: - 自定义背景图

extension NativeBridge {
    static func bgFileURL() -> URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("bg.jpg")
    }

    static func deleteBackground() {
        try? FileManager.default.removeItem(at: bgFileURL())
    }

    /// 长边压到 1600 再存 jpg，页面通过 /__bg.jpg 读
    static func saveBackground(_ image: UIImage) -> Bool {
        let maxSide: CGFloat = 1600
        let w = max(1, image.size.width), h = max(1, image.size.height)
        let scale = min(1, maxSide / max(w, h))
        let size = CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try data.write(to: bgFileURL(), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    @MainActor
    func presentBgPicker(cb: String) {
        guard let vc = Self.topViewController() else {
            send(cb, ok: false, msg: "界面还没准备好")
            return
        }
        var cfg = PHPickerConfiguration(photoLibrary: .shared())
        cfg.filter = .images
        cfg.selectionLimit = 1
        let picker = PHPickerViewController(configuration: cfg)
        picker.delegate = self
        bgCbId = cb
        vc.present(picker, animated: true)
    }

    static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
        var vc = window?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc
    }
}

extension NativeBridge: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let cb = bgCbId
        bgCbId = ""
        guard let item = results.first else {
            Task { @MainActor in self.send(cb, ok: false, msg: "已取消") }
            return
        }
        let provider = item.itemProvider
        guard provider.canLoadObject(ofClass: UIImage.self) else {
            Task { @MainActor in self.send(cb, ok: false, msg: "这张图读不了") }
            return
        }
        provider.loadObject(ofClass: UIImage.self) { obj, error in
            let ok: Bool
            let msg: String
            if let img = obj as? UIImage {
                ok = NativeBridge.saveBackground(img)
                msg = ok ? "ok" : "保存失败"
            } else {
                ok = false
                msg = error?.localizedDescription ?? "读取失败"
            }
            Task { @MainActor in self.send(cb, ok: ok, msg: msg) }
        }
    }
}

// MARK: - 导航：第三方地图

extension NativeBridge {
    /// 点「车辆位置」时：装了高德/百度就给选择，苹果地图被卸载了也不会点不动。
    /// 坐标按 GCJ-02 传（高德 dev=0、百度 coord_type=gcj02）；如果实际有偏移，
    /// 把高德改成 dev=1、百度改成 coord_type=wgs84 即可。
    @MainActor
    func presentMapOptions(lat: Double, lng: Double) {
        guard !(lat == 0 && lng == 0) else {
            DebugLog.shared.add("openMap 坐标为空，忽略")
            return
        }
        let coords = "\(lat),\(lng)"
        // 中文要转义，否则 URL(string:) 会直接返回 nil（点了没反应就是这个原因）
        let name = "我的车".addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "car"
        var items: [(String, URL)] = []

        if let u = URL(string: "iosamap://viewMap?sourceApplication=icar&poiname=\(name)&lat=\(lat)&lon=\(lng)&dev=0"),
           UIApplication.shared.canOpenURL(u) {
            items.append(("高德地图", u))
        }
        if let u = URL(string: "baidumap://map/marker?location=\(coords)&title=\(name)&content=\(name)&coord_type=gcj02&src=cn.icar.native"),
           UIApplication.shared.canOpenURL(u) {
            items.append(("百度地图", u))
        }
        if let u = URL(string: "maps://?ll=\(coords)&q=\(name)"),
           UIApplication.shared.canOpenURL(u) {
            items.append(("苹果地图", u))
        }

        // 一个装了就直接开，多个让用户选；全都没有就落到高德网页版
        if items.count == 1 {
            UIApplication.shared.open(items[0].1)
            return
        }
        if items.isEmpty {
            if let web = URL(string: "https://uri.amap.com/marker?position=\(lng),\(lat)&name=\(name)&coordinate=gaode&callnative=1") {
                UIApplication.shared.open(web)
            }
            return
        }
        guard let vc = Self.topViewController() else {
            UIApplication.shared.open(items[0].1)
            return
        }
        let sheet = UIAlertController(title: "用哪个地图导航", message: nil, preferredStyle: .actionSheet)
        for (name, url) in items {
            sheet.addAction(UIAlertAction(title: name, style: .default) { _ in
                UIApplication.shared.open(url)
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = vc.view
            pop.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.maxY - 40, width: 1, height: 1)
        }
        vc.present(sheet, animated: true)
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
