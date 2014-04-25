// RUN: %target-run-simple-swift | FileCheck %s

// Regression test for <rdar://problem/16119895>.

struct Generic<T> {
  typealias Storage = HeapBufferStorage<Int,T>

  init() {
    buffer = HeapBuffer(Storage.self, 0, 0)
  }

  mutating func isUniquelyReferenced() -> Bool {
    return buffer.isUniquelyReferenced()
  }
  
  var buffer: HeapBuffer<Int, T>
}
func g0() {
  var x = Generic<Int>()
  // CHECK: true
  println(x.isUniquelyReferenced())
  // CHECK-NEXT: true
  println(x.buffer.isUniquelyReferenced())
}
g0()


struct NonGeneric {
  typealias T = Int
  typealias Storage = HeapBufferStorage<Int,T>

  init() {
    buffer = HeapBuffer(Storage.self, 0, 0)
  }

  mutating func isUniquelyReferenced() -> Bool {
    return buffer.isUniquelyReferenced()
  }
  
  var buffer: HeapBuffer<Int, T>
}
func g1() {
  var x = NonGeneric()
  // CHECK-NEXT: true
  println(x.isUniquelyReferenced())
  // CHECK-NEXT: true
  println(x.buffer.isUniquelyReferenced())
}
g1()
