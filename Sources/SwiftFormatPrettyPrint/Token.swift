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

import SwiftFormatConfiguration
import SwiftFormatCore
import SwiftSyntax

enum GroupBreakStyle {
  /// A consistent break indicates that the break will always be finalized as a newline
  /// if wrapping occurs.
  case consistent

  /// Inconsistent breaks will only be expressed as a newline if they're required to be wrapped as
  /// their addition to the line would go past the line length limit.
  case inconsistent
}

enum BreakKind {
  /// If line wrapping occurs at an `open` break, then the base indentation level increases by one
  /// indentation unit until the corresponding `close` break is encountered.
  case open

  /// If line wrapping occurs at a `close` break, then the base indentation level returns to the
  /// value it had before the corresponding `open` break.
  case close

  /// If line wrapping occurs at a `continue` break, then the following line will be treated as a
  /// continuation line (indented one unit further than the base level) without changing the base
  /// level.
  ///
  /// An example use of a `continue` break is when an expression is split across multiple lines;
  /// the break before each operator is a continuation:
  ///
  /// ```swift
  /// let someLongVariable = someLongExpression
  ///   + anotherLongExpression - aThirdLongExpression
  ///   + somethingElse
  /// ```
  case `continue`

  /// If line wrapping occurs at a `same` break, then the following line will be indented at the
  /// base indentation level instead of an increased continuation level.
  ///
  /// An example use of a `same` break is to align the first element on each line in a
  /// comma-delimited list:
  ///
  /// ```swift
  /// let array = [
  ///   1, 2, 3,
  ///   4, 5, 6,
  ///   7, 8, 9,
  /// ]
  /// ```
  case same

  /// A `reset` break that occurs on a continuation line forces a line break that ends the
  /// continuation and causes the tokens on the next line to be indented at the base indentation
  /// level.
  ///
  /// These breaks are used, for example, to force an open curly brace onto a new line if it would
  /// otherwise fit on a continuation line, so that the body of the braced block can be
  /// distinguished from the continuation line(s) above it:
  ///
  /// ```swift
  /// func foo(_ x: Int) {
  ///   // This is allowed because the line above is not a continuation.
  /// }
  ///
  /// func foo(
  ///   _ x: Int
  /// ) {
  ///   // This is also allowed, for the same reason.
  /// }
  ///
  /// func foo(_ x: Int)
  ///   throws -> Int
  /// {
  ///   // Here we must force the brace down or the block contents would
  ///   // collide with the "throws" line.
  /// }
  /// ```
  case reset
}

enum Token {
  case syntax(String)
  case open(GroupBreakStyle)
  case close
  case `break`(BreakKind, size: Int)
  case space(size: Int)
  case newlines(Int, discretionary: Bool)
  case comment(Comment, wasEndOfLine: Bool)
  case verbatim(Verbatim)

  // Convenience overloads for the enum types
  static let open = Token.open(.inconsistent, 0)
  static func open(_ breakStyle: GroupBreakStyle, _ offset: Int) -> Token {
    return Token.open(breakStyle)
  }
  static let newline = Token.newlines(1, discretionary: false)
  static func newline(discretionary: Bool) -> Token {
    return Token.newlines(1, discretionary: discretionary)
  }

  static let space = Token.space(size: 1)

  static let `break` = Token.break(.continue, size: 1)
  static func `break`(_ kind: BreakKind) -> Token {
    return .break(kind, size: 1)
  }

  static func verbatim(text: String) -> Token {
    return Token.verbatim(Verbatim(text: text))
  }
}
