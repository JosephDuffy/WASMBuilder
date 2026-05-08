// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "WASMBuilder",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "wasm-builder", targets: ["WASMBuilderCLI"]),
        .executable(name: "server", targets: ["Server"]),
        .library(name: "App", targets: ["App"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
        .package(
            url: "https://github.com/swiftlang/swift-subprocess.git",
            .upToNextMinor(from: "0.4.0")
        ),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.118.0"),
    ],
    targets: [
        .executableTarget(
            name: "Server",
            dependencies: [
                .target(name: "App"),
            ],
        ),
        .executableTarget(
            name: "WASMBuilderCLI",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .target(name: "WASMBuilder"),
            ],
        ),
        .target(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "WASMBuilder",
            ],
        ),
        .target(
            name: "WASMBuilder",
            dependencies: [
                .product(
                    name: "Subprocess",
                    package: "swift-subprocess",
                ),
            ],
            exclude: ["WrapperPackage"],
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                .target(name: "App"),
                .product(name: "VaporTesting", package: "vapor"),
            ],
        ),
        .testTarget(
            name: "WASMBuilderTests",
            dependencies: [
                .target(name: "WASMBuilder"),
            ],
        ),
    ],
)
