/// An inline element that represents a hard line break.
public struct LineBreakNode: InlineContent {

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new line break node.
  ///
  /// - Parameter sourceRange: The source range from which the node was parsed, if known.
  public init(sourceRange: Range<SourceLocation>? = nil) {
    self.sourceRange = sourceRange
  }

  /// Returns a new node equivalent to the receiver, but whose source range has been replaced with
  /// the given value.
  ///
  /// - Parameter sourceRange: The new source range.
  /// - Returns: The new node.
  public func replacingSourceRange(_ sourceRange: Range<SourceLocation>?) -> LineBreakNode {
    return LineBreakNode(sourceRange: sourceRange)
  }
}
