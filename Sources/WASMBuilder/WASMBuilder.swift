import Foundation
import Subprocess
import System

public struct WASMBuilder {
    public init() {}

    public func build(
        swiftAppPackage: String,
        outputFile: String,
        sdk: SwiftSDK = .wasmEmbedded,
        target: String? = nil,
        linkEmbeddedUnicodeDataTables: Bool = false
    ) async throws {
        let fileManager = FileManager.default
        let packageURL = URL(fileURLWithPath: swiftAppPackage)
        let outputURL = URL(fileURLWithPath: outputFile)
        let temporaryPackageURL = fileManager.temporaryDirectory
            .appendingPathComponent("WASMBuilder-\(UUID().uuidString)", isDirectory: true)

        try fileManager.copyItem(at: packageURL, to: temporaryPackageURL)
        defer {
            try? fileManager.removeItem(at: temporaryPackageURL)
        }

        let package = try await describePackage(at: temporaryPackageURL)
        let resolvedTarget = try package.executableTarget(named: target)
        let targetSourceURL = try resolvedTarget.sourceURL(relativeTo: temporaryPackageURL)
        let entryPoint = try findEntryPoint(in: targetSourceURL)
        var entryPointSource = try String(contentsOf: entryPoint.sourceURL, encoding: .utf8)

        if !entryPointSource.contains("@_expose(wasm, \"main\")") {
            entryPointSource.append(wasmEntryPointShim(entryPointType: entryPoint.typeName))
            try entryPointSource.write(to: entryPoint.sourceURL, atomically: true, encoding: .utf8)
        }

        try await addWrapperProduct(to: temporaryPackageURL, target: resolvedTarget.name)
        try PackageManifestParser.removeAppleProductTypesIfPresent(in: temporaryPackageURL)
        try await buildPackage(
            at: temporaryPackageURL,
            outputURL: outputURL,
            sdk: sdk,
            linkEmbeddedUnicodeDataTables: linkEmbeddedUnicodeDataTables
        )
    }

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

        try await buildPackage(
            at: temporaryPackageURL,
            outputURL: outputURL,
            sdk: .wasmEmbedded,
            linkEmbeddedUnicodeDataTables: false
        )
    }

    private func buildPackage(
        at packageURL: URL,
        outputURL: URL,
        sdk: SwiftSDK,
        linkEmbeddedUnicodeDataTables: Bool
    ) async throws {
        let fileManager = FileManager.default
        let buildArguments = try swiftBuildArguments(
            sdk: sdk,
            linkEmbeddedUnicodeDataTables: linkEmbeddedUnicodeDataTables
        )
        let result = try await run(
            .name("swift"),
            arguments: Arguments(buildArguments),
            // arguments: [
            //     "package",
            //     "--swift-sdk",
            //     "swift-6.3.1-RELEASE_wasm-embedded",
            //     "--configuration",
            //     "release",
            //     "js",
            // ],
            workingDirectory: FilePath(packageURL.path),
            output: .standardOutput,
            error: .standardError,
        )

        guard result.terminationStatus.isSuccess else {
            throw WASMBuilderError.buildFailed(
                status: result.terminationStatus.description,
                standardOutput: "",
                standardError: "",
            )
        }

        let builtWASMURL = try findBuiltWASM(in: packageURL)
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

        if let wrapperWASM = wasmFiles.first(where: { $0.lastPathComponent == "SwiftWASMWrapper.wasm" }) {
            return wrapperWASM
        }

        if let wrapperWASM = wasmFiles.first(where: { $0.lastPathComponent == "wrapper.wasm" }) {
            return wrapperWASM
        }

        guard let wasmFile = wasmFiles.first else {
            throw WASMBuilderError.missingBuildArtifact(buildURL.path)
        }

        return wasmFile
    }
}

func swiftBuildArguments(
    sdk: SwiftSDK,
    linkEmbeddedUnicodeDataTables: Bool,
    swiftSDKsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library")
        .appendingPathComponent("org.swift.swiftpm")
        .appendingPathComponent("swift-sdks")
) throws -> [String] {
    var arguments = [
        "build",
        "--swift-sdk",
        sdk.identifier,
        "--configuration",
        "release",
    ]

    if linkEmbeddedUnicodeDataTables {
        let unicodeDataTablesURL = try SwiftSDKArtifactResolver(
            swiftSDKsDirectory: swiftSDKsDirectory
        )
        .unicodeDataTablesLibrary(for: sdk)

        arguments += [
            "-Xlinker",
            "--whole-archive",
            "-Xlinker",
            unicodeDataTablesURL.path,
            "-Xlinker",
            "--no-whole-archive",
        ]
    }

    return arguments
}

