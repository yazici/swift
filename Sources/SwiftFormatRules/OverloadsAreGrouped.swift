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

/// Multiple overloads with the same base name must be grouped together, appearing seqeuntially.
///
/// Initializers and subscripts are considered to have the same base name.
///
/// Lint: Overloads that do not appear sequentially will yield lint errors.
///
/// Format: Overloads will be moved so that they are sequential; they will all appear after the
///         first matching overload in the file.
///
/// - SeeAlso: https://google.github.io/swift#overloaded-declarations
public final class OverloadsAreGrouped: SyntaxFormatRule {

}
