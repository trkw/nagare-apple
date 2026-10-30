// swift-tools-version: 5.9
import PackageDescription

// NagareKit holds everything that is not UI (API client, models, keychain), so it can be
// tested with `swift test` without the app.
let package = Package(
    name: "NagareKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NagareKit", targets: ["NagareKit"])],
    targets: [
        .target(name: "NagareKit"),
        .testTarget(name: "NagareKitTests", dependencies: ["NagareKit"]),
    ]
)
