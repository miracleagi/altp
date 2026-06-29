// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Altp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Altp", targets: ["Altp"])
    ],
    targets: [
        .executableTarget(
            name: "Altp",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon")
            ]
        )
    ]
)
