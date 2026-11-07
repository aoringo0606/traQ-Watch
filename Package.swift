// swift-tools-version: 6.2
import PackageDescription

// UIと通信から独立した本文解析の回帰テスト。アプリに外部依存は追加しない。
let package = Package(
    name: "MessageCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MessageCore", targets: ["MessageCore"])],
    targets: [
        .target(name: "MessageCore", path: "traQ Watch Watch App/Core"),
        .testTarget(name: "MessageCoreTests", dependencies: ["MessageCore"], path: "Tests/MessageCoreTests")
    ]
)
