// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Murmur",
    platforms: [
        // 13 is WhisperKit's minimum; the GUI app will set its own (likely 15) when added.
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "MurmurPlatform",
            targets: ["MurmurPlatform"]
        ),
        .library(
            name: "MurmurDesign",
            targets: ["MurmurDesign"]
        ),
        .library(
            name: "MurmurKit",
            targets: ["MurmurKit"]
        ),
        .executable(
            name: "murmur-bench",
            targets: ["MurmurBench"]
        ),
        .executable(
            name: "murmur-polish-bench",
            targets: ["MurmurPolishBench"]
        ),
        .executable(
            name: "murmur-bias-bench",
            targets: ["MurmurBiasBench"]
        ),
        .executable(
            name: "murmur-stream-bench",
            targets: ["MurmurStreamBench"]
        ),
        .executable(
            name: "murmur-cli",
            targets: ["MurmurCLI"]
        ),
        .executable(
            name: "murmur",
            targets: ["MurmurApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "0.18.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.4.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.4.0"),
        // SPEC-026 — Sparkle 2.x for in-app updates on the DMG path.
        // Kept off MurmurKit (kit stays Sparkle-free); linked only into
        // MurmurApp. `from: "2.6.0"` floats up through 2.x; do not pin a
        // branch.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
        // SPEC-007 — in-process llama.cpp polish engine. Thin binding: a
        // binaryTarget over the official llama.cpp xcframework, tracked daily.
        // We write the inference loop ourselves (see LlamaCppPolishEngine).
        .package(url: "https://github.com/mattt/llama.swift", .upToNextMajor(from: "2.9488.0")),
    ],
    targets: [
        .target(
            name: "MurmurPlatform",
            dependencies: [],
            path: "Sources/MurmurPlatform"
        ),
        // Stripe-field geometry, palette, and dither math shared by the app's
        // menu-bar glyph, overlay, and brand mark. Foundation only.
        .target(
            name: "MurmurDesign",
            dependencies: [],
            path: "Sources/MurmurDesign"
        ),
        // Tiny Objective-C shim: lets Swift catch the NSExceptions that
        // AVAudioEngine.installTap raises on format mismatches (otherwise an
        // uncatchable SIGABRT). See MurmurObjCSupport.h.
        .target(
            name: "MurmurObjCSupport",
            path: "Sources/MurmurObjCSupport"
        ),
        .target(
            name: "MurmurStreaming",
            dependencies: [
                "MurmurPlatform",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources/MurmurStreaming"
        ),
        .target(
            name: "MurmurKit",
            dependencies: [
                "MurmurPlatform",
                "MurmurStreaming",
                "MurmurObjCSupport",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "LlamaSwift", package: "llama.swift"),
            ],
            path: "Sources/MurmurKit"
        ),
        .executableTarget(
            name: "MurmurBench",
            dependencies: [
                "MurmurKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MurmurBench"
        ),
        .executableTarget(
            name: "MurmurPolishBench",
            dependencies: [
                "MurmurPlatform",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MurmurPolishBench"
        ),
        .executableTarget(
            name: "MurmurBiasBench",
            dependencies: [
                "MurmurPlatform",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MurmurBiasBench"
        ),
        .executableTarget(
            name: "MurmurStreamBench",
            dependencies: [
                "MurmurPlatform",
                "MurmurStreaming",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MurmurStreamBench"
        ),
        .executableTarget(
            name: "MurmurCLI",
            dependencies: [
                "MurmurKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MurmurCLI"
        ),
        .executableTarget(
            name: "MurmurApp",
            dependencies: [
                "MurmurKit",
                "MurmurDesign",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MurmurApp"
        ),
        .testTarget(
            name: "MurmurKitTests",
            dependencies: ["MurmurKit"],
            path: "Tests/MurmurKitTests"
        ),
        .testTarget(
            name: "MurmurDesignTests",
            dependencies: ["MurmurDesign"],
            path: "Tests/MurmurDesignTests"
        ),
    ]
)
