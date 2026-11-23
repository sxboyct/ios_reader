import Foundation

/// Xiangse's XXTEA container: little-endian words, zero padding and a trailing plaintext length.
/// This decodes a source container; it does not implement site response decryption or nativeTool APIs.
public enum XBSData {
    public static func json(_ data: Data) throws -> Data {
        guard data.count <= HTTPClient.subscriptionLimit else { throw TVError.unsupported("书源超过 32 MB。") }
        if (try? JSONSerialization.jsonObject(with: data)) != nil { return data }
        guard data.count >= 8, data.count.isMultiple(of: 4) else { throw TVError.unsupported("文件不是有效的 JSON / XBS 书源。") }
        let bytes = [UInt8](data)
        var words = stride(from: 0, to: bytes.count, by: 4).map { i in
            UInt32(bytes[i]) | UInt32(bytes[i + 1]) << 8 | UInt32(bytes[i + 2]) << 16 | UInt32(bytes[i + 3]) << 24
        }
        let key: [UInt32] = [0xe8bc87e5, 0xbbe686a4, 0x9187e9bf, 0xe5a1bae6]
        let delta: UInt32 = 0x9e3779b9
        let rounds = 6 + 52 / words.count
        var sum = UInt32(rounds) &* delta
        var y = words[0]
        func mix(_ y: UInt32, _ z: UInt32, _ p: Int, _ e: Int, _ sum: UInt32) -> UInt32 {
            ((z >> 5 ^ y << 2) &+ (y >> 3 ^ z << 4)) ^ ((sum ^ y) &+ (key[(p & 3) ^ e] ^ z))
        }
        for _ in 0..<rounds {
            let e = Int(sum >> 2 & 3)
            for p in stride(from: words.count - 1, through: 1, by: -1) {
                words[p] = words[p] &- mix(y, words[p - 1], p, e, sum)
                y = words[p]
            }
            words[0] = words[0] &- mix(y, words[words.count - 1], 0, e, sum)
            y = words[0]; sum = sum &- delta
        }
        let length = Int(words[words.count - 1]), padded = data.count - 4
        guard length >= padded - 3, length <= padded else { throw TVError.unsupported("XBS 文件损坏或编码不受支持。") }
        let decoded = Data((0..<length).map { UInt8(truncatingIfNeeded: words[$0 / 4] >> (($0 % 4) * 8)) })
        guard (try? JSONSerialization.jsonObject(with: decoded)) != nil else { throw TVError.unsupported("XBS 中没有有效的 JSON 书源。") }
        return decoded
    }
}
