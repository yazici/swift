public class FunctionCallTests: PrettyPrintTestCase {
  public func testBasicFunctionCalls() {
    let input =
      """
      let a = myFunc()
      let a = myFunc(var1: 123, var2: "abc")
      let a = myFunc(var1: 123, var2: "abc", var3: Bool, var4: (1, 2, 3))
      let a = myFunc(var1, var2, var3)
      let a = myFunc(var1, var2, var3, var4, var5, var6)
      let a = myFunc(var1: 123, var2: someFun(var1: "abc", var2: 123, var3: Bool, var4: 1.23))
      """

    let expected =
      """
      let a = myFunc()
      let a = myFunc(var1: 123, var2: "abc")
      let a = myFunc(
        var1: 123,
        var2: "abc",
        var3: Bool,
        var4: (1, 2, 3)
      )
      let a = myFunc(var1, var2, var3)
      let a = myFunc(
        var1,
        var2,
        var3,
        var4,
        var5,
        var6
      )
      let a = myFunc(
        var1: 123,
        var2: someFun(
          var1: "abc",
          var2: 123,
          var3: Bool,
          var4: 1.23
        )
      )

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 45)
  }
}
