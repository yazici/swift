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

/// Force-unwraps are strongly discouraged and must be documented.
///
/// Lint: If a force unwrap is used, a lint warning is raised.
///       TODO(abl): consider having documentation (e.g. a comment) cancel the warning?
///
/// - SeeAlso: https://google.github.io/swift#force-unwrapping-and-force-casts
public final class NeverForceUnwrap: SyntaxLintRule {

  public override func visit(_ node: SourceFileSyntax) {
    // Tracks whether "XCTest" is imported in the source file before processing the individual
    setImportsXCTest(context: context, sourceFile: node)
    super.visit(node)
  }

  public override func visit(_ node: ForcedValueExprSyntax) {
    guard !context.importsXCTest else { return }
    diagnose(.doNotForceUnwrap(name: node.expression.description), on: node)
  }

  public override func visit(_ node: AsExprSyntax) {
    // Only fire if we're not in a test file and if there is an exclamation mark following the `as`
    // keyword.
    guard !context.importsXCTest else { return }
    guard let questionOrExclamation = node.questionOrExclamationMark else { return }
    guard questionOrExclamation.tokenKind == .exclamationMark else { return }
    diagnose(.doNotForceCast(name: node.typeName.description), on: node)
  }
}

extension Diagnostic.Message {
  static func doNotForceUnwrap(name: String) -> Diagnostic.Message {
    return .init(.warning, "do not force unwrap '\(name)'")
  }

  static func doNotForceCast(name: String) -> Diagnostic.Message {
    return .init(.warning, "do not force cast to '\(name)'")
  }
}
