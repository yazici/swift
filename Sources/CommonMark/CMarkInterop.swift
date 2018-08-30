import CCommonMark
import Foundation

/// Creates a new Swift value corresponding to the given node.
///
/// This function walks the tree, creating the equivalent Swift tree for the given node and all of
/// its children recursively.
///
/// - Parameter cNode: The C pointer of a node.
/// - Returns: A Swift value corresponding to the tree rooted at the given node.
fileprivate func makeNode(from cNode: OpaquePointer) -> MarkdownNode {
  let sourceRange = makeSourceRange(for: cNode)
  let type = cmark_node_get_type(cNode)

  let node: MarkdownNode
  switch type {
  case CMARK_NODE_BLOCK_QUOTE:
    node = BlockQuoteNode(
      children: makeNodes(fromChildrenOf: cNode) as! [BlockContent],
      sourceRange: sourceRange)
  case CMARK_NODE_CODE:
    node = InlineCodeNode(
      literalContent: String(cString: cmark_node_get_literal(cNode)),
      sourceRange: sourceRange)
  case CMARK_NODE_CODE_BLOCK:
    node = CodeBlockNode(
      literalContent: String(cString: cmark_node_get_literal(cNode)),
      fenceText: String(cString: cmark_node_get_fence_info(cNode)),
      sourceRange: sourceRange)
  case CMARK_NODE_EMPH:
    node = EmphasisNode(
      children: makeNodes(fromChildrenOf: cNode) as! [InlineContent],
      sourceRange: sourceRange)
  case CMARK_NODE_HEADER:
    node = HeaderNode(
      level: HeaderNode.Level(rawValue: numericCast(cmark_node_get_header_level(cNode)))!,
      children: makeNodes(fromChildrenOf: cNode) as! [InlineContent],
      sourceRange: sourceRange)
  case CMARK_NODE_HRULE:
    node = HorizontalRuleNode(sourceRange: sourceRange)
  case CMARK_NODE_HTML:
    node = HTMLBlockNode(
      literalContent: String(cString: cmark_node_get_literal(cNode)),
      sourceRange: sourceRange)
  case CMARK_NODE_IMAGE:
    node = ImageNode(
      url: URL(string: String(cString: cmark_node_get_url(cNode))),
      title: String(cString: cmark_node_get_title(cNode)),
      children: makeNodes(fromChildrenOf: cNode) as! [InlineContent],
      sourceRange: sourceRange)
  case CMARK_NODE_INLINE_HTML:
    node = InlineHTMLNode(
      literalContent: String(cString: cmark_node_get_literal(cNode)),
      sourceRange: sourceRange)
  case CMARK_NODE_ITEM:
    node = ListItemNode(
      children: makeNodes(fromChildrenOf: cNode) as! [BlockContent],
      sourceRange: sourceRange)
  case CMARK_NODE_LINEBREAK:
    node = LineBreakNode(sourceRange: sourceRange)
  case CMARK_NODE_LINK:
    node = LinkNode(
      url: URL(string: String(cString: cmark_node_get_url(cNode))),
      title: String(cString: cmark_node_get_title(cNode)),
      children: makeNodes(fromChildrenOf: cNode) as! [InlineContent],
      sourceRange: sourceRange)
  case CMARK_NODE_LIST:
    let cListType = cmark_node_get_list_type(cNode)
    let listType: ListNode.ListType
    if cListType == CMARK_BULLET_LIST {
      listType = .bulleted
    } else {
      let cDelimiter = cmark_node_get_list_delim(cNode)
      listType = .ordered(
        delimiter: ListNode.Delimiter(cDelimiter),
        startingNumber: numericCast(cmark_node_get_list_start(cNode)))
    }
    node = ListNode(
      listType: listType,
      items: makeNodes(fromChildrenOf: cNode) as! [ListItemNode],
      isTight: cmark_node_get_list_tight(cNode) != 0,
      sourceRange: sourceRange)
  case CMARK_NODE_PARAGRAPH:
    node = ParagraphNode(
      children: makeNodes(fromChildrenOf: cNode) as! [InlineContent],
      sourceRange: sourceRange)
  case CMARK_NODE_SOFTBREAK:
    node = SoftBreakNode(sourceRange: sourceRange)
  case CMARK_NODE_STRONG:
    node = StrongNode(
      children: makeNodes(fromChildrenOf: cNode) as! [InlineContent],
      sourceRange: sourceRange)
  case CMARK_NODE_TEXT:
    node = TextNode(
      literalContent: String(cString: cmark_node_get_literal(cNode)),
      sourceRange: sourceRange)
  default:
    fatalError("Unexpected node type \(type) encountered")
  }

  return node
}

/// Returns an array of Swift values that are children of the given C node pointer.
///
/// - Parameter cNode: The C pointer of a node.
/// - Returns: An array of Swift values representing the children of the given node.
func makeNodes(fromChildrenOf cNode: OpaquePointer) -> [MarkdownNode] {
  var children = [MarkdownNode]()
  var cChildOrNil = cmark_node_first_child(cNode)
  while let cChild = cChildOrNil {
    children.append(makeNode(from: cChild))
    cChildOrNil = cmark_node_next(cChild)
  }
  return children
}

/// Returns a new source range equal to the start and end locations of the given node pointer.
///
/// - Parameter cNode: The C pointer of a node.
/// - Returns: The source range of the given node.
func makeSourceRange(for cNode: OpaquePointer) -> Range<SourceLocation> {
  return SourceLocation(
    line: numericCast(cmark_node_get_start_line(cNode)),
    column: numericCast(cmark_node_get_start_column(cNode))
  )..<SourceLocation(
    line: numericCast(cmark_node_get_end_line(cNode)),
    column: numericCast(cmark_node_get_end_column(cNode))
  )
}

extension ListNode.Delimiter {

  /// Creates a delimiter equivalent to the given underlying C value.
  ///
  /// - Parameter cDelim: The underlying C value from which the delimiter should be created.
  fileprivate init(_ cDelim: cmark_delim_type) {
    switch cDelim {
    case CMARK_PERIOD_DELIM: self = .period
    case CMARK_PAREN_DELIM: self = .parenthesis
    default: fatalError("Unexpected list delimiter \(cDelim)")
    }
  }
}
