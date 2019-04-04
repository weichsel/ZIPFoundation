// swift-tools-version:5.0
import PackageDescription

#if canImport(Compression)
let targets: [Target] = [
    .target(name: "ZIPFoundation"),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
]
#else
let targets: [Target] = [
    .systemLibrary(name: "CZLib", pkgConfig: "zlib", providers: [.brew(["zlib"]), .apt(["zlib"])]),
    .target(name: "ZIPFoundation", dependencies: ["CZLib"]),
    .testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
]
#endif

let package = Package(
name: "ZIPFoundation",
platforms: [
    .macOS(.v10_11)
],
products: [
    .library(name: "ZIPFoundation", targets: ["ZIPFoundation"])
],
targets: targets
)
