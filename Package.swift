// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "YingxiaReader",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [.library(name: "TVCore", targets: ["TVCore"])],
    targets: [
        .target(name: "TVCore", dependencies: ["QuickJS"], resources: [.process("Resources"), .copy("ScriptAssets")]),
        .target(
            name: "QuickJS", path: "Vendor/QuickJS", exclude: ["LICENSE", "UPSTREAM.md"],
            sources: ["quickjs.c", "libregexp.c", "libunicode.c", "dtoa.c", "TVScript.c"],
            publicHeadersPath: "include",
            cSettings: [.define("_GNU_SOURCE"), .define("QUICKJS_NG_BUILD"), .define("NDEBUG")]
        ),
        .testTarget(name: "ReaderCoreTests", dependencies: ["TVCore"])
    ]
)
