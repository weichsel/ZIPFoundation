// swift-tools-version:5.0
import PackageDescription

#if canImport(Compression)
let dependencies: [Package.Dependency] = []
#else
let dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/IBM-Swift/CZlib.git", .exact("0.1.2"))
]
#endif

let package = Package(
    name: "ZIPFoundation",
    platforms: [
        .macOS(.v10_11)
    ],
    products: [
        .library(
            name: "ZIPFoundation",
            targets: ["ZIPFoundation"]
        )
    ],
	dependencies: dependencies,
    targets: [
        .target(
            name: "ZIPFoundation"
        ),
		.testTarget(
            name: "ZIPFoundationTests",
            dependencies: ["ZIPFoundation"]
        )
    ]
)
