// swift-tools-version:5.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "F9Grid",
    platforms: [
        .macOS(.v10_13),
        .iOS(.v12),
        .tvOS(.v12),
        .watchOS(.v4)
    ],
    products: [
        .library(
            name: "F9Grid",
            targets: ["F9Grid"]),
    ],
    dependencies: [
        // Test-only dependency (not required for library users)
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.2.2"),
    ],
    targets: [
        .target(
            name: "F9Grid",
            dependencies: []),
        .testTarget(
            name: "F9GridTests",
            dependencies: [
                "F9Grid",
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ]),
    ]
)