private func wasmEntryPointShim(entryPointType: String) -> String {
    """

#if os(WASI)
@_expose(wasm, "main")
@_cdecl("main")
#if !hasFeature(Embedded)
@MainActor
#endif
public func main() {
    \(entryPointType).main()
}

@_expose(wasm, "_initialize")
@_cdecl("_initialize")
public func _initialize() {
    // No-op, but required to ensure the module is properly initialized when called from JavaScript.
}
#endif
"""
}

private enum WASMBuilderError: Error, CustomStringConvertible {
    case missingReplacementMarker(String)
    case buildFailed(status: String, standardOutput: String, standardError: String)
    case missingBuildArtifact(String)
    case packageDescriptionFailed(status: String, standardOutput: String, standardError: String)
    case missingExecutableTarget
    case multipleExecutableTargets([String])
    case unknownTarget(String)
    case missingTargetPath(String)
    case missingEntryPoint(String)
    case missingEntryPointType(String)
    case addProductFailed(status: String, standardOutput: String, standardError: String)
    case unsupportedUnicodeDataTablesSDK(SwiftSDK)
    case missingSwiftSDK(String)
    case missingUnicodeDataTablesLibrary(sdk: String, path: String)

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
        case .packageDescriptionFailed(let status, let standardOutput, let standardError):
            return """
                Swift package description failed with status \(status).
                Standard output:
                \(standardOutput)
                Standard error:
                \(standardError)
                """
        case .missingExecutableTarget:
            return "No executable target was found in the Swift app package."
        case .multipleExecutableTargets(let targets):
            return "Multiple executable targets were found in the Swift app package. Pass one of: \(targets.joined(separator: ", "))."
        case .unknownTarget(let target):
            return "No executable target named \(target) was found in the Swift app package."
        case .missingTargetPath(let target):
            return "Executable target \(target) is missing a path."
        case .missingEntryPoint(let path):
            return "No Swift source file containing @main was found under \(path)."
        case .missingEntryPointType(let path):
            return "The @main type declaration could not be found in \(path)."
        case .addProductFailed(let status, let standardOutput, let standardError):
            return """
                Adding SwiftWASMWrapper product failed with status \(status).
                Standard output:
                \(standardOutput)
                Standard error:
                \(standardError)
                """
        case .unsupportedUnicodeDataTablesSDK(let sdk):
            return "Embedded Unicode data tables can only be linked with the wasm-embedded SDK, not \(sdk.identifier)."
        case .missingSwiftSDK(let sdk):
            return "The Swift SDK \(sdk) was not found in the installed Swift SDK artifact bundles."
        case .missingUnicodeDataTablesLibrary(let sdk, let path):
            return "The Swift SDK \(sdk) is missing libswiftUnicodeDataTables.a at \(path)."
        }
    }
}

struct SwiftSDKArtifactResolver {
    var swiftSDKsDirectory: URL

    func unicodeDataTablesLibrary(for sdk: SwiftSDK) throws -> URL {
        guard sdk == .wasmEmbedded else {
            throw WASMBuilderError.unsupportedUnicodeDataTablesSDK(sdk)
        }

        let fileManager = FileManager.default
        let artifactBundleURLs = (try? fileManager.contentsOfDirectory(
            at: swiftSDKsDirectory,
            includingPropertiesForKeys: nil
        ))?
            .filter { $0.pathExtension == "artifactbundle" } ?? []

        for artifactBundleURL in artifactBundleURLs {
            let infoURL = artifactBundleURL.appendingPathComponent("info.json")
            guard fileManager.fileExists(atPath: infoURL.path) else {
                continue
            }

            let infoData = try Data(contentsOf: infoURL)
            let info = try JSONDecoder().decode(SwiftSDKArtifactBundleInfo.self, from: infoData)
            guard let artifact = info.artifacts[sdk.identifier],
                let variant = artifact.variants.first
            else {
                continue
            }

            let sdkJSONURL = artifactBundleURL.appendingPathComponent(variant.path)
            let sdkData = try Data(contentsOf: sdkJSONURL)
            let metadata = try JSONDecoder().decode(SwiftSDKMetadata.self, from: sdkData)

            guard let targetTriple = metadata.targetTriples.keys.sorted().first,
                let target = metadata.targetTriples[targetTriple]
            else {
                continue
            }

            let sdkRootURL = sdkJSONURL
                .deletingLastPathComponent()
                .appendingPathComponent(target.swiftResourcesPath)
            let unicodeDataTablesURL = sdkRootURL
                .appendingPathComponent("embedded")
                .appendingPathComponent(targetTriple)
                .appendingPathComponent("libswiftUnicodeDataTables.a")

            guard fileManager.fileExists(atPath: unicodeDataTablesURL.path) else {
                throw WASMBuilderError.missingUnicodeDataTablesLibrary(
                    sdk: sdk.identifier,
                    path: unicodeDataTablesURL.path
                )
            }

            return unicodeDataTablesURL
        }

        throw WASMBuilderError.missingSwiftSDK(sdk.identifier)
    }
}

