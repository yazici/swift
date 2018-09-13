public class VariableDeclarationTests: PrettyPrintTestCase {
  public func testLineLength30() {

    let input =
      """
      let x = firstVariable + secondVariable / thirdVariable + fourthVariable
      let y: Int = anotherVar + moreVar
      let (w, z, s): (Int, Double, Bool) = firstTuple + secondTuple
      """

    let expected =
      """
      let x = firstVariable +
        secondVariable /
        thirdVariable +
        fourthVariable
      let y: Int = anotherVar +
        moreVar
      let (w, z, s):
        (Int, Double, Bool) =
        firstTuple + secondTuple

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 30)
  }
}
