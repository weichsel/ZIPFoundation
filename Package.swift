// swift-tools-version:3.0

import PackageDescription

let package = Package(
    name: "ZIPFoundation",
    targets: [
        Target(
            name: "ZIPFoundation"
        )
    ]
)

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
#elseif os(Linux)
let dependency: Package.Dependency = .Package(url: "https://github.com/IBM-Swift/CZlib.git", majorVersion: 0)
package.dependencies.append(dependency)
#endif