private struct SwiftSDKArtifactBundleInfo: Decodable {
    var artifacts: [String: SwiftSDKArtifact]
}

private struct SwiftSDKArtifact: Decodable {
    var variants: [SwiftSDKVariant]
}

private struct SwiftSDKVariant: Decodable {
    var path: String
}

private struct SwiftSDKMetadata: Decodable {
    var targetTriples: [String: SwiftSDKTarget]
}

private struct SwiftSDKTarget: Decodable {
    var swiftResourcesPath: String
}

private struct PackageDescription: Decodable {
    var targets: [TargetDescription]

    func executableTarget(named requestedTarget: String?) throws -> TargetDescription {
        let executableTargets = targets.filter(\.isExecutable)

        if let requestedTarget {
            guard let target = executableTargets.first(where: { $0.name == requestedTarget }) else {
                throw WASMBuilderError.unknownTarget(requestedTarget)
            }

            return target
        }

        guard let target = executableTargets.first else {
            throw WASMBuilderError.missingExecutableTarget
        }

        guard executableTargets.count == 1 else {
            throw WASMBuilderError.multipleExecutableTargets(executableTargets.map(\.name))
        }

        return target
    }
}

private struct TargetDescription: Decodable {
    var name: String
    var type: PackageDescriptionType?
    var path: String?

    var isExecutable: Bool {
        type?.isExecutable == true
    }

    func sourceURL(relativeTo packageURL: URL) throws -> URL {
        guard let path else {
            throw WASMBuilderError.missingTargetPath(name)
        }

        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }

        return packageURL.appendingPathComponent(path, isDirectory: true)
    }
}

private enum PackageDescriptionType: Decodable {
    case string(String)
    case dictionary([String: String?])

    var isExecutable: Bool {
        switch self {
        case .string(let value):
            return value == "executable"
        case .dictionary(let value):
            return value.keys.contains("executable")
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            self = .dictionary(try container.decode([String: String?].self))
        }
    }
}

private func describePackage(at packageURL: URL) async throws -> PackageDescription {
    let result = try await run(
        .name("swift"),
        arguments: [
            "package",
            "describe",
            "--type",
            "json",
        ],
        workingDirectory: FilePath(packageURL.path),
        output: .string(limit: 65_536),
        error: .string(limit: 65_536)
    )

    if result.terminationStatus.isSuccess, let standardOutput = result.standardOutput {
        let data = Data(standardOutput.utf8)
        return try JSONDecoder().decode(PackageDescription.self, from: data)
    }

    return try PackageManifestParser.parse(packageURL: packageURL)
}

private struct EntryPoint {
    var sourceURL: URL
    var typeName: String
}

private func findEntryPoint(in targetSourceURL: URL) throws -> EntryPoint {
    let fileManager = FileManager.default
    let sourceURLs = fileManager
        .enumerator(at: targetSourceURL, includingPropertiesForKeys: [.isRegularFileKey])?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" } ?? []

    for sourceURL in sourceURLs {
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        if source.contains("@main") {
            guard let typeName = entryPointTypeName(in: source) else {
                throw WASMBuilderError.missingEntryPointType(sourceURL.path)
            }

            return EntryPoint(sourceURL: sourceURL, typeName: typeName)
        }
    }

    throw WASMBuilderError.missingEntryPoint(targetSourceURL.path)
}

