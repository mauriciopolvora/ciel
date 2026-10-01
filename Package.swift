// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ciel",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Ciel", targets: ["Ciel"]),
        .executable(name: "CielBenchmarks", targets: ["CielBenchmarks"]),
    ],
    dependencies: [.package(url: "https://github.com/ordo-one/FuzzyMatch.git", exact: "1.4.0")],
    targets: [
        .target(name: "CielCore", dependencies: [.product(name: "FuzzyMatch", package: "FuzzyMatch")]),
        .target(name: "CielApp", dependencies: ["CielCore"], path: "Sources/Ciel"),
        .executableTarget(name: "Ciel", dependencies: ["CielApp"], path: "Sources/CielMain"),
        .executableTarget(name: "CielBenchmarks", dependencies: ["CielCore"]),
        .testTarget(name: "CielCoreTests", dependencies: ["CielCore"]),
        .testTarget(name: "CielAppTests", dependencies: ["CielApp", "CielCore"]),
    ],
    swiftLanguageModes: [.v6]
)
