import Foundation

/// 会直接把 Servo 输出或参数辨识限制为零的关键电机参数检查。
///
/// Rotor V3 固件会把这些字段相乘或作为上下限使用；读到 0 并不代表
/// “不限制”，而是会让对应方向的输出实际变成 0。
public struct MotorOutputConfigurationHealth: Equatable {
    public let disabledFields: [String]

    public var isOutputEnabled: Bool { disabledFields.isEmpty }

    public init(values: [String: ParamValue]) {
        var fields: [String] = []

        func disabled(_ name: String, when predicate: (Double) -> Bool) {
            guard let value = values[name]?.doubleValue, predicate(value) else { return }
            fields.append(name)
        }

        disabled("l_current_max_scale") { $0 <= 0 }
        disabled("l_current_min_scale") { $0 <= 0 }
        disabled("l_max_erpm") { $0 <= 0 }
        disabled("l_min_erpm") { $0 >= 0 }
        disabled("l_max_duty") { $0 <= 0 }
        // SW_V3.4 真机允许 l_min_duty = 0，且 Servo 控制正常；
        // 它不能像最大占空比为零那样被视为“输出禁用”。
        disabled("l_watt_max") { $0 <= 0 }
        disabled("l_watt_min") { $0 >= 0 }

        disabledFields = fields
    }
}
