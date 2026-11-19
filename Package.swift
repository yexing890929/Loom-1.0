// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "Loom", platforms: [.macOS(.v14)], products: [.executable(name: "Loom", targets: ["Loom"])], targets: [.executableTarget(name: "Loom"), .testTarget(name: "LoomTests", dependencies: ["Loom"])])
