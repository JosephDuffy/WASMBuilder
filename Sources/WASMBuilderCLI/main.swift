import ArgumentParser
import WASMBuilder

@main
struct WASMBuilderCLI: AsyncParsableCommand {
    @Option
    var swiftAppPackage: String

    @Option
    var outputFile: String

    @Option
    var sdk: SwiftSDK = .wasmEmbedded

    @Option
    var target: String?

    mutating func run() async throws {
        let builder = WASMBuilder()
        try await builder.build(swiftAppPackage: swiftAppPackage, outputFile: outputFile, sdk: sdk, target: target)
    }
}

extension SwiftSDK: ExpressibleByArgument {
    public init?(argument: String) {
        switch argument {
        case "wasm":
            self = .wasm
        case "wasm-embedded":
            self = .wasmEmbedded
        default:
            return nil
        }
    }
}
