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
        .target(name: "CielApp", dependencies: ["CielCore", "CTranscribe"], path: "Sources/Ciel"),
        .executableTarget(name: "Ciel", dependencies: ["CielApp"], path: "Sources/CielMain"),
        .executableTarget(name: "CielBenchmarks", dependencies: ["CielCore"]),
        .testTarget(name: "CielCoreTests", dependencies: ["CielCore"]),
        .binaryTarget(
            name: "CTranscribe",
            url:
                "https://github.com/handy-computer/transcribe.cpp/releases/download/v0.4.1/TranscribeCpp.xcframework.zip",
            checksum: "fb5646e564036a6c49659e3efcf72eb567af20da31b8569045c9a08181d35126"),
        .testTarget(name: "CielAppTests", dependencies: ["CielApp", "CielCore"]),
    ],
    swiftLanguageModes: [.v6]
)
