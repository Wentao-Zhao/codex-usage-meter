// swift-tools-version: 5.9

import PackageDescription

#if compiler(>=6.3)
let coreSwiftSettings: [SwiftSetting] = [.enableExperimentalFeature("CheckImplementationOnly")]
#else
let coreSwiftSettings: [SwiftSetting] = []
#endif

let package = Package(
  name: "CodexMeter",
  platforms: [
    .macOS(.v13)
  ],
  products: [
    .executable(name: "CodexMeter", targets: ["CodexMeter"]),
    .executable(name: "CodexMeterLogicTests", targets: ["CodexMeterLogicTests"]),
  ],
  targets: [
    .target(name: "CZstdDecoder", path: "Sources/CZstdDecoder", exclude: ["vendor/README.md", "vendor/LICENSE"], publicHeadersPath: "include"),
    .target(
      name: "CodexMeterCore",
      dependencies: ["CZstdDecoder"],
      path: "Sources/CodexMeterCore",
      swiftSettings: coreSwiftSettings
    ),
    .executableTarget(
      name: "CodexMeter",
      dependencies: ["CodexMeterCore"],
      path: "Sources/CodexMeter"
    ),
    .executableTarget(
      name: "CodexMeterLogicTests",
      dependencies: ["CodexMeterCore"],
      path: "Tests/CodexMeterTests"
    ),
  ]
)
