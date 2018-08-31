/// An inline element that represents HTML markup that is directly embedded in the document.
public struct InlineHTMLNode: InlineContent {

  /// The literal HTML content of the node.
  public let literalContent: String

  public let sourceRange: Range<SourceLocation>?

  public var primitiveRepresentation: PrimitiveNode { return .inlineHTML(self) }

  /// Creates a new inline HTML node.
  ///
  /// - Parameters:
  ///   - literalContent: The literal HTML content of the node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(literalContent: String, sourceRange: Range<SourceLocation>? = nil) {
    self.literalContent = literalContent
    self.sourceRange = sourceRange
  }

  /// Returns a new node equivalent to the receiver, but whose literal content has been replaced
  /// with the given string.
  ///
  /// - Parameter literalContent: The new literal content.
  /// - Returns: The new node.
  public func replacingLiteralContent(_ literalContent: String) -> InlineHTMLNode {
    return InlineHTMLNode(literalContent: literalContent, sourceRange: sourceRange)
  }

  /// Returns a new node equivalent to the receiver, but whose source range has been replaced with
  /// the given value.
  ///
  /// - Parameter sourceRange: The new source range.
  /// - Returns: The new node.
  public func replacingSourceRange(_ sourceRange: Range<SourceLocation>?) -> InlineHTMLNode {
    return InlineHTMLNode(literalContent: literalContent, sourceRange: sourceRange)
  }
}
