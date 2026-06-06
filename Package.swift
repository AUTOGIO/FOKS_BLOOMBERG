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
    dependencies: [
        .package(path: "/Users/giovannini_nuovo/Developer/PersonalOSKit")
    ],
    targets: [
        .target(
            name: "FOKSTerminalCore",
            dependencies: [
                .product(name: "ShellRunner", package: "PersonalOSKit"),
                .product(name: "OllamaClient", package: "PersonalOSKit"),
            ]
        ),
        .executableTarget(
            name: "FOKSTerminalApp",
            dependencies: ["FOKSTerminalCore"]
        ),
        .testTarget(
            name: "FOKSTerminalCoreTests",
            dependencies: [
                "FOKSTerminalCore",
                .product(name: "ShellRunner", package: "PersonalOSKit"),
            ]
        )
    ]
)
