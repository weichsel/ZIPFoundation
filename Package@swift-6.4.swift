// swift-tools-version:6.4

// NOTE: This manifest applies only to Xcodes 27+.

import PackageDescription

let zlibPlatforms: [Platform] = [.linux, .android, .windows]
let unixZlibPlatforms: [Platform] = [.linux, .android]

/// Restrict `pkg-config` probes by SwiftPM to `zlibPlatforms`. This excludes macOS, where it is unnecessary, and
/// generates a warning when compiling for Apple platforms.
#if canImport(Darwin)
let czlib: Target = .systemLibrary(name: "CZLib")
#else
let czlib: Target = .systemLibrary(
    name: "CZLib",
    pkgConfig: "zlib",
    providers: [.brew(["zlib"]), .apt(["zlib"])])
#endif

let package = Package(
    name: "ZIPFoundation",
    platforms: [
        .macOS(.v12), .iOS(.v15), .tvOS(.v15), .watchOS(.v9), .visionOS(.v1)
    ],
    products: [
        .library(name: "ZIPFoundation", targets: ["ZIPFoundation"])
    ],
    targets: [
        .target(
            name: "ZIPFoundation",
            dependencies: [
                .target(name: "CZLib", condition: .when(platforms: zlibPlatforms))
            ],
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ],
            cSettings: [
                .define("_GNU_SOURCE", to: "1", .when(platforms: unixZlibPlatforms))
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedLibrary("z", .when(platforms: unixZlibPlatforms)),
                .linkedLibrary("zlib", .when(platforms: [.windows]))
            ]),
        czlib,
        .testTarget(
            name: "ZIPFoundationTests",
            dependencies: ["ZIPFoundation"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ])
    ]
)
