import SwiftSyntax
import XCTest

@testable import SwiftFormatRules

public class CommentWhitespaceTest: DiagnosingTestCase {
  public func testInvalidCommentWhiteSpace() {
    let input = """
      let initialFactor = 2 //        Line comment of initialFactor.
      let finalFactor = 2//Line comment of finalFactor.

      //Lorem ipsum dolor sit amet, at nonumes adipisci sea, natum
      //       offendit vis ex. Audiam legendos expetenda ei quo, nonumes
      // msensibus eloquentiam ex vix.
      let fin = 3//        End of file.
      """

    performLint(CommentWhitespace.self, input: input)
    XCTAssertDiagnosed(.addSpacesBeforeLineComment(count: 1))
    XCTAssertDiagnosed(.addSpacesBeforeLineComment(count: 2))
    XCTAssertDiagnosed(.addSpacesBeforeLineComment(count: 2))
  }
  
  #if !os(macOS)
  static let allTests = [
    CommentWhitespaceTest.testInvalidCommentWhiteSpace,
  ]
  #endif
}
