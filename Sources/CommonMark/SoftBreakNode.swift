/// An inline element that represents a soft break.
public struct SoftBreakNode: InlineContent {

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new soft break node.
  ///
  /// - Parameter sourceRange: The source range from which the node was parsed, if known.
  public init(sourceRange: Range<SourceLocation>? = nil) {
    self.sourceRange = sourceRange
  }
}
