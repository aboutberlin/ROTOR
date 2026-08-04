import Foundation

/// CFG_T（vesc_tool datatypes.h）
public enum CfgT: Int { case undefined = 0, double, int, qstring, `enum`, bool, bitfield }
/// VESC_TX_T
public enum VescTx: Int { case undefined = 0, u8, i8, u16, i16, u32, i32, d16, d32, d32auto }

public struct Param {
    public var name: String
    public var longName: String = ""
    public var type: Int = 0
    public var transmittable: Bool = false
    public var vTx: Int = 0
    public var vTxDoubleScale: Double = 1.0
    public var enumNames: [String] = []
    public var valInt: Int = 0
    public var valDouble: Double = 0
    public init(name: String) { self.name = name }
}

/// 解析 ConfigParams XML（mcconf/appconf 参数定义表），并计算配置签名。
public final class ConfigParams: NSObject, XMLParserDelegate {
    public private(set) var params: [Param] = []
    private var serialOrderNames: [String] = []

    private var stack: [String] = []
    private var cur: Param?
    private var text = ""

    public static func parse(path: String) -> ConfigParams? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        let cp = ConfigParams()
        let p = XMLParser(data: data)
        p.delegate = cp
        return p.parse() ? cp : nil
    }

    // VESC XML 可用 <SerOrder> 把线上顺序与界面/分组中的定义顺序分开。
    // 较旧的 XML 没有该节点时才回退到文档顺序。
    public var serializeOrder: [Param] {
        let transmittable = params.filter { $0.transmittable }
        guard !serialOrderNames.isEmpty else { return transmittable }
        let byName = Dictionary(uniqueKeysWithValues: transmittable.map { ($0.name, $0) })
        return serialOrderNames.compactMap { byName[$0] }
    }

    public func signature() -> UInt32 {
        var s = ""
        for p in serializeOrder {
            s += p.name
            s += String(p.type)
            s += String(p.vTx)
            for n in p.enumNames { s += n }
        }
        return CRC.crc32c(Array(s.utf8))
    }

    private static func toInt(_ s: String) -> Int { Int(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) ?? 0 }
    private static func toDouble(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)) ?? 0 }

    // MARK: XMLParserDelegate
    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                       qualifiedName qName: String?, attributes: [String: String] = [:]) {
        stack.append(name)
        text = ""
        if stack.count == 3, stack[1] == "Params" {
            cur = Param(name: name)                       // ConfigParams > Params > <paramName>
        }
    }

    public func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                       qualifiedName qName: String?) {
        if stack.count == 4, stack[1] == "Params", cur != nil { // 参数下的字段
            switch name {
            case "longName": cur!.longName = text
            case "type": cur!.type = ConfigParams.toInt(text)
            case "transmittable": cur!.transmittable = (text.trimmingCharacters(in: .whitespaces) == "1")
            case "vTx": cur!.vTx = ConfigParams.toInt(text)
            case "vTxDoubleScale": cur!.vTxDoubleScale = ConfigParams.toDouble(text)
            case "enumNames": cur!.enumNames.append(text)
            case "valInt": cur!.valInt = ConfigParams.toInt(text)
            case "valDouble": cur!.valDouble = ConfigParams.toDouble(text)
            default: break
            }
        } else if stack.count == 3, stack[1] == "Params", let c = cur {
            params.append(c); cur = nil
        } else if stack.count == 3, stack[1] == "SerOrder", name == "ser" {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { serialOrderNames.append(value) }
        }
        stack.removeLast()
    }
}
