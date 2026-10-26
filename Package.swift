// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FMChat",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "FMChat", targets: ["FMChat"])
    ],
    targets: [
        .executableTarget(name: "FMChat")
    ]
)
