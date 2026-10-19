// swift-tools-version:5.9
import PackageDescription

let package = Package(
  name: "micguard",
  platforms: [.macOS(.v13)],
  targets: [.executableTarget(name: "micguard")]
)
