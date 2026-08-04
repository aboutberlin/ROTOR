import Foundation

/// V3 世代的上传：走 bootloader 的 IAP 原始帧。
///
/// 与 `VescStagingUpload` 有三处根本不同，不是参数差异：
/// **没有擦除命令**；块号 × 128 就是镜像偏移；设备在第一个 ACK 里下发
/// **会话令牌**，之后每一包都必须携带它。
///
/// 令牌那条是最容易踩的：拿不到 ACK 就学不到令牌，于是永远推进不了第 0 块。
/// 官方工具在这种情况下会无限重发——实测把第 0 块原地发了 12114 次。
/// 这里改为有界失败，把"设备没在听"变成一条明确的错误而不是一条卡死的进度条。
public struct IAPRawUpload: FirmwareUploadStrategy {
    public let name = "IAP raw"
    public let maxAttemptsPerBlock: Int
    /// 每次尝试后等待 ACK 的轮询次数，每轮 2 ms。
    private let ackPollRounds = 200

    public init(maxAttemptsPerBlock: Int = 5) {
        self.maxAttemptsPerBlock = maxAttemptsPerBlock
    }

    public func upload(
        image: [UInt8],
        host: FirmwareUploadHost,
        progress: ((Double) -> Void)?
    ) -> Result<FirmwareUploadReceipt, FirmwareUploadFailure> {
        guard !image.isEmpty else { return .failure(.emptyImage) }
        let blockSize = RotorV3IAP.blockSize
        let blockCount = (image.count + blockSize - 1) / blockSize
        guard blockCount <= Int(UInt16.max) else {
            return .failure(.invalidImageSize(image.count))
        }

        // 数据流之前的单个控制包。
        host.uploadWriteRaw(RotorV3IAP.controlPacket(sequence: host.uploadNextIAPSequence()))
        firmwareUploadSleep(0.05)

        var token = RotorV3IAP.initialSessionToken
        var rx: [UInt8] = []
        var blockIndex = 0
        var written = 0
        progress?(0)

        while blockIndex < blockCount {
            let start = blockIndex * blockSize
            let payload = Array(image[start..<Swift.min(start + blockSize, image.count)])
            var attempts = 0
            var advancedTo: Int?

            while attempts < maxAttemptsPerBlock, advancedTo == nil {
                attempts += 1
                guard let packet = RotorV3IAP.dataPacket(
                    sequence: host.uploadNextIAPSequence(),
                    sessionToken: token,
                    blockIndex: UInt16(blockIndex),
                    data: payload
                ) else { return .failure(.invalidImageSize(image.count)) }
                host.uploadWriteRaw(packet)

                // 设备会把多个 ACK 粘在一次读里，所以按魔数+长度切帧，
                // 不能假设“一次读 = 一帧”。
                for _ in 0..<ackPollRounds {
                    let chunk = host.uploadReadRaw(max: 512)
                    if !chunk.isEmpty { rx.append(contentsOf: chunk) }
                    let parsed = RotorV3IAP.parseAcks(rx)
                    if parsed.consumed > 0 { rx.removeFirst(parsed.consumed) }
                    if let ack = parsed.acks.last {
                        token = ack.sessionToken
                        if Int(ack.nextBlock) > blockIndex { advancedTo = Int(ack.nextBlock) }
                        break
                    }
                    firmwareUploadSleep(0.002)
                }
            }

            guard let next = advancedTo else {
                return .failure(.blockNotAcknowledged(block: blockIndex, attempts: attempts))
            }
            written += next - blockIndex
            blockIndex = next
            progress?(Swift.min(1.0, Double(blockIndex) / Double(blockCount)))
        }

        return .success(FirmwareUploadReceipt(
            imageSize: image.count,
            imageCRC16: CRC.crc16(image),
            transmittedSize: blockCount * blockSize,
            writtenChunks: written,
            skippedChunks: 0
        ))
    }
}
