import Foundation

/// 长安车控接口（与 Android 版同一套）
enum ChangAnAPI {
    static let base = "https://incallapi.changan.com.cn"
    static let cac = "https://m.iov.changan.com.cn"
    static let clientId = "2c918082632162010163388048d60158"
    static let tankL: Double = 50   // 油箱容量（升），换车要改

    // MARK: - 底层请求

    /// 长安接口的 code 有时是数字、有时是字符串（如 media 接口回 "2"），
    /// 按安卓 optInt 的习惯统一取整，避免该刷 token 时没刷
    static func codeInt(_ j: [String: Any]) -> Int {
        if let i = j["code"] as? Int { return i }
        if let n = j["code"] as? NSNumber { return n.intValue }
        if let s = j["code"] as? String, let i = Int(s) { return i }
        return -1
    }

    static func send(_ urlString: String,
                             method: String = "GET",
                             form: [String: String]? = nil) async throws -> Data {
        guard let url = URL(string: urlString) else { throw APIError.bad("地址错误") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = 15
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("inCall", forHTTPHeaderField: "vcs-app-id")
        req.setValue("cn.com.changan.cvim", forHTTPHeaderField: "X-Requested-With")
        req.setValue("okhttp/4.12.0", forHTTPHeaderField: "User-Agent")
        if let form = form {
            req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            req.httpBody = form
                .map { "\(esc($0.key))=\(esc($0.value))" }
                .joined(separator: "&")
                .data(using: .utf8)
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        let body = String(data: data, encoding: .utf8) ?? ""
        let short = urlString.replacingOccurrences(of: base, with: "")
        DebugLog.shared.add("\(method) \(short.prefix(90)) → \(code) \(body.prefix(120))")
        guard (200..<300).contains(code) else {
            throw APIError.bad("服务端返回 \(code)")
        }
        return data
    }

    static func esc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    private static func json(_ d: Data) throws -> [String: Any] {
        guard let o = try JSONSerialization.jsonObject(with: d) as? [String: Any] else {
            throw APIError.bad("返回格式不对")
        }
        return o
    }

    // MARK: - 登录

    static func sendCode(phone: String) async throws {
        _ = try await send("\(base)/api/sms/sendAuthcode", method: "POST", form: ["phone": phone])
    }

    /// 返回车辆名；token / carId 写进 Keychain
    @discardableResult
    static func login(phone: String, code: String) async throws -> String {
        let d = try await send("\(base)/app2/api/oauth2login/token/stageOne",
                               method: "POST",
                               form: ["mobile": phone, "vercode": code])
        let j = try json(d)
        guard codeInt(j) == 0 else {
            throw APIError.bad(j["msg"] as? String ?? "登录失败")
        }
        guard let data = j["data"] as? [String: Any],
              let token = data["access_token"] as? String else {
            throw APIError.bad("登录返回缺 token")
        }
        Store.set(token, for: "token")
        Store.set(data["refresh_token"] as? String ?? "", for: "refresh")
        let exp = (data["expires_in"] as? Double) ?? 7200
        Store.set(String(Date().timeIntervalSince1970 + exp), for: "expiresAt")
        Store.set(phone, for: "phone")

        try await refreshCarMeta()
        return Store.get("carName") ?? "我的车"
    }

    static func refreshCarMeta() async throws {
        let j = try await getJSON("/app2/api/user/cars?type=0&token=TOKEN")
        let arr = (j["data"] as? [[String: Any]]) ?? []
        DebugLog.shared.add("车辆列表 code=\(j["code"] ?? "-") 数量=\(arr.count)")
        guard let car = arr.first else {
            DebugLog.shared.add("⚠️ 车辆列表为空，carId 没拿到")
            return
        }
        Store.set(car["carId"] as? String ?? "", for: "carId")
        Store.set(car["carName"] as? String ?? car["seriesName"] as? String ?? "我的车", for: "carName")
        Store.set(car["seriesName"] as? String ?? "", for: "seriesName")
        Store.set(car["seriesCode"] as? String ?? "", for: "seriesCode")
    }

    // MARK: - token 维护

    static var loggedIn: Bool { Store.get("token") != nil }

    static func logout() {
        ["token", "refresh", "expiresAt", "carId", "carName", "seriesName", "phone"].forEach(Store.del)
    }

    static func ensureToken(force: Bool = false) async throws {
        guard let token = Store.get("token"), !token.isEmpty else {
            throw APIError.bad("未登录")
        }
        let exp = Double(Store.get("expiresAt") ?? "0") ?? 0
        let now = Date().timeIntervalSince1970
        if !force && now < exp - 60 { return }

        guard let rt = Store.get("refresh"), !rt.isEmpty else { return }
        let url = "\(cac)/cac/api/v1/oauth2/refresh_token?client_id=\(clientId)&refresh_token=\(esc(rt))"
        guard let d = try? await send(url) else { return }
        guard let j = try? json(d) else { return }
        if (j["status_code"] as? String) == "0", let t = j["access_token"] as? String, !t.isEmpty {
            Store.set(t, for: "token")
            if let r = j["refresh_token"] as? String { Store.set(r, for: "refresh") }
            let e = (j["expires_in"] as? Double) ?? 7200
            Store.set(String(now + e), for: "expiresAt")
        }
    }

    private static func getJSON(_ path: String, method: String = "GET",
                                form: [String: String]? = nil) async throws -> [String: Any] {
        try await ensureToken()
        let token = Store.get("token") ?? ""
        var body = form
        var p = path.replacingOccurrences(of: "TOKEN", with: token)
        if method == "POST", body == nil { body = ["token": token] }
        var d = try await send(base + p, method: method, form: body)
        var j = try json(d)
        if codeInt(j) == 2 {          // token 过期，刷新后重试一次
            try await ensureToken(force: true)
            let t2 = Store.get("token") ?? ""
            p = path.replacingOccurrences(of: "TOKEN", with: t2)
            d = try await send(base + p, method: method, form: body)
            j = try json(d)
        }
        return j
    }

    // MARK: - 车况

    static func status() async throws -> CarStatus {
        let d = try await statusRaw()
        DebugLog.shared.add("车况字段数 \(d.count)")
        return CarStatus(raw: d)
    }

    /// 车况原始 data（网页版桥用，按安卓 statusJson 的口径自己组装）
    static func statusRaw() async throws -> [String: Any] {
        let carId = Store.get("carId") ?? ""
        guard !carId.isEmpty else { throw APIError.bad("未绑定车辆") }
        // 车况接口只认 POST：GET 会回 40005「请求方法不支持：GET」，
        // 以前能用是服务端放宽过，现在收紧了，参数照安卓版带全
        let path = "/app2/api/car/data?carId=\(carId)&ErrorAutoProjectile=false&toast=false&keys=*&isNev=0&token=TOKEN"
        var j = try await getJSON(path, method: "POST")
        if codeInt(j) == 40005 {
            // 万一服务端以后又放回 GET，兜一次，不至于又全空
            j = try await getJSON(path, method: "GET")
        }
        guard let d = carData(j) else {
            let code = j["code"].map { "\($0)" } ?? "-"
            let msg = (j["msg"] as? String) ?? "-"
            DebugLog.shared.add("⚠️ 车况为空 code=\(code) msg=\(msg)")
            throw APIError.bad("车况为空（\(code) \(msg)）")
        }
        return d
    }

    /// 车况 data 可能是对象，也可能被包成 JSON 字符串，两种都认
    private static func carData(_ j: [String: Any]) -> [String: Any]? {
        if let d = j["data"] as? [String: Any] { return d }
        if let s = j["data"] as? String,
           let obj = try? JSONSerialization.jsonObject(with: Data(s.utf8)),
           let d = obj as? [String: Any] { return d }
        return nil
    }

    // MARK: - 下发指令

    /// 下发 + 轮询一步到位（旧调用方式，车外拍照等还在用）
    @discardableResult
    static func exec(_ cmd: String, extra: [String: String] = [:]) async throws -> String {
        let taskId = try await dispatch(cmd, extra: extra)
        guard !taskId.isEmpty else { return "已下发" }
        return try await pollResult(taskId)
    }

    /// 只负责把指令发出去，返回 taskId（可能为空）。
    /// 拆出来是为了界面能在下发成功那一刻就亮「已下发」，不再干等轮询。
    static func dispatch(_ cmd: String, extra: [String: String] = [:]) async throws -> String {
        try await ensureToken()
        let token = Store.get("token") ?? ""
        let carId = Store.get("carId") ?? ""
        guard !carId.isEmpty else { throw APIError.bad("未绑定车辆") }

        // 1. 一次性校验码
        let pinData = try await send("\(base)/app2/api/control/createPinVerifyCode",
                                     method: "POST", form: ["token": token])
        let pinJ = try json(pinData)
        guard codeInt(pinJ) == 0, let pinCode = pinJ["data"] as? String else {
            throw APIError.bad("PIN 获取失败")
        }

        // 2. 公钥
        let keyData = try await send("\(base)/app2/api/v2/security/key?carId=\(carId)&moblie=&token=\(esc(token))")
        let keyJ = try json(keyData)
        guard codeInt(keyJ) == 0, let keyB64 = keyJ["data"] as? String,
              let der = Data(base64Encoded: keyB64) else {
            throw APIError.bad("公钥获取失败")
        }
        guard let pub = RSACrypto.publicKey(fromSPKI: der) else {
            throw APIError.bad("公钥解析失败")
        }

        // 3. 组明文并加密
        let plain: [String: Any] = [
            "pinVerifyCode": pinCode,
            "cmd": cmd,
            "type": cmd,
            "pin": Store.get("pinCode") ?? "",
            "wifiPassword": "",
        ]
        let plainData = try JSONSerialization.data(withJSONObject: plain, options: [.sortedKeys])
        guard let enc = RSACrypto.encryptOAEP(plainData, key: pub) else {
            throw APIError.bad("加密失败")
        }
        let s = enc.base64EncodedString()

        // 4. 下发
        var body: [String: String] = [
            "carId": carId, "token": token, "isNev": "0", "s": s,
        ]
        for (k, v) in extra { body[k] = v }
        let execData = try await send("\(base)/app2/api/v3/control/execute", method: "POST", form: body)
        let execJ = try json(execData)
        guard codeInt(execJ) == 0 else {
            throw APIError.bad(execJ["msg"] as? String ?? "指令发送失败")
        }

        return (execJ["data"] as? [String: Any])?["taskId"] as? String ?? ""
    }

    /// 轮询车端回执：完成 / 失败 / 20 秒超时。
    /// 状态值大小写、Success/Completed 混用都认，别因为拼写对不上就一直干等。
    static func pollResult(_ taskId: String) async throws -> String {
        let token = Store.get("token") ?? ""
        let carId = Store.get("carId") ?? ""
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let stData = try await send("\(base)/api/car/getControlInfo", method: "POST",
                                        form: ["token": token, "carId": carId, "id": taskId, "isNev": "0"])
            let stJ = try json(stData)
            guard codeInt(stJ) == 0, let dd = stJ["data"] as? [String: Any] else { continue }
            let hs = ((dd["handleStatus"] as? String) ?? "").lowercased()
            let rawDesc = (dd["handleStatusDesc"] as? String) ?? (dd["resultDesc"] as? String) ?? ""
            let desc = rawDesc.count > 40 ? String(rawDesc.prefix(40)) : rawDesc
            if hs.contains("complete") || hs.contains("success") { return "成功" }
            // 车端明确失败/超时/离线就别再干等 20 秒
            if hs.contains("fail") { throw APIError.bad(desc.isEmpty ? "车端执行失败" : desc) }
            if hs.contains("timeout") { throw APIError.bad(desc.isEmpty ? "车端超时未响应" : desc) }
            if hs.contains("offline") { throw APIError.bad(desc.isEmpty ? "车辆离线" : desc) }
            // Initialized / Runing 这类中间态继续轮询
        }
        return "已下发（状态超时）"
    }
}

enum APIError: LocalizedError {
    case bad(String)
    var errorDescription: String? {
        switch self {
        case .bad(let m): return m
        }
    }
}
