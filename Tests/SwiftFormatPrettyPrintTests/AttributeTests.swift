public class AttributeTests: PrettyPrintTestCase {
  public func testAttributeParamSpacing() {
    let input =
      """
      @available
      @available(iOS 9.0, *)
      @available(*, unavailable, renamed: "MyRenamedProtocol")
      @available(iOS 10.0, macOS 10.12, *)
      """

    let expected =
      """
      @available
      @available(iOS 9.0, *)
      @available(*, unavailable, renamed: "MyRenamedProtocol")
      @available(iOS 10.0, macOS 10.12, *)


      """

    // Do not wrap attributes
    assertPrettyPrintEqual(input: input, expected: expected, linelength: 5)
  }
}
