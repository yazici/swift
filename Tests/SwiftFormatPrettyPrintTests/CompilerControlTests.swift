public class CompilerControlTests: PrettyPrintTestCase {
  public func testConditionalCompilation() {
    let input =
      """
      #if swift(>=4.0)
      print("Stuff")
      #endif
      #if swift(>=4.0)
      print("Stuff")
      #elseif compiler(>=3.0)
      print("More Stuff")
      print("Another Line")
      #endif
      """

    let expected =
      """
      #if swift(>=4.0)
      print("Stuff")
      #endif
      #if swift(>=4.0)
      print("Stuff")
      #elseif compiler(>=3.0)
      print("More Stuff")
      print("Another Line")
      #endif

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 45)
  }
}
