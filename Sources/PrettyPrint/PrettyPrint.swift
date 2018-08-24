import Configuration
import Core
import SwiftSyntax

#if os(Linux)
import Glibc
#else
import Darwin
#endif

// TODO(harlan): Comment this whole file.

// Characters used in debug mode to mark breaks, groups, and other points of interest.
fileprivate let spaceMarker = "\u{00B7}"
fileprivate let breakMarker = "\u{23CE}"
fileprivate let openGroupMarker = "\u{27EC}"
fileprivate let closeGroupMarker = "\u{27ED}"

/// PrettyPrinter takes a Syntax node and outputs a well-formatted, reindented reproduction of the
/// code to stdout.
public class PrettyPrinter {
  private let configuration: Configuration
  private var stream: [Token]
  private var tokens = [Token]()
  private var bufferIndent = [Indent]()
  private var outputIndent = [Indent]()
  private var forceWrapping = [Bool]()
  private var lineLength = 0
  private var maxLineLength: Int

  private var requiresIndent = false

  /// If true, the pretty printer will output control characters that indicate where groups and
  /// breaks occur in the formatted output.
  private var isDebugMode: Bool

  /// The current index (0..<6) of the color to be used for the next color group.
  private var currentDebugGroupMarkerColor = 0

  /// We cycle through ANSI colors 31...36 for group brackets.
  private let groupMarkerColorCount = 6

  /// The ANSI color code string for the current group color (used in debug mode).
  private var currentGroupColorString: String {
    return Ansi.color(currentDebugGroupMarkerColor + 1)
  }

  /// Creates a new PrettyPrinter with the provided formatting configuration.
  ///
  /// - Parameters:
  ///   - configuration: The configuration used to decide whitespace or breaking behavior.
  ///   - node: The node to be pretty printed.
  public init(configuration: Configuration, node: Syntax, isDebugMode: Bool) {
    self.configuration = configuration
    self.stream = node.makeTokenStream(configuration: configuration)
    self.maxLineLength = configuration.lineLength
    self.isDebugMode = isDebugMode
  }

  func write<S: StringProtocol>(_ str: S) {
    print(str, terminator: "")
  }

  func adjustLineLength(_ token: Token) {
    if case .newlines = token {
      lineLength = 0
    } else {
      lineLength += token.columns
    }
  }

  func appendToken(_ token: Token) {
    adjustLineLength(token)
    tokens.append(token)
  }

  func addToken(_ token: Token) {
    if case .newlines = token {
      appendToken(token)
      flush(forceWrapped: false)
      return
    }

    if lineLength + token.columns > maxLineLength {
      flush(forceWrapped: true)
      if case .break(.inconsistent, _) = token {
        appendToken(.newline)
      } else {
        appendToken(token)
      }
    } else {
      appendToken(token)
    }
  }

  public func prettyPrint() {
    for token in stream {
      switch token {
      case .open(let i):
        addToken(token)
        addIndent(i)
      case .close:
        addToken(token)
        removeIndent()
      default:
        addToken(token)
      }
    }
    addToken(.newline)
    flush(forceWrapped: false)
  }

  func recomputeMaxLength() {
    maxLineLength = configuration.lineLength - bufferIndent.length(in: configuration)
  }

  func addIndent(_ level: Indent) {
    bufferIndent.append(level)
    recomputeMaxLength()
  }

  func removeIndent() {
    bufferIndent.removeLast()
    recomputeMaxLength()
  }

  func writeNewlines(_ count: Int = 1) {
    write(String(repeating: "\n", count: count))
    requiresIndent = true
  }

  func writeIndent() {
    if requiresIndent {
      write(outputIndent.indentation())
    }
    requiresIndent = false
  }

