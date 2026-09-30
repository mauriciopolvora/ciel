// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ciel",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Ciel", targets: ["Ciel"])],
    dependencies: [.package(url: "https://github.com/ordo-one/FuzzyMatch.git", exact: "1.4.0")],
    targets: [
        .target(name: "CielCore", dependencies: [.product(name: "FuzzyMatch", package: "FuzzyMatch")]),
        .executableTarget(name: "Ciel", dependencies: ["CielCore"]),
        .executableTarget(name: "CielChecks", dependencies: ["CielCore"], path: "Tests/CielCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
