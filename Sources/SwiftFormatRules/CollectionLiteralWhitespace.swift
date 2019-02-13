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

/// Enforces whitespace requirements for array literals, tuples, and dictionary literals.
///
/// Lint: If an array, dictionary, or tuple literal it on a single line, and there are any spaces
///       after the opening delimiter, or any spaces before the closing delimiter, a lint
///       error is raised.
///
/// - SeeAlso: https://google.github.io/swift#horizontal-whitespace
public final class CollectionLiteralWhitespace: SyntaxLintRule {
  public override func visit(_ token: TokenSyntax) {
    // Ensure we have an adjacent token on the same line
    guard let next = token.nextToken else { return }
    if next.leadingTrivia.containsNewlines { return }

    // If either this current token is a left delimiter, or the next token
    // is a right delimiter, then remove spaces from our trailing trivia.
    if token.tokenKind.isLeftBalancedDelimiter && token.trailingTrivia.containsSpaces {
      diagnose(.noSpacesAfter(token), on: token)
      return
    }

    if next.tokenKind.isRightBalancedDelimiter && token.trailingTrivia.containsSpaces {
      diagnose(.noSpacesBefore(next), on: next)
      return
    }
  }
}

extension Diagnostic.Message {
  static func noSpacesAfter(_ token: TokenSyntax) -> Diagnostic.Message {
    return .init(.warning, "remove spaces after '\(token.text)'")
  }
  static func noSpacesBefore(_ token: TokenSyntax) -> Diagnostic.Message {
    return .init(.warning, "remove spaces before '\(token.text)'")
  }
}
