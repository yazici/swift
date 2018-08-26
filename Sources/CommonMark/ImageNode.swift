import Foundation

/// An inline element that represents an image.
public struct ImageNode: InlineContent {

  /// The URL from which the image should be loaded.
  ///
  /// The value of this property will be nil if the image has no URL set, or if the URL string in a
  /// parsed document was a value that Foundation's `URL` could not parse.
  public let url: URL?

  /// The title text associated with the image, if any.
  ///
  /// When rendered to HTML, the title is used as the `title` attribute of the image, which browsers
  /// typically render as a tooltip when the user hovers over it.
  public let title: String

  /// The children of the receiver.
  ///
  /// The children of an image node can be used by renderers as an alternate representation if the
  /// client doesn't support images. For example, when rendered in HTML, the text of the child nodes
  /// is used as the `alt` tag of the `<img>` tag.
  public let children: [InlineContent]

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new image node.
  ///
  /// - Parameters:
  ///   - url: The URL from which the image should be loaded.
  ///   - title: The title text associated with the image, if any.
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
