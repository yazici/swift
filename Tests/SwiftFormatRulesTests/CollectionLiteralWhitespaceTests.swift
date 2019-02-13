import Foundation
import XCTest
import SwiftSyntax

@testable import SwiftFormatRules

public class CollectionLiteralWhitespaceTests: DiagnosingTestCase {
  public func testInvalidCollectionLiteralWhitespace() {
    let input =
      """
      func a( x: Int ) {
        print( [ x ] )
        if ( x == 0 ) {
          var arr = [ Int ]()
          arr.append(x )
          print( arr)
        }
      }
      """

    performLint(CollectionLiteralWhitespace.self, input: input)

    let leftParen = SyntaxFactory.makeLeftParenToken()
    let rightParen = SyntaxFactory.makeRightParenToken()
    let leftSquare = SyntaxFactory.makeLeftSquareBracketToken()
    let rightSquare = SyntaxFactory.makeRightSquareBracketToken()

    // func a( x: Int ) {
    XCTAssertDiagnosed(.noSpacesAfter(leftParen))
    XCTAssertDiagnosed(.noSpacesBefore(rightParen))

    // print( [ x ] )
    XCTAssertDiagnosed(.noSpacesAfter(leftParen))
    XCTAssertDiagnosed(.noSpacesAfter(leftSquare))
    XCTAssertDiagnosed(.noSpacesBefore(rightSquare))
    XCTAssertDiagnosed(.noSpacesBefore(rightParen))

    // if ( x == 0 ) {
    XCTAssertDiagnosed(.noSpacesAfter(leftParen))
    XCTAssertDiagnosed(.noSpacesBefore(rightParen))

    // var arr = [ Int ]()
    XCTAssertDiagnosed(.noSpacesAfter(leftSquare))
    XCTAssertDiagnosed(.noSpacesBefore(rightSquare))

    // arr.append(x )
    XCTAssertDiagnosed(.noSpacesBefore(rightParen))

    // print( arr)
    XCTAssertDiagnosed(.noSpacesAfter(leftParen))
  }

#if !os(macOS)
  static let allTests = [
    CollectionLiteralWhitespaceTests.testInvalidCollectionLiteralWhitespace,
  ]
#endif
}
