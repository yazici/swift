public class AccessorTests: PrettyPrintTestCase {
  public func testBasicAccessors() {
    let input =
      """
      struct MyStruct {
        var memberValue: Int
        var someValue: Int {
          get { return memberValue + 2 }
          set(newValue) { memberValue = newValue }
        }
      }
      struct MyStruct {
        var memberValue: Int
        var someValue: Int {
          @objc get { return memberValue + 2 }
          @objc(isEnabled) set(newValue) { memberValue = newValue }
        }
      }
      struct MyStruct {
        var memberValue: Int
        var memberValue2: Int
        var someValue: Int {
          get {
            let A = 123
            return A
          }
          set(newValue) {
            memberValue = newValue
            memberValue2 = newValue / 2
          }
        }
      }
      struct MyStruct {
        var memberValue: Int
        var SomeValue: Int {
          return 123
        }
        var AnotherValue: Double {
          let out = 1.23
          return out
        }
      }
      """

    let expected =
      """
      struct MyStruct {
        var memberValue: Int
        var someValue: Int {
          get { return memberValue + 2 }
          set(newValue) { memberValue = newValue }
        }
      }
      struct MyStruct {
        var memberValue: Int
        var someValue: Int {
          @objc get { return memberValue + 2 }
          @objc(isEnabled)
          set(newValue) { memberValue = newValue }
        }
      }
      struct MyStruct {
        var memberValue: Int
        var memberValue2: Int
        var someValue: Int {
          get {
            let A = 123
            return A
          }
          set(newValue) {
            memberValue = newValue
            memberValue2 = newValue / 2
          }
        }
      }
      struct MyStruct {
        var memberValue: Int
        var SomeValue: Int { return 123 }
        var AnotherValue: Double {
          let out = 1.23
          return out
        }
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 45)
  }
}
