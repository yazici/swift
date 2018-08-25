/// A Markdown node that represents inline content; that is, content that only takes up as much
/// width as necessary and is laid out on the same line as sibling content (or is line-wrapped) when
/// rendered.
///
/// Examples of inline content include text, hyperlinks, and images.
///
/// At this time, the `InlineContent` protocol does not add any members of its own over what is
/// already required by `MarkdownNode`. Instead, it is used as a means of enforcing containment
/// relationships between nodes in the AST.
public protocol InlineContent: MarkdownNode {}
