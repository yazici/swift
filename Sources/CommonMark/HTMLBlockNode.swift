/// A block element that represents HTML markup that is directly embedded in the document.
public struct HTMLBlockNode: BlockContent {

  /// The literal HTML content of the node.
  public let literalContent: String

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new empty HTML block node.
  ///
  /// - Parameters:
  ///   - literalContent: The literal HTML content of the node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(literalContent: String, sourceRange: Range<SourceLocation>? = nil) {
    self.literalContent = literalContent
    self.sourceRange = sourceRange
  }
}
