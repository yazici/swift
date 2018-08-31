/// A block element that represents a horizontal rule.
public struct HorizontalRuleNode: BlockContent {

  public let sourceRange: Range<SourceLocation>?

  public var primitiveRepresentation: PrimitiveNode { return .horizontalRule(self) }

  /// Creates a new horizontal rule node.
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
  public func replacingSourceRange(_ sourceRange: Range<SourceLocation>?) -> HorizontalRuleNode {
    return HorizontalRuleNode(sourceRange: sourceRange)
  }
}
