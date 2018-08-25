// swift-tools-version:4.1
//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Formatter open source project.
//
// Copyright (c) 2018 Apple Inc. and the Swift Formatter project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Formatter project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import PackageDescription

let package = Package(
  name: "swiftformat",
  dependencies: [
    .package(url: "https://github.com/apple/swift-package-manager.git", from: "0.1.0"),
    .package(url: "https://github.com/apple/swift-syntax", from: "0.40200.0"),
  ],
  targets: [
    .target(
      name: "swiftformat",
      dependencies: ["Rules", "Core", "Configuration", "PrettyPrint", "SwiftSyntax", "Utility"]),
    .target(
      name: "generate-pipeline",
      dependencies: ["SwiftSyntax"]),
    .target(
      name: "Rules",
      dependencies: ["Core", "Configuration"]),
    .target(
      name: "PrettyPrint",
      dependencies: ["Core", "Configuration"]),
    .target(
      name: "Core",
      dependencies: ["Configuration", "SwiftSyntax"]),
    .target(
      name: "Configuration",
      dependencies: []),
    .target(name: "CommonMark", dependencies: ["CCommonMark"]),
    .target(
      name: "CCommonMark",
      exclude: [
        "cmark/api_test",
        // We must exclude main.c or SwiftPM will treat this target as an
        // executable target and we won't be able to import it from the
        // CommonMark Swift module.
        "cmark/src/main.c",
      ]
    ),
    .testTarget(
      name: "SwiftFormatTests",
      dependencies: ["Core", "Configuration", "Rules", "PrettyPrint", "SwiftSyntax"]),
    .testTarget(
      name: "PrettyPrinterTests",
      dependencies: ["Core", "Configuration", "Rules", "PrettyPrint", "SwiftSyntax"]),
    .testTarget(name: "CommonMarkTests", dependencies: ["CommonMark"]),
  ]
)
