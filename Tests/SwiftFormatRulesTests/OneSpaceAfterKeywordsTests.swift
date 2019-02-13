import SwiftSyntax
import XCTest

@testable import SwiftFormatRules

public class OneSpaceAfterKeywordsTests: DiagnosingTestCase {
  public func testInvalidOneSpaceAfterKeywordsTests() {
    let input =
      """
      let   v1 = "Test"
      var             values: Values
      func isIdentifier(_       tokKind: TokenKind) -> Bool {
        guard     let     first = v1.first else { return false }
        if case .identifier(_) = tokKind {
          return               true
        }
        return  false
      }
      """

    performLint(OneSpaceAfterKeywords.self, input: input)

    // let   v1 = "Test"
    XCTAssertDiagnosed(.removeSpacesAfterKeyword(2, "let"))

    // var             values: Values
    XCTAssertDiagnosed(.removeSpacesAfterKeyword(12, "var"))

    // func isIdentifier(_       tokKind: TokenKind) -> Bool {
    XCTAssertDiagnosed(.removeSpacesAfterKeyword(6, "_"))

    // guard     let     first = v1.first else { return false }
    XCTAssertDiagnosed(.removeSpacesAfterKeyword(4, "guard"))
    XCTAssertDiagnosed(.removeSpacesAfterKeyword(4, "let"))

    // return               true
    XCTAssertDiagnosed(.removeSpacesAfterKeyword(14, "return"))

    // return  false
    XCTAssertDiagnosed(.removeSpacesAfterKeyword(1, "return"))
  }
  
  #if !os(macOS)
  static let allTests = [
    OneSpaceAfterKeywordsTests.testInvalidOneSpaceAfterKeywordsTests,
    ]
  #endif
}
