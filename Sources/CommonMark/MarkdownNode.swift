/// A node in the AST representing a parsed Markdown document.
///
/// This protocol is refined by the more specific `BlockContent` and `InlineContent` protocols,
/// which help to enforce the containment relationship between the types of nodes in the AST.
public protocol MarkdownNode {}
