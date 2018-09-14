public class FunctionDeclTests: PrettyPrintTestCase {
  public func testBasicFunctionDeclarations() {
    let input =
      """
      func myFun(var1: Int, var2: Double) {
        print("Hello World")
      }
      func reallyLongName(var1: Int, var2: Double, var3: Bool) {
        print("Hello World")
      }
      """

    let expected =
      """
      func myFun(var1: Int, var2: Double) {
        print("Hello World")
      }
      func reallyLongName(
        var1: Int,
        var2: Double,
        var3: Bool
      ) {
        print("Hello World")
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 50)
  }

  public func testFunctionDeclReturns() {
    let input =
      """
      func myFun(var1: Int, var2: Double) -> Double {
        print("Hello World")
        return 1.0
      }
      func reallyLongName(var1: Int, var2: Double, var3: Bool) -> Double {
        print("Hello World")
        return 1.0
      }
      """

    let expected =
      """
      func myFun(var1: Int, var2: Double) -> Double {
        print("Hello World")
        return 1.0
      }
      func reallyLongName(
        var1: Int,
        var2: Double,
        var3: Bool
      ) -> Double {
        print("Hello World")
        return 1.0
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 50)
  }

  public func testFunctionGenericParameters() {
    let input =
    """
    func myFun<S, T>(var1: S, var2: T) {
      print("Hello World")
    }
    """

    let expected =
    """
    func myFun<S, T>(var1: S, var2: T) {
      print("Hello World")
    }

    """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 40)
  }
}
