// swift-tools-version:5.9
import PackageDescription

let zlibPlatforms: [Platform] = [.linux, .android, .windows]
let unixZlibPlatforms: [Platform] = [.linux, .android]

let package = Package(
    name: "ZIPFoundation",
    platforms: [
        .macOS(.v10_13), .iOS(.v12), .tvOS(.v12), .watchOS(.v4), .visionOS(.v1)
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
        .systemLibrary(
            name: "CZLib",
            pkgConfig: "zlib",
            providers: [.brew(["zlib"]), .apt(["zlib"])]),
        .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
    ],
    swiftLanguageVersions: [.v4, .v4_2, .v5]
)
