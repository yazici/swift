import SwiftSyntax
import XCTest

@testable import SwiftFormatRules

public class AvoidInitializersForLiteralsTests: DiagnosingTestCase {
  public func testInitializersForLiterals() {
    XCTAssertFormatting(
      AvoidInitializersForLiterals.self,
      input: """
             let v1 = UInt32(76)
             let v2 = UInt8(257)
             performFunction(x: Int16(54))
             performFunction(x: Int32(54))
             performFunction(x: Int64(54))
             let c = Character("s")
             if 3 > Int(2) || someCondition {}
             let a = Int(bitPattern: 123456)
             """,
      expected: """
                let v1 = 76 as UInt32
                let v2 = 257 as UInt8
                performFunction(x: 54 as Int16)
                performFunction(x: 54 as Int32)
                performFunction(x: 54 as Int64)
                let c = "s" as Character
                if 3 > 2 as Int || someCondition {}
                let a = Int(bitPattern: 123456)
                """)
  }

  #if !os(macOS)
  static let allTests = [
    AvoidInitializersForLiteralsTests.testInitializersForLiterals,
  ]
  #endif
}
