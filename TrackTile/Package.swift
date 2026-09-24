// swift-tools-version: 6.0
import PackageDescription

let infoPlist = "\(Context.packageDirectory)/Resources/Info.plist"

let package = Package(
    name: "TrackTile",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "TrackTile", targets: ["TrackTile"]),
    ],
    targets: [
        .target(name: "CMultitouch"),
        .target(name: "TrackTileCore"),
        .executableTarget(
            name: "TrackTile",
            dependencies: ["CMultitouch", "TrackTileCore"],
            linkerSettings: [
                // Embeds Info.plist so `swift run` gets a bundle identifier too.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", infoPlist,
                ]),
            ]
        ),
        .testTarget(name: "TrackTileTests", dependencies: ["TrackTileCore"]),
    ]
)
