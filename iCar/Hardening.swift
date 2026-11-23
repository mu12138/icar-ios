import CryptoKit
import Darwin
import Foundation
import UIKit

/// 轻量加固：
/// - 构建期已经开了 -Osize、strip、dead-code stripping（project.yml）；
/// - 运行时做两件事：看有没有调试器/越狱环境（只记日志，不阻断，避免误伤），
///   以及校验网页资源有没有被改过（改过就按安卓那套 C 方案处理：界面照常，控车指令直接失败）。
enum Hardening {

    /// 网页资源被改过（或被换包）
    private(set) static var assetsTampered = false

    static func start() {
        checkDebugger()
        checkJailbreak()
        verifyWebAssets()
    }

    // MARK: - 网页资源校验

    private static func verifyWebAssets() {
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("WebUI") else {
            assetsTampered = true
            DebugLog.shared.add("⚠️ 找不到 WebUI 目录")
            return
        }
        var bad: [String] = []
        for (rel, expect) in WebHashes.map {
            let url = root.appendingPathComponent(rel)
            guard let data = try? Data(contentsOf: url) else {
                bad.append(rel + "(缺失)")
                continue
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if digest != expect { bad.append(rel) }
        }
        if bad.isEmpty {
            DebugLog.shared.add("资源校验通过（\(WebHashes.map.count) 个文件）")
        } else {
            assetsTampered = true
            DebugLog.shared.add("⚠️ 网页资源被修改：\(bad.joined(separator: ", "))")
        }
    }

    // MARK: - 调试器 / 越狱（只记日志）

    private static func checkDebugger() {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        let ok = mib.withUnsafeMutableBufferPointer { ptr -> Bool in
            sysctl(ptr.baseAddress, UInt32(ptr.count), &info, &size, nil, 0) == 0
        }
        if ok && (info.kp_proc.p_flag & P_TRACED) != 0 {
            DebugLog.shared.add("⚠️ 检测到调试器附加")
        }
    }

    private static func checkJailbreak() {
        let paths = [
            "/Applications/Cydia.app",
            "/Library/MobileSubstrate/MobileSubstrate.dylib",
            "/bin/bash",
            "/usr/sbin/sshd",
            "/private/var/lib/apt",
        ]
        let hit = paths.filter { FileManager.default.fileExists(atPath: $0) }
        if !hit.isEmpty {
            DebugLog.shared.add("⚠️ 检测到越狱环境：\(hit.joined(separator: ", "))")
        }
    }
}
