import SwiftSyntax
import XCTest

@testable import SwiftFormatRules

public class ColonWhitespaceTests: DiagnosingTestCase {
  public func testInvalidColonWhitespace() {
    let input =
      """
      let v1: Int = 0
      let v2 : Int = 1
      let v3 :Int = 1
      let v4    \t: \t     Int = 1
      let v5: [Int: String] = [: ]
      let v6: [Int: String] = [23:  "twenty three"]
      """

    performLint(ColonWhitespace.self, input: input)

    // let v2 : Int = 1
    XCTAssertDiagnosed(.noSpacesBeforeColon)

    // let v3 :Int = 1
    XCTAssertDiagnosed(.noSpacesBeforeColon)
    XCTAssertDiagnosed(.addSpaceAfterColon)

    // let v4    \t: \t     Int = 1
    XCTAssertDiagnosed(.noSpacesBeforeColon)
    XCTAssertDiagnosed(.removeSpacesAfterColon(count: 6))

    // let v5: [Int: String] = [: ]
    XCTAssertDiagnosed(.noSpacesAfterColon)

    // let v6: [Int: String] = [23:  "twenty three"]
    XCTAssertDiagnosed(.removeSpacesAfterColon(count: 1))
  }

  #if !os(macOS)
  static let allTests = [
    ColonWhitespaceTests.testInvalidColonWhitespace,
  ]
  #endif
}
