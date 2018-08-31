/// A block element that represents a long quotation, typically rendered in a callout box.
public struct BlockQuoteNode: BlockContent {

  /// The children of the receiver.
  public let children: [BlockContent]

  public let sourceRange: Range<SourceLocation>?

  public var primitiveRepresentation: PrimitiveNode { return .blockQuote(self) }

  /// Creates a new block quote node.
  ///
  /// - Parameters:
  ///   - children: Block content nodes that are children of the new node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(children: [BlockContent], sourceRange: Range<SourceLocation>? = nil) {
    self.children = children
    self.sourceRange = sourceRange
  }

  /// Returns a new node equivalent to the receiver, but whose children have been replaced with the
  /// given list of nodes.
  ///
  /// - Parameter children: The new list of children.
  /// - Returns: The new node.
  public func replacingChildren(_ children: [BlockContent]) -> BlockQuoteNode {
    return BlockQuoteNode(children: children, sourceRange: sourceRange)
  }

  /// Returns a new node equivalent to the receiver, but whose source range has been replaced with
  /// the given value.
  ///
  /// - Parameter sourceRange: The new source range.
  /// - Returns: The new node.
  public func replacingSourceRange(_ sourceRange: Range<SourceLocation>?) -> BlockQuoteNode {
    return BlockQuoteNode(children: children, sourceRange: sourceRange)
  }
}
