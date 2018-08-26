import Foundation

/// An inline element that represents a hyperlink.
public struct LinkNode: InlineContent {

  /// The URL to which the link should navigate.
  ///
  /// The value of this property will be nil if the link has no URL set, or if the URL string in a
  /// parsed document was a value that Foundation's `URL` could not parse.
  public let url: URL?

  /// The title text associated with the link, if any.
  ///
  /// When rendered to HTML, the title is used as the `title` attribute of the link, which browsers
  /// typically render as a tooltip when the user hovers over it.
  public let title: String

  /// The children of the receiver.
  ///
  /// The children of a link node are the content that is rendered inside it.
  public let children: [InlineContent]

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new link node.
  ///
  /// - Parameters:
  ///   - url: The URL to which the link should navigate.
  ///   - title: The title text associated with the link, if any.
  ///   - children: Inline content nodes that are children of the new node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(
    url: URL?,
    title: String = "",
    children: [InlineContent] = [],
    sourceRange: Range<SourceLocation>? = nil
  ) {
    self.url = url
    self.title = title
    self.children = children
    self.sourceRange = sourceRange
  }
}
