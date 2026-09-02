// swift-tools-version: 5.9
//
// This package exists to unit-test `Core/` from the command line (`swift test`) without
// needing Xcode. The app itself is built from InlineRewriter.xcodeproj, which compiles the
// same Core sources directly into the app target.
import PackageDescription

let package = Package(
    name: "InlineRewriterCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "InlineRewriterCore",
            path: "Core"
        ),
        .testTarget(
            name: "InlineRewriterCoreTests",
            dependencies: ["InlineRewriterCore"],
            path: "Tests/InlineRewriterCoreTests"
        ),
    ]
)
