import Foundation

/// 固件上传策略。
///
/// 不同世代的控制器用**完全不同**的方式接收固件，差异不是几个参数，
/// 而是两套独立协议：一套先擦除暂存区再按偏移写块，另一套走 bootloader
/// 的原始帧、带会话令牌、没有擦除命令。把它们塞进同一个函数靠 `if` 分开，
/// 会让"支持第三种设备"变成在别人的控制流里插分支。
///
/// 每种策略是一个独立实现，选哪个由设备决定，调用方不需要知道区别。
public protocol FirmwareUploadStrategy {
    /// 供日志与错误信息使用的短名。
    var name: String { get }

    func upload(
        image: [UInt8],
        host: FirmwareUploadHost,
        progress: ((Double) -> Void)?
    ) -> Result<FirmwareUploadReceipt, FirmwareUploadFailure>
}

/// 策略需要的最小宿主能力。
///
/// 刻意不把整个 `Client` 交给策略：策略只应该看得到收发和序号，
/// 看不到连接管理、配置读写和控制指令。能看到什么，就会有人去用什么。
public protocol FirmwareUploadHost: AnyObject {
    /// 发一个 VESC 封帧请求并等待首字节匹配的回包。
    func uploadSendVesc(_ payload: [UInt8], expect: Int, retries: Int) -> [UInt8]?
    /// 直接写裸字节（bootloader 原始帧不经过任何封帧层）。
    @discardableResult func uploadWriteRaw(_ bytes: [UInt8]) -> Bool
    /// 直接读裸字节。
    func uploadReadRaw(max: Int) -> [UInt8]
    /// 取下一个 IAP 滚动序号并自增。序号是主机进程内状态，不是设备状态。
    func uploadNextIAPSequence() -> UInt8
    /// 可选的线路诊断，用于区分“设备拒绝”与“没有收到响应”。
    var uploadTrace: ((String, [UInt8]) -> Void)? { get }
}

/// `usleep` 会被信号提前打断，而上传里的等待长度直接影响能否收到 ACK。
func firmwareUploadSleep(_ seconds: TimeInterval) {
    guard seconds > 0 else { return }
    let whole = floor(seconds)
    var requested = timespec(tv_sec: Int(whole),
                             tv_nsec: Int((seconds - whole) * 1_000_000_000))
    var remaining = timespec()
    while nanosleep(&requested, &remaining) == -1 && errno == EINTR {
        requested = remaining
    }
}
