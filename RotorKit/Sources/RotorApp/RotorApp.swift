import SwiftUI
import RotorKit

@main
struct RotorApp: App {
    init() {
        SelfTest.runIfRequested()          // 只连模拟器，不占串口，不需要加锁
        SingleInstance.acquireOrExit()     // 两个实例会互相抢串口
        Acceptance.runIfRequested()
    }

    @StateObject private var model = AppModel()
    @StateObject private var l10n = L10nStore()

    var body: some Scene {
        WindowGroup("Rotor · Mac") {
            RootView()
                // 五个子模型分别注入：macOS 13 的 ObservableObject 不会把嵌套对象的
                // 变更向外传播，视图必须直接观察自己用到的那个。顺带的好处是遥测
                // 每秒刷新几次也不会带着参数页一起重绘。
                .environmentObject(model)
                .environmentObject(model.connection)
                .environmentObject(model.telemetry)
                .environmentObject(model.config)
                .environmentObject(model.detection)
                .environmentObject(model.firmware)
                .environmentObject(model.control)
                .environmentObject(l10n)
                .frame(minWidth: 940, minHeight: 640)
                // 语言变更时整棵树重建。见 L10nStore 的说明。
                .id(l10n.language)
        }
        .windowResizability(.contentMinSize)
    }
}

struct RootView: View {
    @EnvironmentObject var connection: ConnectionModel
    var body: some View {
        VStack(spacing: 0) {
            ConnectionBar()
            Divider()
            TabView {
                DashboardView()
                    .tabItem { Label(L10n.t(L10n.Tab.realtime),
                                     systemImage: "gauge.with.dots.needle.67percent") }
                ConfigView()
                    .tabItem { Label(L10n.t(L10n.Tab.parameters),
                                     systemImage: "slider.horizontal.3") }
                DeviceView()
                    .tabItem { Label(L10n.t(L10n.Tab.device), systemImage: "cpu") }
                FirmwareView()
                    .tabItem { Label(L10n.t(L10n.Tab.firmware), systemImage: "square.and.arrow.down.on.square") }
            }
            .padding(14)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // 首次打开自动连模拟器，立即有数据/曲线可看（无需硬件）。
            if !connection.connected && connection.simMode { connection.connect() }
        }
    }
}
