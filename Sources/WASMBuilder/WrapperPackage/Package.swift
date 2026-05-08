// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "swift-server",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .executable(name: "wrapper", targets: ["Wrapper"]),
    ],
    dependencies: [
        // .package(url: "https://github.com/swiftwasm/JavaScriptKit.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "Wrapper",
            // dependencies: ["JavaScriptKit"],
            // swiftSettings: [
            //     .enableExperimentalFeature("Extern"),
            // ],
            // plugins: [
            //     .plugin(name: "BridgeJS", package: "JavaScriptKit"),
            // ],
        ),
    ],
)
