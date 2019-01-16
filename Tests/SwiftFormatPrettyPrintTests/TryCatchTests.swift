public class TryCatchTests: PrettyPrintTestCase {
  public func testBasicTries() {
    let input =
      """
      let a = try possiblyFailingFunc()
      let a = try? possiblyFailingFunc()
      let a = try! possiblyFailingFunc()
      """

    let expected =
      """
      let a = try possiblyFailingFunc()
      let a = try? possiblyFailingFunc()
      let a = try! possiblyFailingFunc()

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 40)
  }

  public func testDoTryCatch() {
    let input =
      """
      do { foo() } catch { bar() }

      do {
        try thisFuncMightFail()
      } catch error1 {
        print("Nope")
      }

      do {
        try thisFuncMightFail()
      } catch error1 {
        print("Nope")
      } catch error2(let someVar) {
        print(someVar)
        print("Don't do it!")
      }

      do {
        try thisFuncMightFail()
      } catch is ABadError{
        print("Nope")
      }
      """

    let expected =
      """
      do { foo() } catch { bar() }

      do { try thisFuncMightFail() }
      catch error1 { print("Nope") }

      do { try thisFuncMightFail() }
      catch error1 { print("Nope") }
      catch error2(let someVar) {
        print(someVar)
        print("Don't do it!")
      }

      do { try thisFuncMightFail() }
      catch is ABadError { print("Nope") }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 40)
  }

  public func testCatchWhere() {
    let input =
      """
      do {
        try thisFuncMightFail()
      } catch error1 where error1 is ErrorType {
        print("Nope")
      }

      do {
        try thisFuncMightFail()
      } catch error1 where error1 is LongerErrorType {
        print("Nope")
      }
      """

    let expected =
      """
      do { try thisFuncMightFail() }
      catch error1 where error1 is ErrorType {
        print("Nope")
      }

      do { try thisFuncMightFail() }
      catch error1
      where error1 is LongerErrorType
      { print("Nope") }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 45)
  }
}
