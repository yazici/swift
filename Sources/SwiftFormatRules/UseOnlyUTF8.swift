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

/// Source files are encoded in UTF-8.
///
/// Lint: Files encoded in anything but UTF-8 will yield a lint error.
///
/// Format: If the given file is not UTF-8, it will be transcoded to UTF-8.
///
/// SeeAlso: https://google.github.io/swift#file-encoding
public final class UseOnlyUTF8: FileRule {

}
