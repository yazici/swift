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

/// Force-try (`try!`) is forbidden.
///
/// This rule does not apply to test code, defined as code which:
///   * Contains the line `import XCTest`
///
/// Lint: Using `try!` results in a lint error.
///
/// TODO: Create exception for NSRegularExpression
///
/// - SeeAlso: https://google.github.io/swift#error-types
public final class NeverUseForceTry: SyntaxLintRule {

  public override func visit(_ node: SourceFileSyntax) {
    setImportsXCTest(context: context, sourceFile: node)
    super.visit(node)
  }

  public override func visit(_ node: TryExprSyntax) {
    guard !context.importsXCTest else { return }
    guard let mark = node.questionOrExclamationMark else { return }
    if mark.tokenKind == .exclamationMark {
      diagnose(.doNotForceTry, on: node.tryKeyword)
    }
  }
}

extension Diagnostic.Message {
  static let doNotForceTry = Diagnostic.Message(.warning, "do not use force try")
}
