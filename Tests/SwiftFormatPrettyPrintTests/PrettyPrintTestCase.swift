import SwiftFormatConfiguration
import SwiftFormatCore
import SwiftSyntax
import XCTest

@testable import SwiftFormatPrettyPrint

public class PrettyPrintTestCase: XCTestCase {
  public func assertPrettyPrintEqual(
    input: String,
    expected: String,
    linelength: Int,
    file: StaticString = #file,
    line: UInt = #line
  ) {
    let config = Configuration()
    config.lineLength = linelength

    let context = Context(
      configuration: config,
      diagnosticEngine: nil,
      fileURL: URL(fileURLWithPath: "/tmp/test.swift")
    )

    do {
      let syntax = try SyntaxTreeParser.parse(input)

      let printer = PrettyPrinter(
        configuration: context.configuration,
        node: syntax,
        isDebugMode: false,
        printTokenStream: false
      )
      let output = printer.prettyPrint()
      XCTAssertEqual(expected, output, file: file, line: line)
    } catch {
      fatalError("\(error)")
    }
  }
}
