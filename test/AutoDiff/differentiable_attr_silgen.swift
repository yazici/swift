// RUN: %target-swift-frontend -emit-silgen -enable-testing -verify %s | %FileCheck %s

//===----------------------------------------------------------------------===//
// Normal types
//===----------------------------------------------------------------------===//

@_silgen_name("foo")
@differentiable(vjp: dfoo)
public func foo(_ x: Float, _ y: Float) -> Float {
  return 1
}

// CHECK-LABEL: sil [differentiable source 0 wrt 0, 1 vjp @dfoo] @foo

@_silgen_name("dfoo")
public func dfoo(_ x: Float, _ y: Float) -> (Float, (Float) -> (Float, Float)) {
  return (foo(x, y), { _ in (1, 1) })
}

// CHECK-LABEL: sil @dfoo

//===----------------------------------------------------------------------===//
// Indirect returns
//===----------------------------------------------------------------------===//

@_silgen_name("foo_indir_ret")
@differentiable(vjp: dfoo_indir_ret)
public func foo_indir_ret<T: Differentiable>(_ x: Float, _ y: T) -> T {
  return y
}

// CHECK-LABEL: sil [differentiable source 0 wrt 0, 1 vjp @dfoo_indir_ret] @foo_indir_ret : $@convention(thin) <T where T : Differentiable> (Float, @in_guaranteed T) -> @out T {
// CHECK: bb0(%0 : @trivial $*T, %1 : @trivial $Float, %2 : @trivial $*T):

@_silgen_name("dfoo_indir_ret")
public func dfoo_indir_ret<T: Differentiable>(_ x: Float, _ y: T) -> (T, (T.CotangentVector) -> (Float, T.CotangentVector)) {
  return (y, { v in (x, v) })
}

//===----------------------------------------------------------------------===//
// JVP
//===----------------------------------------------------------------------===//

@_silgen_name("hasjvp")
@differentiable(jvp: dhasjvp)
public func hasjvp(_ x: Float, _ y: Float) -> Float {
  return 1
}

// CHECK-LABEL: sil [differentiable source 0 wrt 0, 1 jvp @dhasjvp] @hasjvp

@_silgen_name("dhasjvp")
public func dhasjvp(_ x: Float, _ y: Float) -> (Float, (Float, Float) -> Float) {
  return (1, { _, _ in 1 })
}

// CHECK-LABEL: sil @dhasjvp

//===----------------------------------------------------------------------===//
// VJP
//===----------------------------------------------------------------------===//

@inlinable
@_silgen_name("hasvjp")
@differentiable(vjp: dhasvjp)
public func hasvjp(_ x: Float, _ y: Float) -> Float {
  return 1
}

// CHECK-LABEL: sil [serialized] [differentiable source 0 wrt 0, 1 vjp @dhasvjp] @hasvjp

@_silgen_name("dhasvjp")
public func dhasvjp(_ x: Float, _ y: Float) -> (Float, (Float) -> (Float, Float)) {
  return (1, { _ in (1, 1) })
}

// CHECK-LABEL: sil @dhasvjp

//===----------------------------------------------------------------------===//
// Stored property
//===----------------------------------------------------------------------===//

struct DiffStoredProp {
  @differentiable(wrt: (self), jvp: storedPropJVP, vjp: storedPropVJP)
  let storedProp: Float

  @_silgen_name("storedPropJVP")
  func storedPropJVP() -> (Float, (DiffStoredProp) -> Float) {
    fatalError("unimplemented")
  }

  @_silgen_name("storedPropVJP")
  func storedPropVJP() -> (Float, (Float) -> DiffStoredProp) {
    fatalError("unimplemented")
  }
}

extension DiffStoredProp : VectorNumeric {
  static var zero: DiffStoredProp { fatalError("unimplemented") }
  static func + (lhs: DiffStoredProp, rhs: DiffStoredProp) -> DiffStoredProp {
    fatalError("unimplemented")
  }
  static func - (lhs: DiffStoredProp, rhs: DiffStoredProp) -> DiffStoredProp {
    fatalError("unimplemented")
  }
  typealias Scalar = Float
  static func * (lhs: Float, rhs: DiffStoredProp) -> DiffStoredProp {
    fatalError("unimplemented")
  }
}

extension DiffStoredProp : Differentiable {
  typealias TangentVector = DiffStoredProp
  typealias CotangentVector = DiffStoredProp
}

//===----------------------------------------------------------------------===//
// Computed property
//===----------------------------------------------------------------------===//

struct DiffComputedProp {
  @differentiable(wrt: (self), jvp: computedPropJVP, vjp: computedPropVJP)
  var computedProp: Float {
    return 0
  }

  @_silgen_name("computedPropJVP")
  func computedPropJVP() -> (Float, (DiffComputedProp) -> Float) {
    fatalError("unimplemented")
  }

  @_silgen_name("computedPropVJP")
  func computedPropVJP() -> (Float, (Float) -> DiffComputedProp) {
    fatalError("unimplemented")
  }
}

extension DiffComputedProp : VectorNumeric {
  static var zero: DiffComputedProp { fatalError("unimplemented") }
  static func + (lhs: DiffComputedProp, rhs: DiffComputedProp) -> DiffComputedProp {
    fatalError("unimplemented")
  }
  static func - (lhs: DiffComputedProp, rhs: DiffComputedProp) -> DiffComputedProp {
    fatalError("unimplemented")
  }
  typealias Scalar = Float
  static func * (lhs: Float, rhs: DiffComputedProp) -> DiffComputedProp {
    fatalError("unimplemented")
  }
}

extension DiffComputedProp : Differentiable {
  typealias TangentVector = DiffComputedProp
  typealias CotangentVector = DiffComputedProp
}

// CHECK-LABEL: DiffComputedProp.computedProp.getter
// CHECK-NEXT: [differentiable source 0 wrt 0 jvp @computedPropJVP vjp @computedPropVJP]

public struct MyLayer: Differentiable {
  @differentiable
  var x: Float = 10
}

// CHECK-LABEL: initialization expression of MyLayer.x
// CHECK-NEXT: sil [transparent] @$s26differentiable_attr_silgen7MyLayerV1xSfvpfi : $@convention(thin) () -> Float
