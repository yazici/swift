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

/// All values should be written in lower camel-case (`lowerCamelCase`).
/// Underscores (except at the beginning of an identifier) are disallowed.
///
/// Lint: If an identifier contains underscores or begins with a capital letter, a lint error is
///       raised.
///
/// - SeeAlso: https://google.github.io/swift#identifiers
public final class AlwaysUseLowerCamelCase: SyntaxLintRule {
  public override func visit(_ node: VariableDeclSyntax) {
    for binding in node.bindings {
      guard let pat = binding.pattern as? IdentifierPatternSyntax else {
        continue
      }
      diagnoseLowerCamelCaseViolations(pat.identifier)
    }
  }

  public override func visit(_ node: FunctionDeclSyntax) {
    diagnoseLowerCamelCaseViolations(node.identifier)
  }

  public override func visit(_ node: EnumCaseElementSyntax) {
    diagnoseLowerCamelCaseViolations(node.identifier)
  }

  func diagnoseLowerCamelCaseViolations(_ identifier: TokenSyntax) {
    guard case .identifier(let text) = identifier.tokenKind else { return }
    if text.isEmpty { return }
    if text.dropFirst().contains("_") || ("A"..."Z").contains(text.first!) {
      diagnose(.variableNameMustBeLowerCamelCase(text), on: identifier) {
        $0.highlight(identifier.sourceRange(in: self.context.fileURL))
      }
    }
  }
}

extension Diagnostic.Message {
  static func variableNameMustBeLowerCamelCase(_ name: String) -> Diagnostic.Message {
    return .init(.warning, "variable '\(name)' must be lower-camel-case")
  }
}

