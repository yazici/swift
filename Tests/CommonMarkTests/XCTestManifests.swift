import XCTest

#if !os(macOS)
public func allTests() -> [XCTestCaseEntry] {
  return [
    testCase(MarkdownDocumentTest.allTests),
    testCase(MarkdownRenderingTest.allTests),
  ]
}
#endif
