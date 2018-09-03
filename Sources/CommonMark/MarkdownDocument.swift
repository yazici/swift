import CCommonMark

/// A node that represents the document root.
public struct MarkdownDocument: MarkdownNode {

  /// The children of the receiver.
  public let children: [BlockContent]

  public let sourceRange: Range<SourceLocation>?

  public var primitiveRepresentation: PrimitiveNode { return .document(self) }

  /// Creates a new Markdown document.
  ///
  /// - Parameters:
  ///   - children: Block content nodes that are children of the new node.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(children: [BlockContent], sourceRange: Range<SourceLocation>? = nil) {
    self.children = children
    self.sourceRange = sourceRange
  }

  /// Creates a Markdown document by parsing the given text.
  ///
  /// - Parameter text: The Markdown text that should be parsed.
  public init(byParsing text: String) {
    guard let cDocument = cmark_parse_document(text, text.utf8.count, 0) else {
      fatalError("cmark_parse_document unexpectedly returned nil")
    }
    self.init(
      children: makeNodes(fromChildrenOf: cDocument) as! [BlockContent],
      sourceRange: makeSourceRange(for: cDocument)
    )
  }

  /// Returns a new node equivalent to the receiver, but whose children have been replaced with the
  /// given list of nodes.
  ///
  /// - Parameter children: The new list of children.
  /// - Returns: The new node.
  public func replacingChildren(_ children: [BlockContent]) -> MarkdownDocument {
    return MarkdownDocument(children: children, sourceRange: sourceRange)
  }

  /// Returns a new node equivalent to the receiver, but whose source range has been replaced with
  /// the given value.
  ///
  /// - Parameter sourceRange: The new source range.
  /// - Returns: The new node.
  public func replacingSourceRange(_ sourceRange: Range<SourceLocation>?) -> MarkdownDocument {
    return MarkdownDocument(children: children, sourceRange: sourceRange)
  }

  /// Returns a string that contains the content of the Markdown document rendered using the given
  /// renderer.
  ///
  /// - Parameters:
  ///   - renderer: A value from `MarkdownRenderer` that indicates what output format the document
  ///     should be rendered in.
  ///   - options: Additional options that control the renderers output; empty by default.
  /// - Returns: A string containing the rendered content of the Markdown document.
  public func string(
    renderedUsing renderer: MarkdownRenderer,
    options: MarkdownRenderer.Options = []
  ) -> String {
    let rawOptions = options.rawValue
    let cNode = primitiveRepresentation.makeCNode()

    let cString: UnsafeMutablePointer<Int8>
    switch renderer {
    case .xml: cString = cmark_render_xml(cNode, rawOptions)
    case .html: cString = cmark_render_html(cNode, rawOptions)
    case .manPage(let width): cString = cmark_render_man(cNode, rawOptions, numericCast(width))
    case .commonMark(let width):
      cString = cmark_render_commonmark(cNode, rawOptions, numericCast(width))
    case .latex(let width): cString = cmark_render_latex(cNode, rawOptions, numericCast(width))
    }

    return String(cString: cString)
  }
}
