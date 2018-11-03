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

/// A block element that represents a paragraph of text.
public struct ParagraphNode: BlockContent {

  /// The children of the receiver.
  public let children: [InlineContent]

  public let sourceRange: Range<SourceLocation>?

  public var primitiveRepresentation: PrimitiveNode { return .paragraph(self) }

  /// Creates a new paragraph node.
  ///
  /// - Parameters:
  ///   - children: Inline content nodes that are children of the new node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(children: [InlineContent], sourceRange: Range<SourceLocation>? = nil) {
    self.children = children
    self.sourceRange = sourceRange
  }

  /// Returns a new node equivalent to the receiver, but whose children have been replaced with the
  /// given list of nodes.
  ///
  /// - Parameter children: The new list of children.
  /// - Returns: The new node.
  public func replacingChildren(_ children: [InlineContent]) -> ParagraphNode {
    return ParagraphNode(children: children, sourceRange: sourceRange)
  }

  /// Returns a new node equivalent to the receiver, but whose source range has been replaced with
  /// the given value.
  ///
  /// - Parameter sourceRange: The new source range.
  /// - Returns: The new node.
  public func replacingSourceRange(_ sourceRange: Range<SourceLocation>?) -> ParagraphNode {
    return ParagraphNode(children: children, sourceRange: sourceRange)
  }
}
