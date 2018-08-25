/// A block element that represents a section header.
public struct HeaderNode: BlockContent {

  /// The level of a header, which describes its position in the hierarchy of a document and the
  /// size at which the header is rendered.
  public enum Level: Int {
    case h1 = 1
    case h2 = 2
    case h3 = 3
    case h4 = 4
    case h5 = 5
    case h6 = 6
  }

  /// The level of the header.
  public let level: Level

  /// The children of the receiver.
  public let children: [InlineContent]

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new header node.
  ///
  /// - Parameters:
  ///   - level: The level of the header. If omitted, `.h1` is used.
  ///   - children: Inline content nodes that are children of the new node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(
    level: Level = .h1,
    children: [InlineContent],
    sourceRange: Range<SourceLocation>? = nil
  ) {
    self.level = level
    self.children = children
    self.sourceRange = sourceRange
  }
}
