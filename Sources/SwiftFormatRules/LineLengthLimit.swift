//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import Foundation
import SwiftFormatCore
import SwiftSyntax

/// Enforces line length limits.
///
/// Lint: If a line exceeds the maximum line length, a lint error is raised.
///
/// - SeeAlso: https://google.github.io/swift#column-limit
public final class LineLengthLimit: SyntaxLintRule {

}
