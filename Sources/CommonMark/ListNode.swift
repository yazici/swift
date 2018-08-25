/// A block element that represents a bulleted or numbered list.
public struct ListNode: BlockContent {

  /// Indicates the character that is used to separate the number of an ordered list item from the
  /// text of the item.
  public enum Delimiter {

    /// The number of the list item is followed by a period (e.g., `1.`).
    case period

    /// The number of the list item is followed by a closing parenthesis (e.g., `1)`).
    case parenthesis
  }

  /// The type of the list.
  public enum ListType {

    /// The list is a bulleted list.
    case bulleted

    /// The list is an ordered list with the given delimiter and starting number.
    case ordered(delimiter: Delimiter, startingNumber: Int)
  }

  /// The type of the list (bulleted or ordered).
  ///
  /// If the type of the list is `.ordered`, then the type's associated values convey the delimiter
  /// of the items and their starting number.
  public let listType: ListType

  /// The items in the list.
  public let items: [ListItemNode]

  /// Indicates whether or not the list is tight.
  ///
  /// The tightness of a list affects its rendering. In HTML, for example, child `ParagraphNode`s of
  /// a tight list's items are not wrapped in `<p>` tags, but they are in a loose list.
  public let isTight: Bool

  public let sourceRange: Range<SourceLocation>?

  /// Creates a new list node.
  ///
  /// - Parameters:
  ///   - listType: The type of the list (bulleted or ordered).
  ///   - items: The items in the list.
  ///   - isTight: Indicates whether or not the list is tight.
  ///   - sourceRange: The source range from which the node was parsed, if known.
  public init(
    listType: ListType,
    items: [ListItemNode],
    isTight: Bool = false,
    sourceRange: Range<SourceLocation>? = nil
  ) {
    self.listType = listType
    self.items = items
    self.isTight = isTight
    self.sourceRange = sourceRange
  }
}
