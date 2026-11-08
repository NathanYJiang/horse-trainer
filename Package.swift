// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HorseTrainer",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "HorseTrainer", targets: ["HorseTrainer"]),
        .library(name: "PokerCore", targets: ["PokerCore"]),
    ],
    targets: [
        .target(name: "PokerCore"),
        .executableTarget(name: "HorseTrainer", dependencies: ["PokerCore"], resources: [.copy("Resources/Fonts")]),
        .testTarget(name: "PokerCoreTests", dependencies: ["PokerCore"]),
    ]
)
