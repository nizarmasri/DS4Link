// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "DS4Link",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: controller matching, phase derivation, error text, logging. Unit-testable.
        .target(
            name: "DS4LinkCore",
            path: "Sources/DS4LinkCore"
        ),
        // The app: IOBluetooth driver, GameController monitor, SwiftUI window, --cli test mode.
        .executableTarget(
            name: "DS4Link",
            dependencies: ["DS4LinkCore"],
            path: "Sources/DS4Link",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("GameController"),
            ]
        ),
        .testTarget(
            name: "DS4LinkCoreTests",
            dependencies: ["DS4LinkCore"],
            path: "Tests/DS4LinkCoreTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
