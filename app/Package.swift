// swift-tools-version:6.2
//
// Package manifest for the Untitled macOS editor shell (overview §13, step 2;
// ADR-0001/0002/0003). The shell CONSUMES the headless `UntitledCore` package
// and never modifies it to accept UI types — dependencies flow inward only.
//
// Targets:
//   - `UntitledShell` (library): pure Foundation + UntitledCore file-pair I/O —
//     no AppKit, fully testable headlessly.
//   - `UntitledApp` (executable): the `@main` SwiftUI/AppKit shell.
//   - `UntitledShellTests` (test): real-path round-trip tests for the file layer.

import PackageDescription

let package = Package(
    name: "UntitledApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../core"),
    ],
    targets: [
        .target(
            name: "UntitledShell",
            dependencies: [.product(name: "UntitledCore", package: "core")]
        ),
        .executableTarget(
            name: "UntitledApp",
            dependencies: [
                "UntitledShell",
                .product(name: "UntitledCore", package: "core"),
            ]
        ),
        .testTarget(
            name: "UntitledShellTests",
            dependencies: [
                "UntitledShell",
                .product(name: "UntitledCore", package: "core"),
            ]
        ),
    ]
)
