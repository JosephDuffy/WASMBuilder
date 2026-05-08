public enum SwiftSDK: Sendable {
    case wasm
    case wasmEmbedded
}

extension SwiftSDK {
    var identifier: String {
        switch self {
        case .wasm:
            "swift-6.3.1-RELEASE_wasm"
        case .wasmEmbedded:
            "swift-6.3.1-RELEASE_wasm-embedded"
        }
    }
}
