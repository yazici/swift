#if os(Linux)
import CommonMarkTests
import SwiftFormatRulesTests
import XCTest

XCTMain([
  ColonWhitespaceTests.allTests,
  DoNotUseSemicolonsTests.allTests,
  MultiLineTrailingCommasTests.allTests,
  NoParensAroundConditionsTests.allTests,
  UseEnumForNamespacingTests.allTests,
  AvoidInitializersForLiteralsTests.allTests,
  CollectionLiteralWhitespaceTests.allTests,
  NoVoidReturnOnFunctionSignatureTests.allTests,
  OneVariableDeclarationPerLineTests.allTests,
  UseSingleLinePropertyGetterTests.allTests,
  UseWhereClausesInForLoopsTests.allTests,
  OpenBraceWhitespaceTests.allTests,
  CloseBraceWhitespaceTests.allTests,
  AlwaysUseLowerCamelCaseTests.allTests,
  CommonMarkTests.XCTestManifests.allTests,
].joined())
#endif
