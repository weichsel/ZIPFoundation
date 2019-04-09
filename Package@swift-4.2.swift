// swift-tools-version:4.2
import PackageDescription

#if canImport(Compression)
let targets: [Target] = [
    .target(name: "ZIPFoundation"),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
]
let dependencies: [Package.Dependency] = []
#else
let targets: [Target] = [
    .systemLibrary(name: "CZLib", pkgConfig: "zlib", providers: [.brew(["zlib"]), .apt(["zlib"])]),
    .target(name: "ZIPFoundation", dependencies: ["CZLib"]),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
]
let dependencies: [Package.Dependency] = ["CZLib"]
#endif

let package = Package(
    name: "ZIPFoundation",
    products: [
        .library(name: "ZIPFoundation", targets: ["ZIPFoundation"])
    ],
    dependencies: dependencies,    
    targets: targets,
    swiftLanguageVersions: [.v4, .v4_2]
)
