import Foundation

/// 车况（字段映射与 Android 版一致）
struct CarStatus {
    var fuel: Int = 0            // 油量百分比
    var range: Int = 0           // 续航 km
    var odo: Double = 0          // 总里程
    var speed: Double = 0
    var tempIn: Int = 0
    var tempOut: Int = 0
    var locked: Bool = false
    var acOn: Bool = false
    var acTemp: String = "--"
    var online: Bool = false
    var time: String = "--"
    var voltage: Double = 0
    var doors: [Bool] = [false, false, false, false]   // FL FR BL BR
    var windows: [Bool] = [false, false, false, false]
    var sunroof: Bool = false
    var trunk: Bool = false

    init() {}

    init(raw d: [String: Any]) {
        func i(_ k: String) -> Int { (d[k] as? NSNumber)?.intValue ?? 0 }
        func db(_ k: String) -> Double { (d[k] as? NSNumber)?.doubleValue ?? 0 }

        // 油量优先用升数换算，remainingFuel 在部分车上恒为 100
        let liters = db("fuelLeftover")
        var pct = i("remainingFuel")
        if liters > 0 { pct = Int((liters / ChangAnAPI.tankL * 100).rounded()) }
        fuel = max(0, min(100, pct))

        range = i("remainedOilMile")
        odo = db("totalOdometer")
        speed = db("vehicleSpeed")
        tempIn = i("vehicleTemperature")
        tempOut = i("environmentalTemp")
        voltage = db("batteryVoltage")

        // 车门用 leftFrontDoor 这一组，*DoorStatus 在解锁后会误报
        locked = i("driverDoorLock") == 0 && i("passengerDoorLock") == 0
              && i("leftRearDoorLock") == 0 && i("rightRearDoorLock") == 0

        if let air = d["air"] as? [String: Any] {
            acOn = (air["status"] as? String) == "1"
            acTemp = air["temperature"] as? String ?? "--"
        }

        let t = d["terminalTime"] as? String ?? ""
        time = t.count >= 16 ? String(t.dropFirst(11).prefix(5)) : "--"
        if let date = Self.fmt.date(from: t) {
            online = Date().timeIntervalSince(date) < 15 * 60
        }

        doors = [i("leftFrontDoor") == 1, i("rightFrontDoor") == 1,
                 i("leftRearDoor") == 1, i("rightRearDoor") == 1]
        windows = [i("diverWindow") == 1, i("passengerWindow") == 1,
                   i("leftRearWindow") == 1, i("rightRearWindow") == 1]
        sunroof = i("sunroof") == 1
        trunk = i("trunk") == 1
    }

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// 快捷指令
struct Command: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    let cmd: String
    var danger: Bool = false
    var open: Bool = false   // true = 走开放平台（空调）

    static let all: [Command] = [
        .init(title: "解锁", symbol: "lock.open.fill", cmd: "UnLockDoor"),
        .init(title: "锁车", symbol: "lock.fill", cmd: "LockDoor"),
        .init(title: "开窗", symbol: "wind", cmd: "OpenWindow"),
        .init(title: "留缝", symbol: "rectangle.compress.vertical", cmd: "WindowSlit"),
        .init(title: "关窗", symbol: "wind.circle", cmd: "CloseWindow"),
        .init(title: "天窗翘", symbol: "sun.max", cmd: "SkyWindowLiftUp"),
        .init(title: "天窗开", symbol: "sun.max.fill", cmd: "OpenDormer"),
        .init(title: "关天窗", symbol: "sun.min", cmd: "CloseDormer"),
        .init(title: "启动", symbol: "power", cmd: "OpenEngine"),
        .init(title: "熄火", symbol: "power.circle", cmd: "CloseEngine", danger: true),
        .init(title: "开空调", symbol: "snowflake", cmd: "openAir", open: true),
        .init(title: "关空调", symbol: "snowflake.circle", cmd: "closeAir", open: true),
        .init(title: "闪灯", symbol: "light.max", cmd: "FlashLight"),
        .init(title: "寻车", symbol: "location.fill", cmd: "RemoteSearchCar"),
    ]
}
