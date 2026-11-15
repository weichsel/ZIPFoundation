// swift-tools-version:5.9

// NOTE: This manifest applies only to Xcodes 15-26.

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
        .macOS(.v10_13), .iOS(.v12), .tvOS(.v12), .watchOS(.v5), .visionOS(.v1)
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
            linkerSettings: [
                .linkedLibrary("z", .when(platforms: unixZlibPlatforms)),
                .linkedLibrary("zlib", .when(platforms: [.windows]))
            ]),
        czlib,
        .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
    ],
    swiftLanguageVersions: [.v4, .v4_2, .v5]
)
