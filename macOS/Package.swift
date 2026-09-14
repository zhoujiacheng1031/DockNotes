// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DockNotes",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "DockNotes", targets: ["DockNotesApp"])
    ],
    targets: [
        .executableTarget(
            name: "DockNotesApp",
            exclude: ["Resources"]
        )
    ]
)
