// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SkillAtlasCore", platforms: [.macOS(.v14)],
    products: [.library(name: "SkillAtlasCore", targets: ["SkillAtlasCore"])],
    targets: [
        .target(name: "SkillAtlasCore", path: "Core", resources: [.copy("FocusEngine/clock-contract.json")]),
        .testTarget(name: "SkillAtlasCoreTests", dependencies: ["SkillAtlasCore"], path: "Tests")
    ]
)
