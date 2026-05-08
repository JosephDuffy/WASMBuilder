import Vapor
import WASMBuilder

struct HelloResponse: Content {
    let message: String
}

struct BuildWASMRequest: Content {
    let sourceFile: String?
    let outputFile: String?
}

func routes(_ app: Application) throws {
    app.get("api", "hello") { _ async -> HelloResponse in
        HelloResponse(message: "Hello, world!")
    }

    app.get("api", "build-wasm") { req async throws -> HelloResponse in
        let buildRequest = try req.query.decode(BuildWASMRequest.self)
        guard
              let sourceFile = buildRequest.sourceFile,
              let outputFile = buildRequest.outputFile else {
            return HelloResponse(message: "Missing input or output parameter")
        }

        let builder = WASMBuilder()
        do {
            try await builder.build(sourceFile: sourceFile, outputFile: outputFile)
            return HelloResponse(message: "WASM build succeeded")
        } catch {
            return HelloResponse(message: "Failed to build WASM: \(error)")
        }
    }

    app.get { _ async -> Response in
        let html = """
        <!doctype html>
        <html lang="en">
        <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Hello Vapor</title>
            <style>
                body {
                    align-items: center;
                    background: #f5f7fa;
                    color: #17202a;
                    display: flex;
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
                    justify-content: center;
                    margin: 0;
                    min-height: 100vh;
                }

                main {
                    max-width: 38rem;
                    padding: 2rem;
                    text-align: center;
                }

                h1 {
                    font-size: 3rem;
                    margin: 0 0 1rem;
                }

                p {
                    font-size: 1.125rem;
                    line-height: 1.6;
                    margin: 0;
                }
            </style>
        </head>
        <body>
            <main>
                <h1>Hello, Vapor!</h1>
                <p>Your Swift server is running and ready for routes, middleware, and views.</p>
            </main>
            <script>
                async function fetchAndRunWASM() {
                    const wasmResponse = await fetch("/swift-embedded.wasm")
                    const module = await WebAssembly.compileStreaming(wasmResponse)
                    const instance = await WebAssembly.instantiateStreaming(module)
                    console.dir(instance)
                    instance.exports.main()
                }
                fetchAndRunWASM()
            </script>
        </body>
        </html>
        """

        var headers = HTTPHeaders()
        headers.add(name: .contentType, value: "text/html; charset=utf-8")

        return Response(
            status: .ok,
            headers: headers,
            body: .init(string: html)
        )
    }
}
