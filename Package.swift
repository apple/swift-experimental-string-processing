// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let availabilityDefinition = PackageDescription.SwiftSetting.unsafeFlags([
    "-Xfrontend",
    "-define-availability",
    "-Xfrontend",
    #""SwiftStdlib 5.7:macOS 9999, iOS 9999, watchOS 9999, tvOS 9999""#
])

let package = Package(
    name: "swift-experimental-string-processing",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "_StringProcessing",
            targets: ["_StringProcessing"]),
        .library(
            name: "Prototypes",
            targets: ["Prototypes"]),
        .library(
            name: "_RegexParser",
            targets: ["_RegexParser"]),
        .executable(
            name: "VariadicsGenerator",
            targets: ["VariadicsGenerator"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages which this package depends on.
        .target(
            name: "_RegexParser",
            dependencies: [],
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"]),
                availabilityDefinition
            ]),
        .testTarget(
            name: "MatchingEngineTests",
            dependencies: [
                "_RegexParser", "_StringProcessing"
            ]),
        .target(
            name: "_CUnicode",
            dependencies: []),
        .target(
            name: "_StringProcessing",
            dependencies: ["_RegexParser", "_CUnicode"],
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"]),
                availabilityDefinition
            ]),
        .target(
            name: "RegexBuilder",
            dependencies: ["_StringProcessing", "_RegexParser"],
            swiftSettings: [
                .unsafeFlags(["-enable-library-evolution"]),
                .unsafeFlags(["-Xfrontend", "-enable-experimental-pairwise-build-block"]),
                availabilityDefinition
            ]),
        .testTarget(
            name: "RegexTests",
            dependencies: ["_StringProcessing"],
            swiftSettings: [availabilityDefinition]),
        .testTarget(
            name: "RegexBuilderTests",
            dependencies: ["_StringProcessing", "RegexBuilder"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-enable-experimental-pairwise-build-block"]),
                availabilityDefinition
            ]),
        .target(
            name: "Prototypes",
            dependencies: ["_RegexParser", "_StringProcessing"],
            swiftSettings: [availabilityDefinition]),

        // MARK: Scripts
        .executableTarget(
            name: "VariadicsGenerator",
            dependencies: [
              .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]),
        .executableTarget(
            name: "PatternConverter",
            dependencies: [
              .product(name: "ArgumentParser", package: "swift-argument-parser"),
              "_RegexParser",
              "_StringProcessing"
            ]),

        // MARK: Exercises
        .target(
          name: "Exercises",
          dependencies: ["_RegexParser", "Prototypes", "_StringProcessing", "RegexBuilder"],
          swiftSettings: [
              .unsafeFlags(["-Xfrontend", "-enable-experimental-pairwise-build-block"]),
              availabilityDefinition
          ]),
        .testTarget(
          name: "ExercisesTests",
          dependencies: ["Exercises"],
          swiftSettings: [availabilityDefinition]),
    ]
)
