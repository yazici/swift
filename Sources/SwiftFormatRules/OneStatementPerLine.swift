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

/// Enforces the 'One Statement Per Line' rule.
///
/// Each statement shall appear on its own line, except those statements with a single
/// sub-statement, such as an `if` statement with a `return` inside.
///
/// Lint: TODO(b/78290677): What is the rule for this that DoNotUseSemicolons doesn't catch?
///
/// Format: TODO(b/78290677): See above.
///
/// - SeeAlso: https://google.github.io/swift#one-statement-per-line
public final class OneStatementPerLine: SyntaxFormatRule {

}
