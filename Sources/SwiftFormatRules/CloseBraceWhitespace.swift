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

// TODO(abl): "right brace" to be consistent with SwiftSyntax?
/// Enforce whitespace for close braces.
///
/// Lint: If a close brace does not have a line break before it, except as covered by One Statement
///       Per Line, a lint error will be raised.
///
/// - SeeAlso: https://google.github.io/swift#braces
public final class CloseBraceWhitespace: SyntaxLintRule {
  public override func visit(_ token: TokenSyntax) {
    guard token.tokenKind == .rightBrace else { return }
    if isInAllowedSingleLineContainer(token) { return }
    if token.leadingTrivia.containsNewlines { return }

    diagnose(.lineBreakRequiredBeforeCloseBrace, on: token)
  }
}

/// Returns `true` if the containing syntax node that is allowed to be a
/// single-line braced node (currently closures and getters/setters), if the
/// node has only one statement.
func isInAllowedSingleLineContainer(_ token: TokenSyntax) -> Bool {
  if token.parent is AccessorBlockSyntax { return true }
  guard let container = token.containingExprStmtOrDecl else { return false }
  if let stmtContainer = container as? WithStatementsSyntax {
    guard stmtContainer.statements.count <= 1,
          stmtContainer is ClosureExprSyntax ||
          stmtContainer is AccessorDeclSyntax else {
      return false
    }
    return true
  } else if let block = token.parent as? CodeBlockSyntax {
    return block.statements.count <= 1
  }
  return false
}

extension Diagnostic.Message {
  static let lineBreakRequiredBeforeCloseBrace =
    Diagnostic.Message(.warning, "insert a newline before this '}'")
}
