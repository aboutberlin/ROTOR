import XCTest
@testable import RotorKit

// 这些在完整 Xcode 下 `swift test` 运行；CLT 环境请用 `swift run kitcheck`。
final class RotorKitTests: XCTestCase {
    func testCRC16() { XCTAssertEqual(CRC.crc16(Array("123456789".utf8)), 0x31C3) }
    func testCRC32C() { XCTAssertEqual(CRC.crc32c(Array("123456789".utf8)), 0xE3069283) }
    func testFWFrame() { XCTAssertEqual(Packet.encodeCmd(.fwVersion).hex, "020100000003") }
    func testV3FWFrame() {
        XCTAssertEqual(RotorV3Packet.encodeCmd(.fwVersion).hex, "aa014158e5bb")
    }
    func testV3RebootFrame() {
        XCTAssertEqual(RotorV3Packet.encodeCmd(.reboot).hex, "aa015ebb3bbb")
    }
    func testV3IAPJumpApplicationFrame() {
        XCTAssertEqual(
            RotorV3IAP.jumpApplication(sequence: 0x30).hex,
            "ec960e30a10768"
        )
        XCTAssertEqual(
            RotorV3IAP.jumpApplication(sequence: 0x37).hex,
            "ec960e37a1076f"
        )
        XCTAssertEqual(
            RotorV3IAP.jumpApplication(sequence: 0xFF).hex,
            "ec960effa10737"
        )
    }

