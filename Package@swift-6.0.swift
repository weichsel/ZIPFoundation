// swift-tools-version:6.0
import PackageDescription

let zlibPlatforms: [Platform] = [.linux, .android, .windows]
let unixZlibPlatforms: [Platform] = [.linux, .android]

let package = Package(
    name: "ZIPFoundation",
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
        .systemLibrary(
            name: "CZLib",
            pkgConfig: "zlib",
            providers: [.brew(["zlib"]), .apt(["zlib"])]),
        .testTarget(
            name: "ZIPFoundationTests",
            dependencies: ["ZIPFoundation"],
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
