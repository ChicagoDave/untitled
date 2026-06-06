// swift-tools-version:6.2
//
// Package manifest for the Galley macOS editor shell (overview §13, step 2;
// ADR-0001/0002/0003). The shell CONSUMES the headless `GalleyCore` package
// and never modifies it to accept UI types — dependencies flow inward only.
//
// Targets:
//   - `GalleyShell` (library): Foundation + GalleyCore — the `.galley` file-pair
//     I/O plus the AppKit-free workspace store (`WorkspaceModel`/
//     `WorkspaceDocument`, ADR-0011 fix (a)). No AppKit, fully testable headlessly.
//   - `Galley` (executable): the `@main` SwiftUI/AppKit shell, incl. file panels.
//   - `GalleyShellTests` (test): real-path tests for the file layer and workspace.

import PackageDescription

let package = Package(
    name: "Galley",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../core"),
    ],
    targets: [
        .target(
            name: "GalleyShell",
            dependencies: [.product(name: "GalleyCore", package: "core")]
        ),
        .executableTarget(
            name: "Galley",
            dependencies: [
                "GalleyShell",
                .product(name: "GalleyCore", package: "core"),
            ]
        ),
        .testTarget(
            name: "GalleyShellTests",
            dependencies: [
                "GalleyShell",
                .product(name: "GalleyCore", package: "core"),
            ]
        ),
    ]
)