    /// 黄金向量取自真机成功升级抓包
    /// `reverse-engineering/captures/capture-SUCCESSFUL-UPLOAD-ak80-9-241122.jsonl`，
    /// 是官方 Windows 工具实际写入串口的原始字节，不是本项目构造的。
    private static func bytes(fromHex hex: String) -> [UInt8] {
        var out: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            out.append(UInt8(hex[index..<next], radix: 16)!)
            index = next
        }
        return out
    }

    func testV3IAPFirmwareDataPacketMatchesCapturedBytes() {
        let payload = Self.bytes(fromHex:
            "a1270708d1270708c1500708812d0708f12d0708512e0708b12e0708e1500708" +
            "41460708310907083109070831090708315107080151070821460708310907" +
            "0831090708e1340708d1350708310907083109070881490708310907" +
            "08a149070831090708310907083109070831090708310907083109070801280708"
        )
        XCTAssertEqual(payload.count, RotorV3IAP.blockSize)
        let packet = RotorV3IAP.dataPacket(
            sequence: 0x05,
            sessionToken: [0x00, 0x00, 0x04, 0x05],
            blockIndex: 1,
            data: payload
        )
        XCTAssertEqual(packet?.hex, "ec962d05a190000004050c00000180" + payload.hex + "a7")
    }

    func testV3IAPShortFinalBlockIsPaddedWith0xFF() {
        let packet = RotorV3IAP.dataPacket(
            sequence: 0x10, sessionToken: [0, 0, 4, 5], blockIndex: 0x0C01, data: [0xAB, 0xCD]
        )
        XCTAssertEqual(packet?.count, 144)
        XCTAssertEqual(Array(packet![12...14]).hex, "0c0180")
        XCTAssertEqual(Array(packet![17..<143]), [UInt8](repeating: 0xFF, count: 126))
        XCTAssertEqual(packet?.last, packet!.dropLast().reduce(UInt8(0), &+))
    }

    func testV3IAPParsesGluedAndPartialAckStream() {
        // 三个真实 ACK 粘在一次读里，尾部再接半个未收全的帧。
        let glued = Self.bytes(fromHex:
            "7b8c2e00a10d000004050001ed" +
            "7b8c2e01a10d000004050001ee" +
            "7b8c2e02a10d000004050001ef"
        )
        let partial = Self.bytes(fromHex: "7b8c2e03a10d0000")
        let result = RotorV3IAP.parseAcks(glued + partial)
        XCTAssertEqual(result.acks.count, 3)
        XCTAssertEqual(result.consumed, glued.count) // 半帧保留给下次
        XCTAssertEqual(result.acks[0].sessionToken, [0x00, 0x00, 0x04, 0x05])
        XCTAssertEqual(result.acks[0].nextBlock, 1)
        XCTAssertEqual(result.acks[2].sequence, 0x02)
    }

    func testV3IAPRejectsAckWithBadChecksum() {
        let corrupted = Self.bytes(fromHex: "7b8c2e00a10d000004050001ee") // 正确应为 ed
        XCTAssertTrue(RotorV3IAP.parseAcks(corrupted).acks.isEmpty)
    }
    func testOutputConfigurationHealthDetectsZeroLimits() {
        let values: [String: ParamValue] = [
            "l_current_max_scale": .double(0),
            "l_current_min_scale": .double(1),
            "l_max_erpm": .double(100_000),
            "l_min_erpm": .double(-100_000),
            "l_max_duty": .double(0.95),
            "l_min_duty": .double(0.005),
            "l_watt_max": .double(1_500_000),
            "l_watt_min": .double(-1_500_000)
        ]
        XCTAssertEqual(
            MotorOutputConfigurationHealth(values: values).disabledFields,
            ["l_current_max_scale"]
        )
    }
    func testOutputConfigurationHealthAcceptsV3Defaults() {
        let values: [String: ParamValue] = [
            "l_current_max_scale": .double(1),
            "l_current_min_scale": .double(1),
            "l_max_erpm": .double(100_000),
            "l_min_erpm": .double(-100_000),
            "l_max_duty": .double(0.95),
            "l_min_duty": .double(0.005),
            "l_watt_max": .double(1_500_000),
            "l_watt_min": .double(-1_500_000)
        ]
        XCTAssertTrue(MotorOutputConfigurationHealth(values: values).isOutputEnabled)
    }
    func testOutputConfigurationHealthAcceptsZeroMinimumDutyOnV34() {
        let values: [String: ParamValue] = [
            "l_current_max_scale": .double(1),
            "l_current_min_scale": .double(1),
            "l_max_erpm": .double(100_000),
            "l_min_erpm": .double(-100_000),
            "l_max_duty": .double(0.95),
            "l_min_duty": .double(0),
            "l_watt_max": .double(1_500_000),
            "l_watt_min": .double(-1_500_000)
        ]
        XCTAssertTrue(MotorOutputConfigurationHealth(values: values).isOutputEnabled)
    }
    func testV3FrameDecoder() {
        let payload: [UInt8] = [UInt8(RotorV3Comm.fwVersion.rawValue), 5, 1, 6]
            + Array("CMESC_AK80_9_SW_V3.2".utf8) + [0]
        let encoded = RotorV3Packet.encode(payload)
        let decoder = RotorV3PacketDecoder()
        XCTAssertEqual(decoder.feed(Array(encoded.prefix(5))).count, 0)
        XCTAssertEqual(decoder.feed(Array(encoded.dropFirst(5))), [payload])
    }
    func testV34GetValuesWithoutOuterEncoderAngle() {
        let text = "45018afcda0000000000000000000000000000000000000000000000ee0000000300000000000000510000000f00000c22000039500044897dfd6800000000000000000001000000000000000a43715ea0"
        let chars = Array(text)
        let payload = stride(from: 0, to: chars.count, by: 2).compactMap {
            UInt8(String(chars[$0...$0 + 1]), radix: 16)
        }
        let values = MotorValues.parseRotorV3(payload)
        XCTAssertNotNil(values)
        XCTAssertEqual(values?.tempFet ?? 0, 39.4, accuracy: 0.001)
        XCTAssertEqual(values?.tempMotor ?? 0, -80.6, accuracy: 0.001)
        XCTAssertEqual(values?.vIn ?? 0, 23.8, accuracy: 0.001)
        XCTAssertEqual(values?.controllerId, 104)
        XCTAssertEqual(values?.currentControlMode, 10)
        XCTAssertEqual(values?.encoderAngle ?? 0, 241.36963, accuracy: 0.001)
        XCTAssertEqual(values?.outerEncoderAngle, 0)
    }
    func testF32Auto() {
        var w = BufWriter(); w.f32auto(3.14159)
        XCTAssertEqual(w.bytes.hex, "40490fcf")
    }
}
