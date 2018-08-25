/// A block element that represents a long quotation, typically rendered in a callout box.
public struct BlockQuoteNode: BlockContent {

  /// The children of the receiver.
  public let children: [BlockContent]

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new block quote node.
  ///
  /// - Parameters:
  ///   - children: Block content nodes that are children of the new node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(children: [BlockContent], sourceRange: Range<SourceLocation>? = nil) {
    self.children = children
    self.sourceRange = sourceRange
  }
}