  func flush(forceWrapped: Bool) {
    let endOfFlushBuffer: Int
    let mostRecentOpen = tokens.lastIndex(where: { $0.isOpen })
    if forceWrapped, let openIdx = mostRecentOpen {
      endOfFlushBuffer = openIdx
    } else {
      endOfFlushBuffer = tokens.count
    }
    for tok in tokens[0..<endOfFlushBuffer] {
      switch tok {
      case .comment(let comment, let hasTrailingSpace):
        let lines = comment.wordWrap(lineLength: maxLineLength - lineLength)
        for (offset, line) in lines.enumerated() {
          if requiresIndent {
            // This comment is pretty far nested, and will pose a problem once we need to keep 80 columns. In fact, this is too long for even 100 columns.
            write(outputIndent.indentation())
          }
          write(line)
          if offset < lines.count - 1 {
            write("\n")
          }
        }
        requiresIndent = false
        if hasTrailingSpace {
          writeSpaces(1)
        }
      case .newlines(let n):
        writeNewlines(n)
      case .syntax(let tok):
        writeIndent()
        if tok.leadingTrivia.hasBackticks {
          write("`")
        }
        write(tok.text)
        if tok.trailingTrivia.hasBackticks {
          write("`")
        }
        if tok.trailingTrivia.hasSpaces {
          writeSpaces(1)
        }
      case .break(let style, let spaces):
        if isDebugMode { writeBreakDebugMarker(style: style) }

        if let wrap = forceWrapping.last, wrap, style == .consistent {
          writeNewlines()
        } else if spaces > 0 {
          writeSpaces(spaces)
        }
      case .open(let indent):
        if isDebugMode { writeOpenGroupDebugMarker() }
        outputIndent.append(indent)
      case .close:
        if isDebugMode { writeCloseGroupDebugMarker() }
        outputIndent.removeLast()
        if !forceWrapping.isEmpty {
          forceWrapping.removeLast()
        }
      }
    }
    tokens.removeSubrange(0..<endOfFlushBuffer)
    if mostRecentOpen != nil {
      forceWrapping.append(forceWrapped)
      lineLength = 0
      tokens.forEach(adjustLineLength)
    }
  }

  /// Writes a consistent or inconsistent break marker in debug mode.
  ///
  /// Breaks are indicated with the Unicode "RETURN SYMBOL" (⏎). Consistent breaks will be displayed
  /// in green and inconsistent breaks in yellow.
  ///
  /// - Parameter style: The break style to display.
  private func writeBreakDebugMarker(style: BreakStyle) {
    let breakColor: String
    switch style {
    case .consistent: breakColor = Ansi.green
    case .inconsistent: breakColor = Ansi.yellow
    }
    write(Ansi.bold)
    write(breakColor)
    write(breakMarker)
    write(Ansi.reset)
  }

  /// Writes a tortoise shell bracket indicating the beginning of a token group.
  ///
  /// Group markers are cycled through six different colors to make it easier to identify adjacent
  /// and nested groups.
  private func writeOpenGroupDebugMarker() {
    write(Ansi.bold)
    write(currentGroupColorString)
    write(openGroupMarker)
    write(Ansi.reset)
    currentDebugGroupMarkerColor = (currentDebugGroupMarkerColor + 1) % groupMarkerColorCount
  }

  /// Writes a tortoise shell bracket indicating the end of a token group.
  ///
  /// Group markers are cycled through six different colors to make it easier to identify adjacent
  /// and nested groups.
  private func writeCloseGroupDebugMarker() {
    currentDebugGroupMarkerColor = currentDebugGroupMarkerColor - 1
    if currentDebugGroupMarkerColor < 0 {
      currentDebugGroupMarkerColor = groupMarkerColorCount - 1
    }
    write(Ansi.bold)
    write(currentGroupColorString)
    write(closeGroupMarker)
    write(Ansi.reset)
  }

  /// Writes the given number of spaces to the output.
  ///
  /// If debug mode is enabled, spaces are rendered as gray Unicode MIDDLE DOT characters.
  private func writeSpaces(_ count: Int) {
    if isDebugMode {
      write(Ansi.brightBlack)
      write(String(repeating: spaceMarker, count: count))
      write(Ansi.reset)
    } else {
      if count == 1 {
        write(" ")
      } else {
        write(String(repeating: " ", count: count))
      }
    }
  }
}

/// Convenience properties/functions to access ANSI color code strings, respecting whether or not
/// output is being written to a terminal.
enum Ansi {

  /// True if stdout is a terminal (as opposed to a pipe or a redirection).
  static private var isTerminal: Bool { return isatty(1) != 0 }

  /// The ANSI color code string that makes subsequent text bold.
  static var bold: String { return isTerminal ? "\u{001b}[1m" : "" }

  /// The ANSI color code string that makes subsequent text reset to normal appearance.
  static var reset: String { return isTerminal ? "\u{001b}[0m" : "" }

  /// The ANSI color code string that makes subsequent text bright black.
  static var brightBlack: String { return "\u{001b}[30;1m" }

  /// The ANSI color code string that makes subsequent text green.
  static var green: String { return color(2) }

  /// The ANSI color code string that makes subsequent text yellow.
  static var yellow: String { return color(3) }

  /// The ANSI color code string that makes subsequent text render in the given color.
  ///
  /// The number 30 is added to the given index to determine the actual color code.
  static func color(_ index: Int) -> String { return isTerminal ? "\u{001b}[\(30 + index)m" : "" }
}
