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

fileprivate let intSizes = ["", "8", "16", "32", "64"]
fileprivate let knownIntTypes = Set(intSizes.map { "Int\($0)" } + intSizes.map { "UInt\($0)" })

/// Avoid using initializer-style casts for literals.
///
/// Using `UInt8(256)` will not error for overflow, leading to a runtime crash. Convert these to
/// `256 as UInt8`, to move the error from runtime to compile time.
///
/// Lint: If an initializer-style cast is used on a built-in type known to be expressible by
///       that kind of literal type, a lint error is raised.
///
/// - SeeAlso: https://google.github.io/swift#numeric-and-string-literals
public final class AvoidInitializersForLiterals: SyntaxLintRule {
  public override func visit(_ node: FunctionCallExprSyntax) {
    // Ensure we're calling a known Integer initializer.
    guard let callee = node.calledExpression as? IdentifierExprSyntax else {
      // Ensure we properly visit the children of this node, in case we have other function calls
      // as parameters to this one.
      return super.visit(node)
    }

    guard node.argumentList.count == 1 else {
      return super.visit(node)
    }

    for arg in node.argumentList {
      if arg.label != nil {
        return super.visit(node)
      }
    }

    let typeName = callee.identifier.text

    guard let _ = extractLiteral(node, typeName) else {
      return super.visit(node)
    }

    diagnose(.avoidInitializerStyleCast(node.description), on: callee) {
      $0.highlight(callee.sourceRange(in: self.context.fileURL))
    }
  }
}

fileprivate func extractLiteral(_ node: FunctionCallExprSyntax, _ typeName: String) -> ExprSyntax? {
  guard let firstArg = node.argumentList.first, node.argumentList.count == 1 else {
    return nil
  }
  if knownIntTypes.contains(typeName) {
    return firstArg.expression as? IntegerLiteralExprSyntax
  }
  if typeName == "Character" {
    return firstArg.expression as? StringLiteralExprSyntax
  }
  return nil
}

extension Diagnostic.Message {
  static func avoidInitializerStyleCast(_ name: String) -> Diagnostic.Message {
    return .init(.warning, "change initializer call '\(name)' with literal argument to an 'as' cast")
  }
}
