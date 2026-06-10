// swift-tools-version: 6.0
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
// REQUIREMENTS: Before making non-trivial edits to this file, read requirements.md, README.md, and AGENTS.md.

import PackageDescription

let package = Package(
    name: "travels-ios",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TravelsCore",
            targets: ["TravelsCore"]
        ),
        .executable(
            name: "travels-tool",
            targets: ["TravelsCLI"]
        )
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite"
        ),
        .target(
            name: "TravelsCore",
            dependencies: ["CSQLite"]
        ),
        .executableTarget(
            name: "TravelsCLI",
            dependencies: ["TravelsCore"]
        ),
        .testTarget(
            name: "TravelsCoreTests",
            dependencies: ["TravelsCore"]
        )
    ]
)
