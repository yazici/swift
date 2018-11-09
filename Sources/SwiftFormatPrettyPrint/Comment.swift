//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Formatter open source project.
//
// Copyright (c) 2018 Apple Inc. and the Swift Formatter project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.txt for the list of Swift Formatter project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import Foundation

struct Comment {
  enum Kind {
    case line, docLine, block, docBlock

    /// The length of the characters starting the comment.
    var prefixLength: Int {
      switch self {
      // `//`, `/*`, and `/**` all will have their continued lines prefixed with 3 characters.
      case .line, .block, .docBlock: return 2

      // `/// ` is 4 characters.
      case .docLine: return 3
      }
    }

    var prefix: String {
      switch self {
      case .line: return "//"
      case .block, .docBlock: return " "
      case .docLine: return "///"
      }
    }
  }
  let kind: Kind
  var text: [String]
  public var length: Int

  init(kind: Kind, text: String) {
    self.text = [text]
    self.kind = kind
    self.length = text.count + kind.prefixLength + 1

    self.text[0].removeFirst(kind.prefixLength)

    switch kind {
    case .docBlock:
      self.text.removeLast(2)
    case .block:
      self.text.removeLast(2)
    default: break
    }
  }

  func print(indent: Int) -> String {
    let separator = "\n" + String(repeating: " ", count: indent) + kind.prefix
    return kind.prefix + self.text.joined(separator: separator)
  }

  mutating func addText(_ text: [String]) {
    for line in text {
      self.text.append(line)
      self.length += line.count + self.kind.prefixLength + 1
    }
  }
}
