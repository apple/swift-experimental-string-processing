// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let availabilityDefinition = PackageDescription.SwiftSetting.unsafeFlags([
    "-Xfrontend",
    "-define-availability",
    "-Xfrontend",
    "SwiftStdlib 5.7:macOS 9999, iOS 9999, watchOS 9999, tvOS 9999",
])

/// Swift settings for building a private stdlib-like module that is to be used
/// by other stdlib-like modules only.
let privateStdlibSettings: [PackageDescription.SwiftSetting] = [
    .unsafeFlags(["-Xfrontend", "-disable-implicit-concurrency-module-import"]),
    .unsafeFlags(["-Xfrontend", "-disable-implicit-string-processing-module-import"]),
]

/// Swift settings for building a user-facing stdlib-like module.
let publicStdlibSettings: [PackageDescription.SwiftSetting] = [
    .unsafeFlags(["-enable-library-evolution"]),
    .unsafeFlags(["-Xfrontend", "-disable-implicit-concurrency-module-import"]),
    .unsafeFlags(["-Xfrontend", "-disable-implicit-string-processing-module-import"]),
    availabilityDefinition
]

let package = Package(
    name: "swift-experimental-string-processing",
    products: [
        // Products define the executables and libraries produced by a package, and make them visible to other packages.
        .library(
            name: "_StringProcessing",
            targets: ["_StringProcessing"]),
        // FIXME: Disabled due to rdar://94763190.
        // .library(
        //     name: "Prototypes",
        //     targets: ["Prototypes"]),
        .library(
            name: "_RegexParser",
            targets: ["_RegexParser"]),
        .executable(
            name: "VariadicsGenerator",
            targets: ["VariadicsGenerator"]),
        .executable(
            name: "RegexBenchmark",
            targets: ["RegexBenchmark"])
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
            swiftSettings: privateStdlibSettings),
        .testTarget(
            name: "MatchingEngineTests",
            dependencies: [
                "_RegexParser", "_StringProcessing"
            ]),
        .target(
            name: "_StringProcessing",
            dependencies: [
              "_RegexParser"
            ],
            swiftSettings: publicStdlibSettings),
        .target(
            name: "RegexBuilder",
            dependencies: ["_StringProcessing", "_RegexParser"],
            swiftSettings: publicStdlibSettings),
        .testTarget(
            name: "RegexTests",
            dependencies: ["_StringProcessing"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"]),
            ]),
        .testTarget(
            name: "RegexBuilderTests",
            dependencies: ["_StringProcessing", "RegexBuilder"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"])
            ]),
        // FIXME: Disabled due to rdar://94763190.
        // .testTarget(
        //     name: "Prototypes",
        //     dependencies: ["_RegexParser", "_StringProcessing"],
        //     swiftSettings: [
        //         .unsafeFlags(["-Xfrontend", "-disable-availability-checking"])
        //     ]),

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
        .executableTarget(
            name: "RegexTester",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "_RegexParser",
                "_StringProcessing"
            ]),
        .executableTarget(
            name: "RegexBenchmark",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "_RegexParser",
                "_StringProcessing",
                "RegexBuilder"
            ],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"]),
            ]),

        // MARK: Exercises
        .target(
            name: "Exercises",
            dependencies: ["_RegexParser", "_StringProcessing", "RegexBuilder"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"])
            ]),
        .testTarget(
            name: "ExercisesTests",
            dependencies: ["Exercises"],
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"])
            ])
    ]
)
