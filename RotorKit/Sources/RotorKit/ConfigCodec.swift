import Foundation

public enum ParamValue: Equatable {
    case int(Int)
    case double(Double)
    public var intValue: Int {
        switch self { case .int(let v): return v; case .double(let d): return Int(d) }
    }
    public var doubleValue: Double {
        switch self { case .int(let v): return Double(v); case .double(let d): return d }
    }
}

/// mcconf/appconf 序列化/反序列化，由 ConfigParams 驱动。
/// 线上：uint32 签名 + 依 serializeOrder 逐参数按 vTx 编码（大端）。
public final class ConfigCodec {
    public let cp: ConfigParams
    public let order: [Param]
    public let signature: UInt32

    public init(_ cp: ConfigParams) {
        self.cp = cp
        self.order = cp.serializeOrder
        self.signature = cp.signature()
    }

    public static func load(path: String) -> ConfigCodec? {
        guard let cp = ConfigParams.parse(path: path) else { return nil }
        return ConfigCodec(cp)
    }

    public func defaults() -> [String: ParamValue] {
        var out: [String: ParamValue] = [:]
        for p in order {
            out[p.name] = (p.type == CfgT.double.rawValue) ? .double(p.valDouble) : .int(p.valInt)
        }
        return out
    }

    private func encode(_ w: inout BufWriter, _ p: Param, _ v: ParamValue) {
        switch p.type {
        case CfgT.enum.rawValue, CfgT.bool.rawValue, CfgT.bitfield.rawValue:
            w.i8(v.intValue)
        case CfgT.int.rawValue:
            switch p.vTx {
            case VescTx.u8.rawValue: w.u8(v.intValue)
            case VescTx.i8.rawValue: w.i8(v.intValue)
            case VescTx.u16.rawValue: w.u16(v.intValue)
            case VescTx.i16.rawValue: w.i16(v.intValue)
            case VescTx.u32.rawValue, VescTx.i32.rawValue: w.i32(v.intValue)
            default: w.i32(v.intValue)
            }
        case CfgT.double.rawValue:
            switch p.vTx {
            case VescTx.d16.rawValue: w.f16(v.doubleValue, p.vTxDoubleScale)
            case VescTx.d32.rawValue: w.f32(v.doubleValue, p.vTxDoubleScale)
            default: w.f32auto(v.doubleValue)     // d32auto
            }
        case CfgT.qstring.rawValue:
            w.raw(Array(String(v.intValue).utf8) + [0])
        default:
            w.i8(v.intValue)
        }
    }

    private func decode(_ r: inout BufReader, _ p: Param) -> ParamValue {
        switch p.type {
        case CfgT.enum.rawValue, CfgT.bool.rawValue: return .int(r.i8())
        case CfgT.bitfield.rawValue: return .int(r.u8())
        case CfgT.int.rawValue:
            switch p.vTx {
            case VescTx.u8.rawValue: return .int(r.u8())
            case VescTx.i8.rawValue: return .int(r.i8())
            case VescTx.u16.rawValue: return .int(r.u16())
            case VescTx.i16.rawValue: return .int(r.i16())
            case VescTx.u32.rawValue: return .int(Int(r.u32()))
            default: return .int(r.i32())
            }
        case CfgT.double.rawValue:
            switch p.vTx {
            case VescTx.d16.rawValue: return .double(r.f16(p.vTxDoubleScale))
            case VescTx.d32.rawValue: return .double(r.f32(p.vTxDoubleScale))
            default: return .double(r.f32auto())
            }
        case CfgT.qstring.rawValue:
            var bytes: [UInt8] = []
            while true { let b = r.u8(); if b == 0 { break }; bytes.append(UInt8(b)) }
            return .int(Int(String(decoding: bytes, as: UTF8.self)) ?? 0)
        default:
            return .int(r.i8())
        }
    }

    public func pack(_ values: [String: ParamValue], signature sig: UInt32? = nil) -> [UInt8] {
        var w = BufWriter()
        w.u32(sig ?? signature)
        for p in order { encode(&w, p, values[p.name] ?? .int(0)) }
        return w.bytes
    }

    /// 按参数在线路上的实际编码比较，而不是直接比较 `Double`。
    /// 浮点参数写入电机后会经过 d16/d32/d32auto 量化，数值回读时末位可能略有变化；
    /// 只要重新编码后的字节相同，就表示该参数确实按预期保存。
    public func changedParameterNames(
        expected: [String: ParamValue], actual: [String: ParamValue]
    ) -> [String] {
        order.compactMap { parameter in
            guard let expectedValue = expected[parameter.name],
                  let actualValue = actual[parameter.name] else {
                return parameter.name
            }
            var expectedWriter = BufWriter()
            var actualWriter = BufWriter()
            encode(&expectedWriter, parameter, expectedValue)
            encode(&actualWriter, parameter, actualValue)
            return expectedWriter.bytes == actualWriter.bytes ? nil : parameter.name
        }
    }

    public func unpack(_ payload: [UInt8]) -> (UInt32, [String: ParamValue]) {
        var r = BufReader(payload)
        let sig = r.u32()
        var values: [String: ParamValue] = [:]
        for p in order { values[p.name] = decode(&r, p) }
        return (sig, values)
    }
}
