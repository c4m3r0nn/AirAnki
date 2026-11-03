// swift-tools-version: 5.9
import PackageDescription
import Foundation

let selfTest = ProcessInfo.processInfo.environment["AIRANKI_SELF_TEST"] == "1"

let package = Package(
    name: "AirAnki",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AirAnki", targets: ["AirAnki"]),
        .executable(name: "AirAnkiReplay", targets: ["AirAnkiReplay"]),
        .library(name: "AirAnkiCore", targets: ["AirAnkiCore"])
    ] + (selfTest ? [.executable(name: "AirAnkiCoreSelfTest", targets: ["AirAnkiCoreSelfTest"])] : []),
    targets: [
        .target(name: "AirAnkiCore"),
        .executableTarget(name: "AirAnki", dependencies: ["AirAnkiCore"]),
        .executableTarget(name: "AirAnkiReplay", dependencies: ["AirAnkiCore"])
    ] + (selfTest ? [
        .executableTarget(name: "AirAnkiCoreSelfTest", dependencies: ["AirAnkiCore"],
                          path: "Tests/AirAnkiCoreTests", swiftSettings: [.define("AIRANKI_SELF_TEST")])
    ] : [
        .testTarget(name: "AirAnkiCoreTests", dependencies: ["AirAnkiCore"],
                    exclude: ["SelfTestMain.swift", "SelfTestAssertions.swift"])
    ])
)
