/// An inline element that represents strong (i.e., bolded) text.
public struct StrongNode: InlineContent {

  /// The children of the receiver.
  public let children: [InlineContent]

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new strong text node.
  ///
  /// - Parameters:
  ///   - children: Inline content nodes that are children of the new node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(children: [InlineContent], sourceRange: Range<SourceLocation>? = nil) {
    self.children = children
    self.sourceRange = sourceRange
  }
}
