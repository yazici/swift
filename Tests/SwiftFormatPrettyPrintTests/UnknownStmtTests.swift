public class UnknownStmtTests: PrettyPrintTestCase {

  /// As SwiftSyntax is updated and becomes more complete, these tests could break since the syntax
  /// components might not be recognized as "unknown".
  public func testUnknownStmt() {
    let input =
      """
      if someCondition {
      if something, #available(OSX 10.12, *) {
      let a = 123
      let b = "abc"
      }
      }

      if someCondition {
            if something, #available(OSX 10.12, *) {
         let a = 123
      let b = "abc"
            }
      }

      if someCondition {
        if anotherCondition {
      if something, #available(OSX 10.12, *) {
        let a = 123
        let b = "abc"
      }
        }
      }

      if #available(OSX 10.12, *) {
        // Do stuff
      } else {
        let a = 123
        let b = "abc"
      }

      #if canImport(os)
        if #available(OSX 10.12, *) {
          // Do stuff
        } else {
          let a = 123
          let b = "abc"
        }
      #endif

      func myfun() {

        if #available(OSX 10.12, *) {

          let a = 123
        } else {
          // do stuff
        }
      }
      """

    let expected =
      """
      if someCondition {
        if something, #available(OSX 10.12, *) {
        let a = 123
        let b = "abc"
        }
      }

      if someCondition {
        if something, #available(OSX 10.12, *) {
        let a = 123
        let b = "abc"
        }
      }

      if someCondition {
        if anotherCondition {
          if something, #available(OSX 10.12, *) {
            let a = 123
            let b = "abc"
          }
        }
      }

      if #available(OSX 10.12, *) {
        // Do stuff
      } else {
        let a = 123
        let b = "abc"
      }

      #if canImport(os)
        if #available(OSX 10.12, *) {
          // Do stuff
        } else {
          let a = 123
          let b = "abc"
        }
      #endif

      func myfun() {

        if #available(OSX 10.12, *) {

          let a = 123
        } else {
          // do stuff
        }
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 45)
  }

  public func testUnknownStmtWithTrailingComment() {
    let input =
      """
      struct MyStruct {
        #if swift(>=4.2)
          // Do stuff here
        #endif  // trailing comment

        let someMemberVar: Int
      }
      """

    assertPrettyPrintEqual(input: input, expected: input + "\n", linelength: 45)
  }
}
