// swift-tools-version:6.4

// SwiftPM manifest for Swift 6.4 and later.

import PackageDescription

let zlibPlatforms: [Platform] = [.linux, .android, .windows]
let unixZlibPlatforms: [Platform] = [.linux, .android]

/// Restrict `pkg-config` probes by SwiftPM to `zlibPlatforms`. This excludes macOS, where it is unnecessary, and
/// generates a warning when compiling for Apple platforms.
///
/// The privacy manifest is only needed on Apple platforms. SwiftPM doesn't support platform conditions for
/// resources, so the manifest is only copied when the package is built on Darwin.
#if canImport(Darwin)
let czlib: Target = .systemLibrary(name: "CZLib")
let resources: [Resource] = [.copy("Resources/PrivacyInfo.xcprivacy")]
#else
let czlib: Target = .systemLibrary(
    name: "CZLib",
    pkgConfig: "zlib",
    providers: [.brew(["zlib"]), .apt(["zlib1g-dev"])])
let resources: [Resource] = []
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
            resources: resources,
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
