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

/// Enforces rules about when to use unicode escape sequences in `String`s.
///
/// For any character that has a special escape sequence (\t, \n, \r, \", \', \\, and \0), that
/// sequence is used rather than the equivalent Unicode (e.g., \u{000a}) escape sequence.
///
/// See: https://google.github.io/swift#special-escape-sequences
///
/// Lint: If a Unicode escape sequence appears in a string literal for a character that has a
///       corresponding special escape sequence, a lint error will be raised.
///
/// Format: Unicode escape sequences for characters which have a special escape sequence will
///         be replaced with the special escape sequence.
public final class UseSpecialEscapeSequences: FileRule {

}
