/// An inline element that represents a hard line break.
public struct LineBreakNode: InlineContent {

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new line break node.
  ///
  /// - Parameter sourceRange: The source range from which the node was parsed, if known.
  public init(sourceRange: Range<SourceLocation>? = nil) {
    self.sourceRange = sourceRange
  }
}
