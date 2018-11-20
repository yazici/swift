public class TupleDeclTests: PrettyPrintTestCase {
  public func testBasicTuples() {
    let input =
      """
      let a = (1, 2, 3)
      let a: (Int, Int, Int) = (1, 2, 3)
      let a = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10)
      let a = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12)
      let a = (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12,)
      """

    let expected =
      """
      let a = (1, 2, 3)
      let a: (Int, Int, Int) = (1, 2, 3)
      let a = (
        1, 2, 3, 4, 5, 6, 7, 8, 9, 10
      )
      let a = (
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12
      )
      let a = (
        1,
        2,
        3,
        4,
        5,
        6,
        7,
        8,
        9,
        10,
        11,
        12,
      )

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 37)
  }
}
