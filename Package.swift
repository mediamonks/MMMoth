// swift-tools-version:5.4
import PackageDescription

let package = Package(
    name: "MMMoth",
    platforms: [
        .iOS(.v11)
    ],
    products: [
        .library(
            name: "MMMoth",
            targets: [
				"MMMoth",
				"Core",
				"UI",
				"Mocks"
			]
		)
    ],
    dependencies: [
		.package(url: "https://github.com/mediamonks/MMMLoadable", .upToNextMajor(from: "1.6.4")),
		.package(url: "https://github.com/mediamonks/MMMCommonUI", .upToNextMajor(from: "3.6.1")),
		.package(url: "https://github.com/mediamonks/MMMocking", .upToNextMajor(from: "0.1.4")),
		.package(url: "https://github.com/mediamonks/MMMObservables", .upToNextMajor(from: "1.4.1")),
		.package(url: "https://github.com/mediamonks/MMMCommonCore", .upToNextMajor(from: "1.8.1"))
    ],
    targets: [
        .target(
            name: "MMMoth",
            dependencies: [
				"Core",
				"UI"
			],
            path: "Sources/MMMoth"
		),
		.target(
            name: "Core",
            dependencies: [
				"MMMLoadable"
            ],
            path: "Sources/Core"
		),
        .target(
            name: "UI",
            dependencies: [
				"Core",
				"MMMCommonUI"
            ],
            path: "Sources/UI"
		),
        .target(
            name: "Mocks",
            dependencies: [
				"UI",
				"MMMocking",
				"MMMObservables",
				"MMMCommonCore"
            ],
            path: "Sources/Mocks"
		),
        .testTarget(
            name: "MMMothTests",
            dependencies: ["MMMoth"],
            path: "Tests"
		)
    ]
)
