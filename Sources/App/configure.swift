import Vapor

public func configure(_ app: Application) async throws {
    try routes(app)

    // Serves files from `Public/` directory
    let fileMiddleware = FileMiddleware(
        publicDirectory: app.directory.publicDirectory
    )
    app.middleware.use(fileMiddleware)
}
