/// A node in the AST representing a parsed Markdown document.
///
/// This protocol is refined by the more specific `BlockContent` and `InlineContent` protocols,
/// which help to enforce the containment relationship between the types of nodes in the AST.
public protocol MarkdownNode {

  /// The range that the node occupies in the original source text, if known.
  ///
  /// The value of this property is provided by the parser when it parses Markdown source text. It
  /// can be nil for nodes created dynamically unless the caller provides a valid range at that
  /// time.
  var sourceRange: Range<SourceLocation>? { get }
}
