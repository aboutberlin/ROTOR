# RotorKit + RotorApp（Swift / 原生 Mac）

阶段二：原生 Mac App 与其协议核心。核心逻辑从已验证的 Python 参考实现移植，**逐字节等价**。

## 构建 / 运行

```bash
cd apps/RotorKit

# 1) 验证核心（无需硬件/Xcode，Command Line Tools 即可）
swift run kitcheck            # 30 项黄金向量 + 端到端，全绿

# 2) 打包成可双击的 App
./make_app.sh                 # 产出 Rotor.app
open Rotor.app

# 3) 或在 Xcode 里开发（推荐，可视化调试）
#    用 Xcode 打开 Package.swift → 选 RotorApp scheme → Run
```

> 本机只有 Command Line Tools（无完整 Xcode）→ 可 `swift build` / `swift run` / 打包，
> 但 `swift test`(XCTest) 与 GUI 可视化需完整 Xcode。故用 `kitcheck` 做核心验证。

## 目录
```
Sources/RotorKit/   协议核心（与 Python 等价，kitcheck 验证）
  CRC · Packet(PacketDecoder) · Buffers · Control · ConfigParams(XMLParser)
  · ConfigCodec · Values · Simulator · Transport(串口+回环) · Client
Sources/kitcheck/      可执行验证器（swift run kitcheck）
Sources/RotorApp/   SwiftUI App
  RotorApp(入口) · AppModel · ConnectionView · DashboardView
  · ControlView · ConfigView · FirmwareView · Components · SerialPorts
  mcconf.xml / appconf.xml（内嵌资源）
Tests/                 XCTest（供 Xcode）
make_app.sh            打包 .app
```

## 现状（诚实清单）

**已验证可用（本机 swift run kitcheck 全绿）**
- 协议/CRC/封包/buffer/float32_auto —— 与 Python 逐字节一致
- 配置签名 `0xdc733ebd`、pack 437B/crc 5819、字节稳定往返
- 端到端：客户端↔模拟器 握手 / 实时 / 读-改-写 mcconf / 错误签名被拒

**App 已编译通过（release 构建 + 打包成功）**，功能对模拟器可用：
- 连接（模拟器 / UART 串口 + 端口/波特率选择）
- 实时仪表（转速/电压/电流/温度/占空比/位置/故障）
- 伺服控制（占空比/电流/转速/位置 + 急停）
- 参数编辑（139 参数分组、搜索、读取/修改/写入、签名显示、脏标记）

**尚未实现 / 下一步（明确标注，不含糊）**
- **CAN 通道**：目前仅 UART + 回环；CAN 传输待加（手册有 CAN 帧规格）。
- **MIT 力控**：走 Rotor 0xAA 运动协议，待在协议层补齐后接入。
- **固件升级写入**：命令已知（JUMP_TO_BOOTLOADER/ERASE/WRITE），为安全起见待真机校验后实现。
- **.McParams/.AppParams 导入导出**：UI 已占位。
- **GUI 可视化**：本机无法运行窗口，需你在 Xcode/真机上看并迭代外观。
