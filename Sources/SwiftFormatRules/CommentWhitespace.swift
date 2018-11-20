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

import SwiftFormatCore
import SwiftSyntax

/// There are at least two spaces before the `//` that begins a line comment.
///
/// Lint: If an invalid number of spaces appear before a comment, a lint error is raised.
///
/// - SeeAlso: https://google.github.io/swift#horizontal-whitespace
public final class CommentWhitespace: SyntaxLintRule {

  public override func visit(_ token: TokenSyntax) {
    guard let nextToken = token.nextToken else { return }

    // Ensures the line comment has at least two spaces before the `//`.
    if triviaIsEndOfLineComment(nextToken.leadingTrivia) {
      let numberOfSpaces = token.trailingTrivia.numberOfSpaces
      if numberOfSpaces < 2 {
        let spacesToAdd = 2 - numberOfSpaces
        diagnose(.addSpacesBeforeLineComment(count: spacesToAdd), on: token)
      }
    }
  }

  /// Returns a value indicating whether the given trivia represents an end of line comment.
  private func triviaIsEndOfLineComment(_ trivia: Trivia) -> Bool {
    // Comments are end-of-line unless the trivia begins with a newline.
    if let firstPiece = trivia.reversed().last {
      if case .newlines(_) = firstPiece { return false }
    }
    for piece in trivia {
      if case .lineComment(_) = piece { return true }
    }
    return false
  }
}

extension Diagnostic.Message {

  static func addSpacesBeforeLineComment(count: Int) -> Diagnostic.Message {
    let ending = count == 1 ? "" : "s"
    return Diagnostic.Message(.warning, "add \(count) space\(ending) before the //")
  }
}
