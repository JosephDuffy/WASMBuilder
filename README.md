# WASMBuilder

WASMBuilder is a Swift package containing various utilities that enable compiling Swift files and packages to WASM.

The goal of the project is to enable producing usable `.wasm` files to allow for embedding runable demos of Swift code in web pages. The project allows for building with either the full WASM SDK or the embedded WASM SDK.

Running

```shell
swift run wasm-builder --swift-app-package ./fixtures/Example\ App\ Playground.swiftpm/ --output-file ./Public/playground-example.wasm --sdk wasm-embedded --link-embedded-unicode-data-tables
```

will build the Swift App Playground at `./fixtures/Example\ App\ Playground.swiftpm/` in to a `.wasm` file using [Embedded Swift]((https://www.swift.org/get-started/embedded/)). This supports package dependencies and can be loaded using a small shim provided in `Public/static.html`.

Embedded Swift adds lots of restrictions, but for simple demos this is not a problem and the produced binary, after run through `wasm-strip`, can be as small as 11 KB (larger than small HTML pages, smaller than most JavaScript files). Regular, non-embedded, builds run closer to 6 MB.

## Requirements

WASMBuilder requires a WASM SDK to be available, which should match your current compiler version. Follow the [Getting Started with Swift SDKs for WebAssembly](https://www.swift.org/documentation/articles/wasm-getting-started.html) guide on how to install the correct SDKs. For my usage I have used Swift 6.3.1 with the `swift-6.3.1-RELEASE_wasm` and `swift-6.3.1-RELEASE_wasm-embedded` SDKs.

## Building Swift App Packages

To enable a demo to be split in to multiple packages and to pull in external dependencies support for Swift App Packages is provided.

## Enabling Full Unicode-compliant String Support

As [described in the embedded Swift documentation](https://docs.swift.org/embedded/documentation/embedded/strings) a separate static library is required when various string operations are required.

This can be enabled using the `--link-embedded-unicode-data-tables` flag, at the cost of around 105 KB.
