public class DeinitializerDeclTests: PrettyPrintTestCase {
  public func testBasicDeinitializerDeclarations() {
    let input =
      """
      struct Struct {
        deinit {
            print("Hello World")
            let a = 23
        }
        deinit {
            let a = 23
        }
        deinit { let a = "AAAA BBBB CCCC DDDD EEEE FFFF" }
      }
      """

    let expected =
      """
      struct Struct {
        deinit {
          print("Hello World")
          let a = 23
        }
        deinit { let a = 23 }
        deinit {
          let a = "AAAA BBBB CCCC DDDD EEEE FFFF"
        }
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 50)
  }

  public func testDeinitializerAttributes() {
    let input =
      """
      struct Struct {
        @objc deinit {
          let a = 123
          let b = "abc"
        }
        @objc @inlinable deinit {
          let a = 123
          let b = "abc"
        }
        @objc @available(swift 4.0) deinit {
          let a = 123
          let b = "abc"
        }
      }
      """

    let expected =
      """
      struct Struct {
        @objc deinit {
          let a = 123
          let b = "abc"
        }
        @objc
        @inlinable
        deinit {
          let a = 123
          let b = "abc"
        }
        @objc
        @available(swift 4.0)
        deinit {
          let a = 123
          let b = "abc"
        }
      }

      """

    assertPrettyPrintEqual(input: input, expected: expected, linelength: 25)
  }
}
