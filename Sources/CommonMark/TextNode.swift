/// An inline element that represents plain text.
public struct TextNode: InlineContent {

  /// The literal text content of the node.
  public let literalContent: String

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new text node.
  ///
  /// - Parameters:
  ///   - literalContent: The literal text content of the node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(literalContent: String, sourceRange: Range<SourceLocation>? = nil) {
    self.literalContent = literalContent
    self.sourceRange = sourceRange
  }
}
