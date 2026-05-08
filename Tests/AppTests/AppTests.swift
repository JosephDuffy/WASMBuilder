@testable import App
import VaporTesting
import Testing

@Suite("App Tests")
struct AppTests {
    @Test
    func helloEndpointReturnsJSON() async throws {
        try await withApp(configure: configure(_:)) { app in
            try await app.testing().test(.GET, "api/hello") { response async throws in
                #expect(response.status == .ok)
                #expect(response.content.contentType == .json)
                try #expect(
                    response.content.decode(HelloResponse.self).message == "Hello, world!"
                )
            }
        }
    }

    @Test
    func rootEndpointReturnsHTML() async throws {
        try await withApp(configure: configure(_:)) { app in
            try await app.testing().test(.GET, "") { response async throws in
                #expect(response.status == .ok)
                #expect(response.headers.first(name: .contentType) == "text/html; charset=utf-8")
                #expect(response.body.string.contains("<h1>Hello, Vapor!</h1>"))
            }
        }
    }
}
