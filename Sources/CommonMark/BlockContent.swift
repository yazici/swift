/// A Markdown node that represents block content; that is, content that occupies the full width of
/// the viewport when rendered.
///
/// Examples of block content include paragraphs, block quotes, and code blocks.
///
/// At this time, the `BlockContent` protocol does not add any members of its own over what is
/// already required by `MarkdownNode`. Instead, it is used as a means of enforcing containment
/// relationships between nodes in the AST.
public protocol BlockContent: MarkdownNode {}
