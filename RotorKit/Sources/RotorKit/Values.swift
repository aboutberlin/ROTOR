import Foundation

public let faultCodes: [Int: String] = [
    0: "NONE", 1: "OVER_VOLTAGE", 2: "UNDER_VOLTAGE", 3: "DRV", 4: "ABS_OVER_CURRENT",
    5: "OVER_TEMP_FET", 6: "OVER_TEMP_MOTOR", 7: "GATE_DRIVER_OVER_VOLTAGE",
    8: "GATE_DRIVER_UNDER_VOLTAGE", 9: "MCU_UNDER_VOLTAGE", 10: "BOOTING_FROM_WATCHDOG_RESET",
    11: "ENCODER_SPI", 12: "ENCODER_SINCOS_BELOW_MIN_AMPLITUDE",
    13: "ENCODER_SINCOS_ABOVE_MAX_AMPLITUDE", 14: "FLASH_CORRUPTION",
    15: "HIGH_OFFSET_CURRENT_SENSOR_1", 16: "HIGH_OFFSET_CURRENT_SENSOR_2",
    17: "HIGH_OFFSET_CURRENT_SENSOR_3", 18: "UNBALANCED_CURRENTS",
]

/// COMM_GET_VALUES 回包（73 字节，bldc/3.6x）。
public struct MotorValues {
    public var tempFet = 0.0, tempMotor = 0.0
    public var currentMotor = 0.0, currentIn = 0.0, idCurr = 0.0, iqCurr = 0.0
    public var duty = 0.0, rpm = 0.0, vIn = 0.0
    public var ampHours = 0.0, ampHoursCharged = 0.0, wattHours = 0.0, wattHoursCharged = 0.0
    public var tachometer = 0, tachometerAbs = 0
    public var faultCode = 0, faultStr = "NONE"
    public var pidPos = 0.0, controllerId = 0
    public var tempMos1 = 0.0, tempMos2 = 0.0, tempMos3 = 0.0
    public var vD = 0.0, vQ = 0.0
    public var currentControlMode = 0
    public var encoderAngle = 0.0, outerEncoderAngle = 0.0

    public init() {}

    public static func parse(_ payload: [UInt8]) -> MotorValues {
        var r = BufReader(payload)
        _ = r.u8()  // id echo
        var v = MotorValues()
        v.tempFet = Double(r.i16()) / 10
        v.tempMotor = Double(r.i16()) / 10
        v.currentMotor = Double(r.i32()) / 100
        v.currentIn = Double(r.i32()) / 100
        v.idCurr = Double(r.i32()) / 100
        v.iqCurr = Double(r.i32()) / 100
        v.duty = Double(r.i16()) / 1000
        v.rpm = Double(r.i32())
        v.vIn = Double(r.i16()) / 10
        v.ampHours = Double(r.i32()) / 10000
        v.ampHoursCharged = Double(r.i32()) / 10000
        v.wattHours = Double(r.i32()) / 10000
        v.wattHoursCharged = Double(r.i32()) / 10000
        v.tachometer = r.i32()
        v.tachometerAbs = r.i32()
        v.faultCode = r.u8()
        v.faultStr = faultCodes[v.faultCode] ?? "UNKNOWN(\(v.faultCode))"
        v.pidPos = Double(r.i32()) / 1_000_000
        v.controllerId = r.u8()
        if r.remaining >= 6 {
            v.tempMos1 = Double(r.i16()) / 10
            v.tempMos2 = Double(r.i16()) / 10
            v.tempMos3 = Double(r.i16()) / 10
        }
        if r.remaining >= 8 {
            v.vD = Double(r.i32()) / 1000
            v.vQ = Double(r.i32()) / 1000
        }
        return v
    }

    /// AK V3 的 COMM_GET_VALUES=69 布局。
    ///
    /// SW_V3.2 返回 85 字节，末尾同时带 encoderAngle 和 outerEncoderAngle；
    /// SW_V3.4 返回 81 字节，只带 encoderAngle。前 81 字节布局相同。
    public static func parseRotorV3(_ payload: [UInt8]) -> MotorValues? {
        guard payload.count >= 81,
              payload.first == UInt8(RotorV3Comm.getValues.rawValue) else {
            return nil
        }
        var r = BufReader(payload)
        _ = r.u8() // COMM_GET_VALUES echo
        var v = MotorValues()
        v.tempFet = Double(r.i16()) / 10
        v.tempMotor = Double(r.i16()) / 10
        v.currentMotor = Double(r.i32()) / 100
        v.currentIn = Double(r.i32()) / 100
        v.idCurr = Double(r.i32()) / 100
        v.iqCurr = Double(r.i32()) / 100
        v.duty = Double(r.i16()) / 1000
        v.rpm = Double(r.i32())
        v.vIn = Double(r.i16()) / 10

        // V3 在这里保留 24 字节；不是标准 VESC 的 Ah/Wh/tachometer 字段。
        for _ in 0..<6 { _ = r.u32() }

        v.faultCode = r.u8()
        v.faultStr = faultCodes[v.faultCode] ?? "UNKNOWN(\(v.faultCode))"
        v.pidPos = r.f32auto()
        v.controllerId = r.u8()
        v.tempMos1 = Double(r.i16()) / 10
        v.tempMos2 = Double(r.i16()) / 10
        v.tempMos3 = Double(r.i16()) / 10
        v.vD = Double(r.i32()) / 1000
        v.vQ = Double(r.i32()) / 1000
        v.currentControlMode = r.i32()
        v.encoderAngle = r.f32auto()
        if r.remaining >= 4 {
            v.outerEncoderAngle = r.f32auto()
        }
        return v
    }
}
