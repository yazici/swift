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
  private let maxLineLength: Int
  private var tokens: [Token]
  private var spaceRemaining: Int

  private var lengths = [Int]()
  private var forceBreak = false // Do we need to force linebreaks?
  private var lastBreak = false // Did the last break token force a new line?
  private var indentStack = [Int]()

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
    self.tokens = node.makeTokenStream(configuration: configuration)
    self.maxLineLength = configuration.lineLength
    self.isDebugMode = isDebugMode
    self.spaceRemaining = self.maxLineLength
  }

  func write<S: StringProtocol>(_ str: S) {
    print(str, terminator: "")
  }

  private func printToken(token: Token, length: Int) {
    switch token {
    case .open(let breaktype):
      if lastBreak, case .consistent = breaktype {
        forceBreak = true
      }
      indentStack.append(spaceRemaining)

    case .close:
      forceBreak = false
      indentStack.removeLast()

    case .break(let offset, let size):
      if length > spaceRemaining || forceBreak {
        let stackValue = indentStack.last ?? maxLineLength
        spaceRemaining = stackValue - offset
        write("\n")
        write(String(repeating: " ", count: (maxLineLength - spaceRemaining)))
        lastBreak = true
      } else {
        write(String(repeating: " ", count: size))
        spaceRemaining -= size
        lastBreak = false
      }

    case .syntax(let syntaxToken):
      write(syntaxToken.text)
      spaceRemaining -= syntaxToken.text.count

    default: () // Skip the other token types for now
    }
  }

  public func prettyPrint() {
    var delimIndexStack = [Int]()
    var total = 0

    // Calculate token lengths
    for (i, token) in tokens.enumerated() {
      switch token {
      case .open:
        lengths.append(-total)
        delimIndexStack.append(i)

      case .close:
        lengths.append(0)

        guard let index = delimIndexStack.popLast() else {
          print("Bad index 1")
          return
        }
        lengths[index] += total

        if case .break = tokens[index] {
          guard let index = delimIndexStack.popLast() else {
            print("Bad index 2")
            return
          }
          lengths[index] += total
        }

      case .break(_, let size):
        if let index = delimIndexStack.last, case .break = tokens[index] {
          lengths[index] += total
          delimIndexStack.removeLast()
        }

        lengths.append(-total)
        delimIndexStack.append(i)
        total += size

      case .syntax(let syntaxToken):
        lengths.append(syntaxToken.text.count)
        total += syntaxToken.text.count

      default: ()
      }
    }

    if let index = delimIndexStack.popLast() {
      lengths[index] += total
    }

    for i in 0..<tokens.count {
      printToken(token: tokens[i], length: lengths[i])
    }
    write("\n")
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
