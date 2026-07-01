// swift-tools-version: 5.9

import PackageDescription

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
    .target(
      name: "CodexMeterCore",
      path: "Sources/CodexMeterCore"
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
