import Foundation
import Testing
import WASMBuilder

@Suite("WASMBuilder")
struct WASMBuilderTests {
    @Test func buildsSingleSourceFileIntoWASM() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WASMBuilderTests-\(UUID().uuidString)")
            .appendingPathComponent("TestFile.wasm")
        defer {
            try? FileManager.default.removeItem(at: outputURL.deletingLastPathComponent())
        }

        let builder = WASMBuilder()

        try await builder.build(
            sourceFile: "TestFile.swift",
            outputFile: outputURL.path
        )

        #expect(FileManager.default.fileExists(atPath: outputURL.path))
        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let fileSize = try #require(attributes[.size] as? UInt64)
        #expect(fileSize > 0)
    }
}
