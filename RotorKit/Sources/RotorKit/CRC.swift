import Foundation

/// CRC 实现，与 bldc/vesc_tool 对齐。
/// - crc16: CCITT/XMODEM，poly 0x1021，init 0x0000（封包用）
/// - crc32c: Castagnoli，poly 0x82F63B78 reflected，init/xorout 0xFFFFFFFF（配置签名用）
public enum CRC {
    static let tab16: [UInt16] = {
        var t = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var c = UInt16(i) << 8
            for _ in 0..<8 {
                c = (c & 0x8000) != 0 ? (c << 1) ^ 0x1021 : (c << 1)
            }
            t[i] = c
        }
        return t
    }()

    public static func crc16(_ data: [UInt8]) -> UInt16 {
        var cksum: UInt16 = 0
        for b in data {
            let idx = Int((cksum >> 8) ^ UInt16(b)) & 0xFF
            cksum = tab16[idx] ^ (cksum << 8)
        }
        return cksum
    }

    public static func crc16(_ data: ArraySlice<UInt8>) -> UInt16 { crc16(Array(data)) }

    public static func crc32c(_ data: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for b in data {
            crc ^= UInt32(b)
            for _ in 0..<8 {
                let mask = ~((crc & 1) &- 1)          // (crc&1) ? 0xFFFFFFFF : 0
                crc = (crc >> 1) ^ (0x82F63B78 & mask)
            }
        }
        return ~crc
    }
}
