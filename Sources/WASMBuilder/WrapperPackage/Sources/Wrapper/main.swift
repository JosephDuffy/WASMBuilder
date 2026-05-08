#if os(WASI)
@_expose(wasm, "main")
@_cdecl("main")
public func main() {
    _main()
}

@_expose(wasm, "_initialize")
@_cdecl("_initialize")
public func _initialize() {
    // No-op, but required to ensure the module is properly initialized when called from JavaScript.
}
#else
@main
struct WASMWrapper {
    static func main() {
        _main()
    }
}
#endif

@inline(__always)
private func _main() {
        // REPLACE_ME
}