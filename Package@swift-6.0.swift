// swift-tools-version:6.0
import PackageDescription

#if canImport(Compression)
let targets: [Target] = [
    .target(name: "ZIPFoundation",
            resources: [
                .copy("Resources/PrivacyInfo.xcprivacy")
            ]),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"], exclude: ["Resources"])
]
#else
let targets: [Target] = [
    .systemLibrary(name: "CZLib", pkgConfig: "zlib", providers: [.brew(["zlib"]), .apt(["zlib"])]),
    .target(name: "ZIPFoundation", dependencies: ["CZLib"], cSettings: [.define("_GNU_SOURCE", to: "1")]),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
]
#endif

let package = Package(
    name: "ZIPFoundation",
    products: [
        .library(name: "ZIPFoundation", targets: ["ZIPFoundation"])
    ],
    targets: targets,
    swiftLanguageModes: [.v5, .v6]
)
