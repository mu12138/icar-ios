import Foundation
import Security

/// 车端指令要用 RSA-OAEP(SHA-256) 加密，公钥是服务端下发的 X.509 SPKI DER
enum RSACrypto {

    /// SPKI -> SecKey
    static func publicKey(fromSPKI der: Data) -> SecKey? {
        guard let pkcs1 = stripSPKI(der) else { return nil }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
        ]
        var err: Unmanaged<CFError>?
        return SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &err)
    }

    /// RSA-OAEP + SHA-256 加密
    static func encryptOAEP(_ plain: Data, key: SecKey) -> Data? {
        var err: Unmanaged<CFError>?
        return SecKeyCreateEncryptedData(key, .rsaEncryptionOAEPSHA256, plain as CFData, &err) as Data?
    }

    // MARK: - 极简 DER 解析

    private struct TLV {
        let tag: UInt8
        let start: Int   // 内容起点
        let end: Int     // 内容终点
    }

    private static func readTLV(_ d: Data, _ idx: inout Int) -> TLV? {
        guard idx < d.count else { return nil }
        let tag = d[idx]
        idx += 1
        guard idx < d.count else { return nil }
        var len = Int(d[idx])
        idx += 1
        if len & 0x80 != 0 {
            let n = len & 0x7F
            guard n > 0, n <= 4, idx + n <= d.count else { return nil }
            len = 0
            for _ in 0..<n {
                len = (len << 8) | Int(d[idx])
                idx += 1
            }
        }
        guard len >= 0, idx + len <= d.count else { return nil }
        return TLV(tag: tag, start: idx, end: idx + len)
    }

    /// SPKI 结构：SEQUENCE { 算法SEQUENCE, BIT STRING( PKCS#1 ) }
    private static func stripSPKI(_ der: Data) -> Data? {
        var i = 0
        guard let outer = readTLV(der, &i), outer.tag == 0x30 else { return nil }
        var p = outer.start
        guard let alg = readTLV(der, &p), alg.tag == 0x30 else { return nil }
        p = alg.end
        guard let bit = readTLV(der, &p), bit.tag == 0x03 else { return nil }
        let s = bit.start + 1          // 跳过「未使用位数」那一字节
        guard s < bit.end else { return nil }
        return der.subdata(in: s..<bit.end)
    }
}
