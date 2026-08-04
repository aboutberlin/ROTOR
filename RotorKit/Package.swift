// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RotorKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RotorKit", targets: ["RotorKit"]),
        .executable(name: "kitcheck", targets: ["kitcheck"]),
        .executable(name: "RotorApp", targets: ["RotorApp"]),
    ],
    targets: [
        .target(name: "RotorKit"),
        .executableTarget(name: "kitcheck", dependencies: ["RotorKit"]),
        .executableTarget(
            name: "RotorApp",
            dependencies: ["RotorKit"],
            resources: [
                .copy("mcconf.xml"),
                .copy("mcconf_v3.xml"),
                .copy("appconf.xml")
            ]
        ),
        // XCTest 测试仅在完整 Xcode 下 `swift test` 运行；CLT 环境用 kitcheck 可执行验证。
        .testTarget(name: "RotorKitTests", dependencies: ["RotorKit"]),
    ]
)
