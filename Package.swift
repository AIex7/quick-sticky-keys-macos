// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "StickyKeys",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "StickyKeys", targets: ["StickyKeys"])
    ],
    targets: [
        .executableTarget(
            name: "StickyKeys",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices")
            ]
        )
    ]
)
