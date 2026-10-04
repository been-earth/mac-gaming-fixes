// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MacGamingFixes",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything that touches the system: CrossOver patching, function keys, audio devices.
        .target(name: "MGFCore"),
        .executableTarget(
            name: "MGF",
            dependencies: ["MGFCore"],
            resources: [
                .process("Resources/en.lproj"), .process("Resources/ru.lproj"),
                .copy("Resources/Icons"), .copy("Resources/Fonts"), .copy("Resources/Brand"), .copy("Resources/Payload"),
            ]
        ),
        .testTarget(name: "MGFCoreTests", dependencies: ["MGFCore"]),
    ]
)
