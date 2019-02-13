import SwiftSyntax
import XCTest

@testable import SwiftFormatRules

public class CommaWhitespaceTests: DiagnosingTestCase {
  public func testInvalidFuncCommaWhiteSpace() {
    let input =
      """
      func testComma(paramA: Bool,paramB: Bool ,paramC: Bool , paramD: Bool) -> Bool {

      if paramA,
         !paramB ,
         paramC   ,
         paramD {
       return true
         }
      return false
      }
      """

    performLint(CommaWhitespace.self, input: input)

    // func testComma...
    XCTAssertDiagnosed(.addSpaceAfterComma)
    XCTAssertDiagnosed(.noSpacesBeforeComma)
    XCTAssertDiagnosed(.addSpaceAfterComma)
    XCTAssertDiagnosed(.noSpacesBeforeComma)

    // if paramA...
    XCTAssertDiagnosed(.noSpacesBeforeComma)
    XCTAssertDiagnosed(.noSpacesBeforeComma)
  }
  
  public func testInvalidDeclCommaWhiteSpace() {
    let input = """
      let numA = [1,2,3]
      let numB = [1 ,2 ,3]
      let numC = [1 , 2 , 3]
      """

    performLint(CommaWhitespace.self, input: input)

    // let numA
    XCTAssertDiagnosed(.addSpaceAfterComma)
    XCTAssertDiagnosed(.addSpaceAfterComma)

    // let numB
    XCTAssertDiagnosed(.noSpacesBeforeComma)
    XCTAssertDiagnosed(.addSpaceAfterComma)
    XCTAssertDiagnosed(.noSpacesBeforeComma)
    XCTAssertDiagnosed(.addSpaceAfterComma)

    // let numC
    XCTAssertDiagnosed(.noSpacesBeforeComma)
    XCTAssertDiagnosed(.noSpacesBeforeComma)
  }
  
  #if !os(macOS)
  static let allTests = [
    CommaWhitespaceTests.testInvalidFuncCommaWhiteSpace,
    CommaWhitespaceTests.testInvalidDeclCommaWhiteSpace,
    ]
  #endif
}
