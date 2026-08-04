// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "S3Repo",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "AWSConfig",
            targets: ["AWSConfig"]
        ),
        .library(
            name: "S3Repo",
            type: .dynamic,
            targets: ["S3Repo"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/awslabs/aws-sdk-swift.git", exact: "1.7.52"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "AWSConfig",
            dependencies: [
                .product(name: "AWSS3", package: "aws-sdk-swift")
            ],
            path: "Sources/AWSConfig"
        ),
        .target(
            name: "S3Repo",
            dependencies: [
                .target(name: "AWSConfig"),
                .product(name: "AWSS3", package: "aws-sdk-swift")
            ],
            path: "Sources/S3Repo"
        )
    ]
)
