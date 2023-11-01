// swift-tools-version:4.0
import PackageDescription

#if os(macOS) || os(iOS) || os(tvOS) || os(visionOS) || os(watchOS)
let dependencies: [Package.Dependency] = []
#else
let dependencies: [Package.Dependency] = [.package(url: "https://github.com/IBM-Swift/CZlib.git", .exact("0.1.2"))]
#endif

let package = Package(
    name: "ZIPFoundation",
    products: [
        .library(name: "ZIPFoundation", targets: ["ZIPFoundation"])
    ],
	dependencies: dependencies,
    targets: [
        .target(name: "ZIPFoundation"),
		.testTarget(name: "ZIPFoundationTests", dependencies: ["ZIPFoundation"])
    ]
)
