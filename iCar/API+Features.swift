import Foundation

// MARK: - 轨迹 / 记录 / 定位 / 全景 / 空调（开放平台）

extension ChangAnAPI {

    private static func carId() throws -> String {
        let id = Store.get("carId") ?? ""
        guard !id.isEmpty else { throw APIError.bad("未绑定车辆") }
        return id
    }

    private static func token() -> String { Store.get("token") ?? "" }

    /// 带 token 的通用取 JSON
    private static func authed(_ path: String, method: String = "GET",
                               form: [String: String]? = nil) async throws -> [String: Any] {
        try await ensureToken()
        let body = form
        let p = path.replacingOccurrences(of: "TOKEN", with: token())
        var d = try await send(base + p, method: method, form: body)
        var j = try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
        if ChangAnAPI.codeInt(j) == 2 {
            try await ensureToken(force: true)
            let p2 = path.replacingOccurrences(of: "TOKEN", with: token())
            d = try await send(base + p2, method: method, form: body)
            j = try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:]
        }
        return j
    }

    // MARK: 轨迹

    struct Trip: Identifiable {
        let id = UUID()
        var start: String
        var end: String
        var mileage: Double
        var oil: Double
        var speed: Double
        var from: String
        var to: String

        init(_ d: [String: Any]) {
            func s(_ k: String) -> String { d[k] as? String ?? "" }
            func n(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }
            start = s("startTime"); end = s("endTime")
            mileage = n("mileage"); oil = n("oil"); speed = n("avrgSpeed")
            from = s("startAddressName"); to = s("endAddressName")
        }
    }

    static func trips(days: Int = 1) async throws -> [Trip] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let end = f.string(from: Date())
        let start = f.string(from: Calendar.current.date(byAdding: .day, value: -(max(1, days) - 1), to: Date()) ?? Date())
        let id = try carId()
        let j = try await authed("/app2/api/driving?carId=\(id)&startDate=\(start)&endDate=\(end)&loading=false&toast=false&token=TOKEN")
        let arr = j["data"] as? [[String: Any]] ?? []
        return arr.map(Trip.init)
    }

    // MARK: 操作记录

    struct ActionRecord: Identifiable {
        let id = UUID()
        var time: String
        var name: String
        var status: String

        init(_ d: [String: Any]) {
            func s(_ k: String) -> String { d[k] as? String ?? "" }
            time = s("createTime").isEmpty ? s("time") : s("createTime")
            name = s("actionName").isEmpty ? s("cmd") : s("actionName")
            status = s("handleStatusDesc").isEmpty ? s("handleStatus") : s("handleStatusDesc")
        }
    }

    static func actions() async throws -> [ActionRecord] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd+HH:mm:ss"
        let end = f.string(from: Date()).replacingOccurrences(of: ":", with: "%3A")
        let start = f.string(from: Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date())
            .replacingOccurrences(of: ":", with: "%3A")
        let id = try carId()
        let j = try await authed("/appserver/api/car/getControlActionHistory?carId=\(id)&pageSize=30&page=1&startTime=\(start)&endTime=\(end)&toast=false&token=TOKEN&isNev=0", method: "POST")
        let d = j["data"] as? [String: Any]
        let arr = d?["data"] as? [[String: Any]] ?? []
        return arr.map(ActionRecord.init)
    }

    // MARK: 定位

    struct CarLocation {
        var lat: Double = 0
        var lng: Double = 0
        var address: String = ""
        var time: String = ""
    }

    static func location() async throws -> CarLocation {
        let id = try carId()
        let j = try await authed("/appserver/api/cardata/getCarLocation?carId=\(id)&mapType=AMap&loading=false&token=TOKEN", method: "POST")
        guard let d = j["data"] as? [String: Any] else { throw APIError.bad(j["msg"] as? String ?? "定位失败") }
        var loc = CarLocation()
        loc.lat = (d["lat"] as? NSNumber)?.doubleValue ?? 0
        loc.lng = (d["lng"] as? NSNumber)?.doubleValue ?? 0
        loc.address = d["address"] as? String ?? d["poiName"] as? String ?? ""
        loc.time = d["terminalTime"] as? String ?? ""
        return loc
    }

    // MARK: 360 全景

    struct PanoPhoto: Identifiable {
        let id: String
        var name: String
        var thumb: String
        var url: String
        var dir: String
        var time: String

        var dirName: String {
            switch dir {
            case "F": return "车头"
            case "D": return "左侧"
            case "R": return "右侧"
            case "P": return "车尾"
            default: return ""
            }
        }
    }

    static func panorama() async throws -> [PanoPhoto] {
        let id = try carId()
        let j = try await authed("/appserver/api/file/getMediaFilesByUserIdAndCarId?pageIndex=0&pageSize=40&carId=\(id)&fileType=1&token=TOKEN&isNev=0")
        let arr = j["data"] as? [[String: Any]] ?? []
        var out: [PanoPhoto] = []
        for p in arr {
            let name = p["name"] as? String ?? ""
            let parts = name.split(separator: "_")
            let dir = parts.count > 3 ? String(parts[3]) : ""
            let pid = p["id"] as? String ?? p["task_id"] as? String ?? UUID().uuidString
            out.append(PanoPhoto(id: pid, name: name,
                                 thumb: p["thumbnail"] as? String ?? "",
                                 url: p["url"] as? String ?? "",
                                 dir: dir,
                                 time: (p["time"] as? String ?? "").replacingOccurrences(of: ".0", with: "")))
        }
        return out
    }

    /// 车外拍照：下发 photograph，等车端上传后回传最新列表
    static func capture() async throws -> [PanoPhoto] {
        _ = try await exec("photograph")
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        return try await panorama()
    }

    static func deletePhoto(id: String) async throws {
        guard !id.isEmpty else { throw APIError.bad("照片 id 为空") }
        let carId = try carId()
        let qs = "recordIds=\(esc(id))&carId=\(carId)&isNev=0&token=\(token())"
        let ep = base + "/appserver/api/file/removeFileByRecordIds"
        var ok = false
        if let d = try? await send(ep + "?" + qs, method: "POST", form: nil) {
            ok = isOK(d)
        }
        if !ok, let d = try? await send(ep, method: "POST", form: ["recordIds": id, "carId": carId, "isNev": "0", "token": token()]) {
            ok = isOK(d)
        }
        if !ok { throw APIError.bad("删除失败") }
    }

    private static func isOK(_ d: Data) -> Bool {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return false }
        if (j["success"] as? Bool) == true { return true }
        let c = (j["code"] as? NSNumber)?.intValue ?? -1
        return c == 0 || c == 200
    }

    // MARK: 空调（走开放平台）

    private static let openBase = "https://open.iov.changan.com.cn"
    private static let openCID = "b235afd313004785bfde580c188c47bb"
    private static let openSEC = "YjIzNWFmZDMxMzAwNDc4NQ=="
    private static let openGEN = "client_id=\(openCID)&device_id=fqvXergO18PeSQ58&nonce=WYYL&size=L&state=OPPOWATCH&timestamp=1794441399&appCode=usercenter&sign=94856A74F928873E702BB125E10B799DD0C5705AE74A45928340538C853E301A"

    private struct OpenResp {
        var code: Int = 0
        var body = Data()
        var qrcodeId = ""
    }

    private static func openPost(_ url: String, ctype: String, body: String, ua: String,
                                 headers: [String: String]? = nil) async throws -> OpenResp {
        guard let u = URL(string: url) else { throw APIError.bad("地址错误") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 25
        req.setValue(ua, forHTTPHeaderField: "User-Agent")
        req.setValue(ctype, forHTTPHeaderField: "Content-Type")
        headers?.forEach { req.setValue($0.value, forHTTPHeaderField: $0.key) }
        req.httpBody = body.data(using: .utf8)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let http = resp as? HTTPURLResponse
        var r = OpenResp()
        r.code = http?.statusCode ?? 0
        r.body = data
        r.qrcodeId = http?.value(forHTTPHeaderField: "qrcode_id") ?? ""
        return r
    }

    private static func saveOpen(_ d: Data) -> String? {
        guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let at = j["access_token"] as? String, !at.isEmpty else { return nil }
        Store.set(at, for: "openToken")
        if let rt = j["refresh_token"] as? String { Store.set(rt, for: "openRefresh") }
        let exp = (j["expires_in"] as? NSNumber)?.doubleValue ?? 86400
        Store.set(String(Date().timeIntervalSince1970 + exp), for: "openExp")
        return at
    }

    static func openToken(force: Bool = false) async throws -> String {
        let exp = Double(Store.get("openExp") ?? "0") ?? 0
        if !force, let at = Store.get("openToken"), !at.isEmpty,
           Date().timeIntervalSince1970 < exp - 120 { return at }

        if let rt = Store.get("openRefresh"), !rt.isEmpty {
            let body = "grant_type=refresh_token&refresh_token=\(esc(rt))&client_id=\(openCID)&client_secret=\(esc(openSEC))"
            if let r = try? await openPost(openBase + "/oauth/token",
                                           ctype: "application/x-www-form-urlencoded",
                                           body: body, ua: "Dart/3.6 (dart:io)"),
               let t = saveOpen(r.body) {
                return t
            }
        }
        return try await openAuth()
    }

    /// 生成二维码 → 用官方登录态自授权 → 换 token
    static func openAuth() async throws -> String {
        try await ensureToken()
        let official = token()
        let g = try await openPost(openBase + "/oauth/api/qrcode/generate",
                                   ctype: "application/x-www-form-urlencoded",
                                   body: openGEN, ua: "Dart/3.6 (dart:io)")
        guard !g.qrcodeId.isEmpty else { throw APIError.bad("二维码生成失败") }

        let a = try await openPost(base + "/oauth/api/qrcode/authorize",
                                   ctype: "application/x-www-form-urlencoded",
                                   body: "token=\(esc(official))&qrcodeId=\(g.qrcodeId)",
                                   ua: "Dart/3.6 (dart:io)")
        guard let aj = try? JSONSerialization.jsonObject(with: a.body) as? [String: Any],
              (aj["code"] as? NSNumber)?.intValue == 0,
              let code = aj["data"] as? String, !code.isEmpty else {
            throw APIError.bad("授权失败")
        }

        let t = try await openPost(openBase + "/oauth/token",
                                   ctype: "application/x-www-form-urlencoded",
                                   body: "redict_uri=&code=\(esc(code))&grant_type=authorization_code&client_secret=\(esc(openSEC))&client_id=\(openCID)",
                                   ua: "Dart/3.6 (dart:io)")
        guard let at = saveOpen(t.body) else { throw APIError.bad("换取 token 失败") }
        return at
    }

    /// 走开放平台下发（空调专用）
    @discardableResult
    static func openExec(_ cmd: String) async throws -> String {
        let at = try await openToken()
        let id = try carId()
        let payload: [String: Any] = ["mapArgsJson": "{}", "senderType": "APP", "cmd": cmd, "carId": id]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let r = try await openPost(openBase + "/openc-apigw/vrtm-agent/api/v2/open/car-control/" + cmd,
                                   ctype: "application/json; charset=utf-8",
                                   body: String(data: data, encoding: .utf8) ?? "{}",
                                   ua: "okhttp/3.10.0",
                                   headers: [
                                       "x-vcs-nonce": "WYYL",
                                       "x-vcs-timestamp": String(Int(Date().timeIntervalSince1970 * 1000)),
                                       "x-vcs-user-access-token": at,
                                   ])
        guard let j = try? JSONSerialization.jsonObject(with: r.body) as? [String: Any] else {
            throw APIError.bad("空调指令失败")
        }
        guard (j["code"] as? NSNumber)?.intValue == 0 else {
            throw APIError.bad(j["msg"] as? String ?? "空调指令失败")
        }
        return j["msg"] as? String ?? "已下发"
    }

    // MARK: - 网页版桥用的原始数据（与安卓 Api.java 一一对应）

    static func tripsRaw(start: String, end: String) async throws -> [[String: Any]] {
        let id = try carId()
        let j = try await authed("/app2/api/driving?carId=\(id)&startDate=\(start)&endDate=\(end)&loading=false&toast=false&ErrorAutoProjectile=false&token=TOKEN")
        if let a = j["data"] as? [[String: Any]] { return a }
        if let d = j["data"] as? [String: Any], let a = d["data"] as? [[String: Any]] { return a }
        return []
    }

    static func actionsRaw(page: Int, size: Int) async throws -> [[String: Any]] {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd+HH:mm:ss"
        let end = f.string(from: Date()).replacingOccurrences(of: ":", with: "%3A")
        let start = f.string(from: Calendar.current.date(byAdding: .month, value: -6, to: Date()) ?? Date())
            .replacingOccurrences(of: ":", with: "%3A")
        let id = try carId()
        let j = try await authed("/appserver/api/car/getControlActionHistory?carId=\(id)&pageSize=\(size)&page=\(page)&startTime=\(start)&endTime=\(end)&toast=false&ErrorAutoProjectile=false&token=TOKEN&isNev=0", method: "POST")
        if let d = j["data"] as? [String: Any], let a = d["data"] as? [[String: Any]] { return a }
        if let a = j["data"] as? [[String: Any]] { return a }
        return []
    }

    static func locationRaw() async throws -> [String: Any] {
        let id = try carId()
        let j = try await authed("/appserver/api/cardata/getCarLocation?carId=\(id)&mapType=AMap&loading=false&ErrorAutoProjectile=false&token=TOKEN", method: "POST")
        guard let d = j["data"] as? [String: Any] else { throw APIError.bad(j["msg"] as? String ?? "定位失败") }
        return d
    }

    static func panoramaRaw() async throws -> [[String: Any]] {
        let id = try carId()
        let j = try await authed("/appserver/api/file/getMediaFilesByUserIdAndCarId?pageIndex=0&pageSize=40&carId=\(id)&fileType=1&ErrorAutoProjectile=false&token=TOKEN&isNev=0&deviceId=00000000-4627-0c29-ffff-ffffef05ac4a", method: "POST")
        return j["data"] as? [[String: Any]] ?? []
    }
}
