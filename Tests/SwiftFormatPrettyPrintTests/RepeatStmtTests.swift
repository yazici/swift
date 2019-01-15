public class RepeatStmtTests: PrettyPrintTestCase {
  public func testBasicRepeatTests() {
    let input =
      """
      repeat {} while x

      repeat { f() } while x

      repeat { foo() } while longcondition

      repeat {
        let a = 123
        var b = "abc"
      } while condition

      repeat {
        let a = 123
        var b = "abc"
      } while condition && condition2
      """

    let expected =
      """
      repeat {} while x

      repeat { f() } while x

      repeat { foo() }
      while longcondition

      repeat {
        let a = 123
        var b = "abc"
      }
      while condition

      repeat {
        let a = 123
        var b = "abc"
      }
      while condition &&
        condition2

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 25)
  }
}
