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
import SwiftSyntax

/// A linting rule that does not parse the file, but instead runs analyses over the raw text of
/// the file.
open class FileRule: Rule {
  /// The context in which this rule in run.
  public let context: Context

  /// Creates a new FileRule executing in the provided context.
  public required init(context: Context) {
    self.context = context
  }
}
