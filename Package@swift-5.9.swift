// swift-tools-version:5.9
import PackageDescription

#if canImport(Compression)
let targets: [Target] = [
    .target(name: "ZIPFoundation",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
]
#else
let targets: [Target] = [
    .systemLibrary(
        name: "CZLib",
        pkgConfig: "zlib",
        providers: [.brew(["zlib"]), .apt(["zlib"])]),
    .target(
        name: "ZIPFoundation",
        dependencies: ["CZLib"],
        cSettings: [.define("_GNU_SOURCE", to: "1")],
        // Per-platform link library. Windows vcpkg installs `zlib.lib`
        // so we link `zlib`; Linux / Android ship `libz.so` aka `-lz`.
        // Apple takes the canImport(Compression) branch above and
        // doesn't reach here.
        linkerSettings: [
            .linkedLibrary("z", .when(platforms: [.linux, .android])),
            .linkedLibrary("zlib", .when(platforms: [.windows]))
        ]),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
]
#endif

let package = Package(
    name: "ZIPFoundation",
    platforms: [
        .macOS(.v10_13), .iOS(.v12), .tvOS(.v12), .watchOS(.v4), .visionOS(.v1)
    ],
    products: [
        .library(name: "ZIPFoundation", targets: ["ZIPFoundation"])
    ],
    targets: targets,
    swiftLanguageVersions: [.v4, .v4_2, .v5]
)
