import Foundation
import Subprocess
import System

public struct WASMBuilder {
    public init() {}

    public func build(sourceFile: String, outputFile: String) async throws {
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: sourceFile)
        let outputURL = URL(fileURLWithPath: outputFile)
        let templateURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("WrapperPackage")
        let temporaryPackageURL = fileManager.temporaryDirectory
            .appendingPathComponent("WASMBuilder-\(UUID().uuidString)", isDirectory: true)

        try fileManager.copyItem(at: templateURL, to: temporaryPackageURL)
        defer {
            try? fileManager.removeItem(at: temporaryPackageURL)
        }

        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let wrapperMainURL = temporaryPackageURL
            .appendingPathComponent("Sources")
            .appendingPathComponent("Wrapper")
            .appendingPathComponent("main.swift")
        let wrapperMain = try String(contentsOf: wrapperMainURL, encoding: .utf8)
        let wrappedSource = wrapperMain.replacingOccurrences(
            of: "        // REPLACE_ME",
            with: source.indented(by: 8)
        )

        guard wrappedSource != wrapperMain else {
            throw WASMBuilderError.missingReplacementMarker(wrapperMainURL.path)
        }

        try wrappedSource.write(to: wrapperMainURL, atomically: true, encoding: .utf8)

        let result = try await run(
            .name("swift"),
            arguments: [
                "build",
                "--swift-sdk",
                "swift-6.3.1-RELEASE_wasm-embedded",
                "--configuration",
                "release",
            ],
            // arguments: [
            //     "package",
            //     "--swift-sdk",
            //     "swift-6.3.1-RELEASE_wasm-embedded",
            //     "--configuration",
            //     "release",
            //     "js",
            // ],
            workingDirectory: FilePath(temporaryPackageURL.path),
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard result.terminationStatus.isSuccess else {
            throw WASMBuilderError.buildFailed(
                status: result.terminationStatus.description,
                standardOutput: result.standardOutput ?? "",
                standardError: result.standardError ?? ""
            )
        }

        let builtWASMURL = try findBuiltWASM(in: temporaryPackageURL)
        let outputDirectoryURL = outputURL.deletingLastPathComponent()

        if !fileManager.fileExists(atPath: outputDirectoryURL.path) {
            try fileManager.createDirectory(
                at: outputDirectoryURL,
                withIntermediateDirectories: true
            )
        }

        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }

        try fileManager.copyItem(at: builtWASMURL, to: outputURL)
    }

    private func findBuiltWASM(in packageURL: URL) throws -> URL {
        let buildURL = packageURL.appendingPathComponent(".build", isDirectory: true)
        let wasmFiles = FileManager.default
            .enumerator(at: buildURL, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "wasm" } ?? []

        if let wrapperWASM = wasmFiles.first(where: { $0.lastPathComponent == "wrapper.wasm" }) {
            return wrapperWASM
        }

        guard let wasmFile = wasmFiles.first else {
            throw WASMBuilderError.missingBuildArtifact(buildURL.path)
        }

        return wasmFile
    }
}

private enum WASMBuilderError: Error, CustomStringConvertible {
    case missingReplacementMarker(String)
    case buildFailed(status: String, standardOutput: String, standardError: String)
    case missingBuildArtifact(String)

    var description: String {
        switch self {
        case .missingReplacementMarker(let path):
            return "Wrapper main.swift is missing the // REPLACE_ME marker: \(path)"
        case .buildFailed(let status, let standardOutput, let standardError):
            return """
                Swift WASM build failed with status \(status).
                Standard output:
                \(standardOutput)
                Standard error:
                \(standardError)
                """
        case .missingBuildArtifact(let path):
            return "Swift WASM build completed, but no .wasm artifact was found under \(path)."
        }
    }
}

private extension String {
    func indented(by spaces: Int) -> String {
        let indentation = String(repeating: " ", count: spaces)
        return split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                line.isEmpty ? "" : indentation + line
            }
            .joined(separator: "\n")
    }
}
