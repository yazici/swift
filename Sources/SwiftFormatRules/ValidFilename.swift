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

/// All Swift source files end with the extension `.swift` and are named based on contents.
///
/// If a file contains a single public type, it is named for that type.
/// If a file extends a type with protocol conformance, it is named `Type+Protocol`.
///
/// See: http://g3doc/company/teams/swift-readability/style_guide#file-names
///
/// Lint: If the above rules are violated, a lint error is raised.
public final class ValidFilename: FileRule {

}
