/// An inline element that represents emphasized (i.e., italicized) text.
public struct EmphasisNode: InlineContent {

  /// The children of the receiver.
  public let children: [InlineContent]

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new emphasized text node.
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
  public func replacingChildren(_ children: [InlineContent]) -> EmphasisNode {
    return EmphasisNode(children: children, sourceRange: sourceRange)
  }

  /// Returns a new node equivalent to the receiver, but whose source range has been replaced with
  /// the given value.
  ///
  /// - Parameter sourceRange: The new source range.
  /// - Returns: The new node.
  public func replacingSourceRange(_ sourceRange: Range<SourceLocation>?) -> EmphasisNode {
    return EmphasisNode(children: children, sourceRange: sourceRange)
  }
}
