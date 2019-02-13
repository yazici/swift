import Foundation
import XCTest
import SwiftSyntax

@testable import SwiftFormatRules

public class CloseBraceWhitespaceTests: DiagnosingTestCase {
  public func testInvalidCloseBraceWhitespace() {
    let input =
      """
      func a()
      { print("hello")
        print("goodbye")}
      func b(){
      }
      func c() {}
      """

    performLint(CloseBraceWhitespace.self, input: input)
    XCTAssertDiagnosed(.lineBreakRequiredBeforeCloseBrace)
  }

#if !os(macOS)
  static let allTests = [
    CloseBraceWhitespaceTests.testInvalidCloseBraceWhitespace,
  ]
#endif
}
