import Configuration
import Core
import SwiftSyntax
import XCTest

@testable import PrettyPrint

let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())

extension SourceFileSyntax {
  static func parse(_ text: String) throws -> SourceFileSyntax {
    let tmpFile = tmpDir
      .appendingPathComponent(UUID().uuidString)
      .appendingPathExtension("swift")
    let fm = FileManager.default
    if fm.fileExists(atPath: tmpFile.path) {
      try fm.removeItem(atPath: tmpFile.path)
    }
    fm.createFile(atPath: tmpFile.path, contents: text.data(using: .utf8)!)
    let source = try self.parse(tmpFile)
    try fm.removeItem(atPath: tmpFile.path)
    return source
  }
}

public class VariableDeclarationTests: XCTestCase {
  public func testLineLength30() {
    let config = Configuration()
    config.lineLength = 30

    let context = Context(
      configuration: config,
      diagnosticEngine: nil,
      fileURL: URL(fileURLWithPath: "/tmp/test.swift")
    )

    let input =
      """
      let x = firstVariable + secondVariable / thirdVariable + fourthVariable
      let y: Int = anotherVar + moreVar
      let (w, z, s): (Int, Double, Bool) = firstTuple + secondTuple
      """

    let expected =
      """
      let x = firstVariable +
        secondVariable /
        thirdVariable +
        fourthVariable
      let y: Int = anotherVar +
        moreVar
      let (w, z, s):
        (Int, Double, Bool) =
        firstTuple + secondTuple

      """

    do {
      let syntax = try SourceFileSyntax.parse(input)

      let printer = PrettyPrinter(
        configuration: context.configuration,
        node: syntax,
        isDebugMode: false
      )
      let output = printer.prettyPrint()
      XCTAssertEqual(expected, output)
    } catch {
      fatalError("\(error)")
    }
  }
}
