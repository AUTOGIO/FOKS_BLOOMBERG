// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FOKS_BLOOMBERG",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "FOKSTerminal", targets: ["FOKSTerminalApp"])
    ],
    targets: [
        .target(
            name: "FOKSTerminalCore"
        ),
        .executableTarget(
            name: "FOKSTerminalApp",
            dependencies: ["FOKSTerminalCore"]
        )
    ]
)
