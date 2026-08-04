import Foundation

/// 设备**能做什么**，而不是设备**是什么型号**。
///
/// 界面和上层逻辑应该问能力，不问世代。问型号会让每加一款设备就要回头
/// 修改所有判断点；问能力则只需要在设备档案里勾选。
public enum Capability: String, CaseIterable, Sendable {
    /// MIT 五参数阻抗控制（`0x60`）。V3.4 起并入主固件；更早的世代需要
    /// 跳到独立的 MIT 应用，因此不算具备本能力。
    case mitControl

    /// 文本终端通道（`COMM_TERMINAL_CMD` / `COMM_PRINT`）。
    case terminalChannel

    /// CAN 周期状态帧分级（`send_can_status`）。
    case canStatusLevels

    /// 固件上传走 bootloader 的 IAP 原始帧；否则走擦除 + 分块暂存区。
    case iapFirmwareUpload

    /// 可在 Servo / MIT 应用之间跳转。
    case applicationSwitching

    /// 位置 + 速度复合控制指令。
    case positionSpeedControl

    /// 参数辨识（电阻、电感、磁链、编码器）。
    case parameterDetection

    /// 写配置后可以立刻回读。
    ///
    /// 旧世代在写入后需要一段沉降时间，过早回读会得到**假失败**——
    /// 值其实写进去了，但读回来还是旧的。具备本能力的设备不需要这层等待。
    case immediateConfigReadback
}

/// 配置参数表的 schema。选哪一份由设备档案决定，不由调用点判断世代。
public enum ConfigSchema: String, Sendable {
    case vesc
    case v3
}
