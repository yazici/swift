/// A single location in source text as a line number and column number.
public struct SourceLocation {

  /// The 1-based line number of the location in the source text.
  public let line: Int

  /// The 1-based column number of the location in the source text.
  public let column: Int

  /// Creates a new source location with the given line and column numbers.
  ///
  /// - Parameters:
  ///   - line: The 1-based line number of the location in the source text.
  ///   - column: The 1-based column number of the location in the source text.
  public init(line: Int, column: Int) {
    self.line = line
    self.column = column
  }
}

extension SourceLocation: Comparable {

  public static func < (lhs: SourceLocation, rhs: SourceLocation) -> Bool {
    return lhs.line < rhs.line || (lhs.line == rhs.line && lhs.column < rhs.column)
  }
}

extension SourceLocation: Hashable {}
