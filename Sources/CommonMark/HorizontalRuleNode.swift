/// A block element that represents a horizontal rule.
public struct HorizontalRuleNode: BlockContent {

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new horizontal rule node.
  ///
  /// - Parameter sourceRange: The source range from which the node was parsed, if known.
  public init(sourceRange: Range<SourceLocation>? = nil) {
    self.sourceRange = sourceRange
  }
}
