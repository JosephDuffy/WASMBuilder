import Foundation
import Testing
@testable import WASMBuilder

@Suite("WASMBuilder")
struct WASMBuilderTests {
    private let embeddedSDKIdentifier = "swift-6.3.1-RELEASE_wasm-embedded"

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

    @Test func resolvesEmbeddedUnicodeDataTablesLibraryFromSwiftSDKArtifact() throws {
        let fixture = try makeSwiftSDKFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.swiftSDKsDirectory)
        }

        let resolvedURL = try SwiftSDKArtifactResolver(
            swiftSDKsDirectory: fixture.swiftSDKsDirectory
        )
        .unicodeDataTablesLibrary(for: .wasmEmbedded)

        #expect(resolvedURL.resolvingSymlinksInPath() == fixture.unicodeDataTablesURL.resolvingSymlinksInPath())
    }

    @Test func buildArgumentsIncludeUnicodeDataTablesLinkerFlagsWhenEnabled() throws {
        let fixture = try makeSwiftSDKFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.swiftSDKsDirectory)
        }

        let arguments = try swiftBuildArguments(
            sdk: .wasmEmbedded,
            linkEmbeddedUnicodeDataTables: true,
            swiftSDKsDirectory: fixture.swiftSDKsDirectory
        )

        #expect(arguments.count == 11)
        #expect(Array(arguments.prefix(8)) == [
            "build",
            "--swift-sdk",
            embeddedSDKIdentifier,
            "--configuration",
            "release",
            "-Xlinker",
            "--whole-archive",
            "-Xlinker",
        ])
        #expect(arguments[8].hasSuffix(
            "/swift.xctoolchain/usr/lib/swift/embedded/wasm32-unknown-wasip1/libswiftUnicodeDataTables.a"
        ))
        #expect(Array(arguments.suffix(2)) == [
            "-Xlinker",
            "--no-whole-archive",
        ])
    }

    @Test func linkingUnicodeDataTablesRequiresEmbeddedSDK() throws {
        let fixture = try makeSwiftSDKFixture()
        defer {
            try? FileManager.default.removeItem(at: fixture.swiftSDKsDirectory)
        }

        do {
            _ = try swiftBuildArguments(
                sdk: .wasm,
                linkEmbeddedUnicodeDataTables: true,
                swiftSDKsDirectory: fixture.swiftSDKsDirectory
            )
            Issue.record("Expected linking Unicode tables with the non-embedded WASM SDK to throw.")
        } catch {
            #expect(String(describing: error).contains("wasm-embedded"))
        }
    }

    private func makeSwiftSDKFixture() throws -> SwiftSDKFixture {
        let fileManager = FileManager.default
        let swiftSDKsDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("WASMBuilderTests-\(UUID().uuidString)")
        let artifactBundleURL = swiftSDKsDirectory
            .appendingPathComponent("swift-6.3.1-RELEASE_wasm.artifactbundle")
        let sdkDirectoryURL = artifactBundleURL
            .appendingPathComponent("swift-6.3.1-RELEASE_wasm")
            .appendingPathComponent("wasm32-unknown-wasip1")
        let swiftResourcesURL = sdkDirectoryURL
            .appendingPathComponent("swift.xctoolchain")
            .appendingPathComponent("usr")
            .appendingPathComponent("lib")
            .appendingPathComponent("swift")
        let unicodeDataTablesURL = swiftResourcesURL
            .appendingPathComponent("embedded")
            .appendingPathComponent("wasm32-unknown-wasip1")
            .appendingPathComponent("libswiftUnicodeDataTables.a")

        try fileManager.createDirectory(
            at: unicodeDataTablesURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data().write(to: unicodeDataTablesURL)

        let infoJSON = """
        {
          "schemaVersion": "1.0",
          "artifacts": {
            "\(embeddedSDKIdentifier)": {
              "type": "swiftSDK",
              "version": "0.0.1",
              "variants": [
                {
                  "path": "swift-6.3.1-RELEASE_wasm/wasm32-unknown-wasip1/embedded-swift-sdk.json"
                }
              ]
            }
          }
        }
        """
        try infoJSON.write(
            to: artifactBundleURL.appendingPathComponent("info.json"),
            atomically: true,
            encoding: .utf8
        )

        let sdkJSON = """
        {
          "schemaVersion": "4.0",
          "targetTriples": {
            "wasm32-unknown-wasip1": {
              "sdkRootPath": "WASI.sdk",
              "swiftResourcesPath": "swift.xctoolchain/usr/lib/swift",
              "swiftStaticResourcesPath": "swift.xctoolchain/usr/lib/swift_static"
            }
          }
        }
        """
        try sdkJSON.write(
            to: sdkDirectoryURL.appendingPathComponent("embedded-swift-sdk.json"),
            atomically: true,
            encoding: .utf8
        )

        return SwiftSDKFixture(
            swiftSDKsDirectory: swiftSDKsDirectory,
            unicodeDataTablesURL: unicodeDataTablesURL
        )
    }
}

private struct SwiftSDKFixture {
    var swiftSDKsDirectory: URL
    var unicodeDataTablesURL: URL
}
