// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ScaleKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ScaleKit", targets: ["ScaleKit"]),
    ],
    targets: [
        .target(name: "ScaleKit"),
        .executableTarget(
            name: "scale-probe",
            dependencies: ["ScaleKit"],
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "ScaleKitTests",
            dependencies: ["ScaleKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
