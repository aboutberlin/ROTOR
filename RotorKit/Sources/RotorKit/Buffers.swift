import Foundation

/// 大端 buffer 读写，对齐 bldc/buffer.c。
public struct BufWriter {
    public private(set) var bytes: [UInt8] = []
    public init() {}

    public mutating func u8(_ v: Int)  { bytes.append(UInt8(truncatingIfNeeded: v)) }
    public mutating func i8(_ v: Int)  { bytes.append(UInt8(truncatingIfNeeded: v)) }

    public mutating func u16(_ v: Int) {
        let x = UInt16(truncatingIfNeeded: v)
        bytes.append(UInt8(x >> 8)); bytes.append(UInt8(x & 0xFF))
    }
    public mutating func i16(_ v: Int) { u16(v) }

    public mutating func u32(_ v: UInt32) {
        bytes.append(UInt8((v >> 24) & 0xFF)); bytes.append(UInt8((v >> 16) & 0xFF))
        bytes.append(UInt8((v >> 8) & 0xFF));  bytes.append(UInt8(v & 0xFF))
    }
    public mutating func i32(_ v: Int) { u32(UInt32(truncatingIfNeeded: v)) }

    public mutating func f16(_ v: Double, _ scale: Double) { i16(Int((v * scale).rounded())) }
    public mutating func f32(_ v: Double, _ scale: Double) { i32(Int((v * scale).rounded())) }

    public mutating func f32auto(_ number: Double) {
        if number == 0 { u32(0); return }
        var e: Int32 = 0
        let sig = frexp(number, &e)
        let sigAbs = abs(sig)
        var sigI: UInt32 = 0
        if sigAbs >= 0.5 {
            sigI = UInt32((sigAbs - 0.5) * 2.0 * 8388608.0)
            e += 126
        }
        var res: UInt32 = (UInt32(truncatingIfNeeded: e) & 0xFF) << 23 | (sigI & 0x7FFFFF)
        if sig < 0 { res |= (1 << 31) }
        u32(res)
    }

    public mutating func raw(_ b: [UInt8]) { bytes.append(contentsOf: b) }
}

public struct BufReader {
    let data: [UInt8]
    public private(set) var i: Int = 0
    public init(_ d: [UInt8]) { data = d }
    public init(_ d: ArraySlice<UInt8>) { data = Array(d) }

    public mutating func u8() -> Int { let v = Int(data[i]); i += 1; return v }
    public mutating func i8() -> Int { let v = u8(); return v >= 128 ? v - 256 : v }

    public mutating func u16() -> Int { let v = (Int(data[i]) << 8) | Int(data[i+1]); i += 2; return v }
    public mutating func i16() -> Int { let v = u16(); return v >= 32768 ? v - 65536 : v }

    public mutating func u32() -> UInt32 {
        let v = (UInt32(data[i]) << 24) | (UInt32(data[i+1]) << 16) | (UInt32(data[i+2]) << 8) | UInt32(data[i+3])
        i += 4; return v
    }
    public mutating func i32() -> Int {
        let v = UInt32(u32()); return v >= 0x8000_0000 ? Int(v) - (1 << 32) : Int(v)
    }

    public mutating func f16(_ scale: Double) -> Double { Double(i16()) / scale }
    public mutating func f32(_ scale: Double) -> Double { Double(i32()) / scale }

    public mutating func f32auto() -> Double {
        let res = u32()
        if res == 0 { return 0 }
        var e = Int32((res >> 23) & 0xFF)
        let sigI = res & 0x7FFFFF
        let neg = (res & (1 << 31)) != 0
        var sig = 0.0
        if e != 0 || sigI != 0 {
            sig = Double(sigI) / 8388608.0 / 2.0 + 0.5
            e -= 126
        }
        let f = scalbn(sig, Int(e))
        return neg ? -f : f
    }

    public var remaining: Int { data.count - i }
}
