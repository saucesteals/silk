// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Silk",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Silk",
            targets: ["Silk"]
        ),
        .executable(
            name: "silk",
            targets: ["SilkCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        // Core layer - CGEvent wrappers
        .target(
            name: "SilkCore",
            dependencies: [],
            path: "Sources/SilkCore"
        ),
        
        // Humanization layer - Movement algorithms
        .target(
            name: "SilkHumanization",
            dependencies: ["SilkCore"],
            path: "Sources/SilkHumanization"
        ),
        
        // Vision layer - Screen capture & UI inspection
        .target(
            name: "SilkVision",
            dependencies: ["SilkCore", "SilkAccessibility"],
            path: "Sources/SilkVision"
        ),
        
        // Accessibility layer - UI element finding and interaction
        .target(
            name: "SilkAccessibility",
            dependencies: ["SilkCore"],
            path: "Sources/SilkAccessibility"
        ),
        
        // Drag operations layer
        .target(
            name: "SilkDrag",
            dependencies: ["SilkCore", "SilkHumanization"],
            path: "Sources/SilkDrag"
        ),
        
        // Scroll operations layer
        .target(
            name: "SilkScroll",
            dependencies: ["SilkCore", "SilkAccessibility"],
            path: "Sources/SilkScroll"
        ),
        
        // Keyboard operations layer
        .target(
            name: "SilkKeyboard",
            dependencies: ["SilkCore"],
            path: "Sources/SilkKeyboard"
        ),
        
        // App management layer
        .target(
            name: "SilkApp",
            dependencies: [],
            path: "Sources/SilkApp"
        ),
        
        // Window management layer
        .target(
            name: "SilkWindow",
            dependencies: [],
            path: "Sources/SilkWindow"
        ),
        
        // Menu & Dock management layer
        .target(
            name: "SilkMenu",
            dependencies: [],
            path: "Sources/SilkMenu"
        ),
        
        // Clipboard operations layer
        .target(
            name: "SilkClipboard",
            dependencies: [],
            path: "Sources/SilkClipboard"
        ),
        
        // Dialog handling layer
        .target(
            name: "SilkDialog",
            dependencies: [],
            path: "Sources/SilkDialog"
        ),
        
        // High-level API
        .target(
            name: "Silk",
            dependencies: [
                "SilkCore",
                "SilkHumanization",
                "SilkVision",
                "SilkAccessibility",
                "SilkDrag",
                "SilkScroll",
                "SilkKeyboard",
                "SilkApp",
                "SilkWindow",
                "SilkMenu",
                "SilkClipboard",
                "SilkDialog"
            ],
            path: "Sources/Silk"
        ),
        
        // CLI tool
        .executableTarget(
            name: "SilkCLI",
            dependencies: [
                "Silk",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/SilkCLI"
        ),
        
    ]
)