private func entryPointTypeName(in source: String) -> String? {
    guard let mainRange = source.range(of: "@main") else {
        return nil
    }

    let searchRange = mainRange.upperBound..<source.endIndex
    for keyword in ["struct", "enum", "class", "actor"] {
        guard let keywordRange = source.range(of: keyword, range: searchRange) else {
            continue
        }

        let nameStart = source[keywordRange.upperBound...]
            .drop(while: { $0.isWhitespace || $0.isNewline })
            .startIndex
        let nameEnd = source[nameStart...]
            .firstIndex(where: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            ?? source.endIndex

        if nameStart < nameEnd {
            return String(source[nameStart..<nameEnd])
        }
    }

    return nil
}

private func addWrapperProduct(to packageURL: URL, target: String) async throws {
    let manifestURL = packageURL.appendingPathComponent("Package.swift")
    let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
    if manifest.contains("SwiftWASMWrapper") {
        return
    }

    let result = try await run(
        .name("swift"),
        arguments: [
            "package",
            "add-product",
            "SwiftWASMWrapper",
            "--type",
            "executable",
            "--targets",
            target,
        ],
        workingDirectory: FilePath(packageURL.path),
        output: .string(limit: 4096),
        error: .string(limit: 4096)
    )

    if result.terminationStatus.isSuccess {
        return
    }

    try PackageManifestParser.addWrapperProduct(to: packageURL, target: target)
}

private enum PackageManifestParser {
    static func parse(packageURL: URL) throws -> PackageDescription {
        let manifestURL = packageURL.appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let targets = executableTargets(in: manifest)

        if !targets.isEmpty {
            return PackageDescription(targets: targets)
        }

        throw WASMBuilderError.packageDescriptionFailed(
            status: "fallback parser failed",
            standardOutput: "",
            standardError: "No executableTarget declarations were found in \(manifestURL.path)."
        )
    }

    static func addWrapperProduct(to packageURL: URL, target: String) throws {
        let manifestURL = packageURL.appendingPathComponent("Package.swift")
        var manifest = try String(contentsOf: manifestURL, encoding: .utf8)

        if manifest.contains("SwiftWASMWrapper") {
            return
        }

        let insertion = """
                .executable(
                    name: "SwiftWASMWrapper",
                    targets: ["\(target)"]
                ),
        """

        guard let productsRange = manifest.range(of: "products: ["),
            let insertionIndex = manifest[productsRange.upperBound...].firstIndex(of: "\n")
        else {
            throw WASMBuilderError.addProductFailed(
                status: "fallback parser failed",
                standardOutput: "",
                standardError: "No products array was found in \(manifestURL.path)."
            )
        }

        manifest.insert(contentsOf: "\n\(insertion)", at: manifest.index(after: insertionIndex))
        try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
    }

    static func removeAppleProductTypesIfPresent(in packageURL: URL) throws {
        let manifestURL = packageURL.appendingPathComponent("Package.swift")
        var manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        let originalManifest = manifest

        manifest = manifest.replacingOccurrences(of: "import AppleProductTypes\n", with: "")
        manifest = removingDeclarations(in: manifest, declaration: ".iOSApplication(")

        if manifest != originalManifest {
            try manifest.write(to: manifestURL, atomically: true, encoding: .utf8)
        }
    }

    private static func executableTargets(in manifest: String) -> [TargetDescription] {
        declarationBlocks(in: manifest, declaration: ".executableTarget(").compactMap { block in
            guard let name = argument(named: "name", in: block) else {
                return nil
            }

            return TargetDescription(
                name: name,
                type: .string("executable"),
                path: argument(named: "path", in: block)
            )
        }
    }

    private static func declarationBlocks(in source: String, declaration: String) -> [String] {
        var blocks: [String] = []
        var searchStart = source.startIndex

        while let declarationRange = source.range(of: declaration, range: searchStart..<source.endIndex) {
            var depth = 1
            var index = declarationRange.upperBound

            while index < source.endIndex, depth > 0 {
                if source[index] == "(" {
                    depth += 1
                } else if source[index] == ")" {
                    depth -= 1
                }

                index = source.index(after: index)
            }

            blocks.append(String(source[declarationRange.upperBound..<source.index(before: index)]))
            searchStart = index
        }

        return blocks
    }

    private static func removingDeclarations(in source: String, declaration: String) -> String {
        var result = source
        var searchStart = result.startIndex

        while let declarationRange = result.range(of: declaration, range: searchStart..<result.endIndex) {
            var depth = 1
            var index = declarationRange.upperBound

            while index < result.endIndex, depth > 0 {
                if result[index] == "(" {
                    depth += 1
                } else if result[index] == ")" {
                    depth -= 1
                }

                index = result.index(after: index)
            }

            var removalEnd = index
            while removalEnd < result.endIndex, result[removalEnd].isWhitespace, result[removalEnd] != "\n" {
                removalEnd = result.index(after: removalEnd)
            }

            if removalEnd < result.endIndex, result[removalEnd] == "," {
                removalEnd = result.index(after: removalEnd)
            }

            if removalEnd < result.endIndex, result[removalEnd] == "\n" {
                removalEnd = result.index(after: removalEnd)
            }

            result.removeSubrange(declarationRange.lowerBound..<removalEnd)
            searchStart = declarationRange.lowerBound
        }

        return result
    }

    private static func argument(named name: String, in source: String) -> String? {
        guard let nameRange = source.range(of: "\(name):") else {
            return nil
        }

        let searchRange = nameRange.upperBound..<source.endIndex
        guard let openingQuote = source[searchRange].firstIndex(of: "\"") else {
            return nil
        }

        let valueStart = source.index(after: openingQuote)
        guard let closingQuote = source[valueStart...].firstIndex(of: "\"") else {
            return nil
        }

        return String(source[valueStart..<closingQuote])
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
