import Foundation

/// 长安车控接口（与 Android 版同一套）
enum ChangAnAPI {
    static let base = "https://incallapi.changan.com.cn"
    static let cac = "https://m.iov.changan.com.cn"
    static let clientId = "2c918082632162010163388048d60158"
    static let tankL: Double = 50   // 油箱容量（升），换车要改

    // MARK: - 底层请求

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
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.bad("服务端返回异常")
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
        guard (j["code"] as? Int ?? -1) == 0 else {
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
        guard let car = arr.first else { return }
        Store.set(car["carId"] as? String ?? "", for: "carId")
        Store.set(car["carName"] as? String ?? car["seriesName"] as? String ?? "我的车", for: "carName")
        Store.set(car["seriesName"] as? String ?? "", for: "seriesName")
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
        if (j["code"] as? Int) == 2 {          // token 过期，刷新后重试一次
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
        let carId = Store.get("carId") ?? ""
        guard !carId.isEmpty else { throw APIError.bad("未绑定车辆") }
        let j = try await getJSON("/app2/api/car/data?carId=\(carId)&keys=*&isNev=0&token=TOKEN")
        guard let d = j["data"] as? [String: Any] else { throw APIError.bad("车况为空") }
        return CarStatus(raw: d)
    }

    // MARK: - 下发指令

    /// 返回执行结果文字
    @discardableResult
    static func exec(_ cmd: String, extra: [String: String] = [:]) async throws -> String {
        try await ensureToken()
        let token = Store.get("token") ?? ""
        let carId = Store.get("carId") ?? ""
        guard !carId.isEmpty else { throw APIError.bad("未绑定车辆") }

        // 1. 一次性校验码
        let pinData = try await send("\(base)/app2/api/control/createPinVerifyCode",
                                     method: "POST", form: ["token": token])
        let pinJ = try json(pinData)
        guard (pinJ["code"] as? Int) == 0, let pinCode = pinJ["data"] as? String else {
            throw APIError.bad("PIN 获取失败")
        }

        // 2. 公钥
        let keyData = try await send("\(base)/app2/api/v2/security/key?carId=\(carId)&moblie=&token=\(esc(token))")
        let keyJ = try json(keyData)
        guard (keyJ["code"] as? Int) == 0, let keyB64 = keyJ["data"] as? String,
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
        guard (execJ["code"] as? Int) == 0 else {
            throw APIError.bad(execJ["msg"] as? String ?? "指令发送失败")
        }

        // 5. 轮询结果
        guard let d = execJ["data"] as? [String: Any],
              let taskId = d["taskId"] as? String, !taskId.isEmpty else {
            return "已下发"
        }
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 500_000_000)
            let stData = try await send("\(base)/api/car/getControlInfo", method: "POST",
                                        form: ["token": token, "carId": carId, "id": taskId, "isNev": "0"])
            let stJ = try json(stData)
            if (stJ["code"] as? Int) == 0, let dd = stJ["data"] as? [String: Any] {
                switch dd["handleStatus"] as? String {
                case "Completed": return "成功"
                case "Failed": throw APIError.bad(dd["handleStatusDesc"] as? String ?? "执行失败")
                default: continue
                }
            }
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
