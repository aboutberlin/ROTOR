import Foundation

/// V1/V2 世代的上传：先擦除暂存区，再按偏移分块写入。
///
/// 线上数据不是裸镜像——前 6 字节是原始长度(uint32) + CRC16，bootloader
/// 靠它校验并提交新应用。全 `0xFF` 的块可以跳过，因为擦除后本来就是 `0xFF`。
public struct VescStagingUpload: FirmwareUploadStrategy {
    public let name = "VESC staging"
    public let chunkSize: Int
    public let attemptsPerChunk: Int

    public init(chunkSize: Int = 384, attemptsPerChunk: Int = 3) {
        self.chunkSize = chunkSize
        self.attemptsPerChunk = attemptsPerChunk
    }

    public func upload(
        image: [UInt8],
        host: FirmwareUploadHost,
        progress: ((Double) -> Void)?
    ) -> Result<FirmwareUploadReceipt, FirmwareUploadFailure> {
        guard !image.isEmpty else { return .failure(.emptyImage) }
        guard image.count <= Int(UInt32.max), chunkSize > 0, chunkSize <= 1_024 else {
            return .failure(.invalidImageSize(image.count))
        }
        guard erase(size: image.count, host: host) else { return .failure(.eraseRejected) }

        var header = BufWriter()
        header.u32(UInt32(image.count))
        header.u16(Int(CRC.crc16(image)))
        let payload = header.bytes + image

        var offset = 0
        var written = 0
        var skipped = 0
        progress?(0)

        while offset < payload.count {
            let end = Swift.min(offset + chunkSize, payload.count)
            let chunk = Array(payload[offset..<end])
            if chunk.allSatisfy({ $0 == 0xFF }) {
                skipped += 1
            } else {
                var accepted = false
                for _ in 0..<attemptsPerChunk where !accepted {
                    accepted = write(offset: UInt32(offset), data: chunk, host: host)
                }
                guard accepted else {
                    return .failure(.chunkRejected(offset: offset, length: chunk.count))
                }
                written += 1
            }
            offset = end
            progress?(Double(offset) / Double(payload.count))
        }

        return .success(FirmwareUploadReceipt(
            imageSize: image.count,
            imageCRC16: CRC.crc16(image),
            transmittedSize: payload.count,
            writtenChunks: written,
            skippedChunks: skipped
        ))
    }

    private func erase(size: Int, host: FirmwareUploadHost) -> Bool {
        guard size > 0, size <= Int(UInt32.max) else { return false }
        var writer = BufWriter()
        writer.u8(Comm.eraseNewApp.rawValue)
        writer.u32(UInt32(size))
        let response = host.uploadSendVesc(writer.bytes,
                                           expect: Comm.eraseNewApp.rawValue,
                                           retries: 10_000)
        return (response?.count ?? 0) >= 2 && response?[1] != 0
    }

    private func write(offset: UInt32, data: [UInt8], host: FirmwareUploadHost) -> Bool {
        guard !data.isEmpty else { return true }
        var writer = BufWriter()
        writer.u8(Comm.writeNewAppData.rawValue)
        writer.u32(offset)
        writer.raw(data)
        let response = host.uploadSendVesc(writer.bytes,
                                           expect: Comm.writeNewAppData.rawValue,
                                           retries: 1_500)
        guard let response, response.count >= 2, response[1] != 0 else { return false }
        // 较新的固件会回显 offset；存在就必须完全一致，否则说明写错了位置。
        if response.count >= 6 {
            var reader = BufReader(response.dropFirst(2))
            return reader.u32() == offset
        }
        return true
    }
}
