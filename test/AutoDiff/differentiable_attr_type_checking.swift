// RUN: %target-swift-frontend -typecheck -verify %s

@differentiable(vjp: dfoo) // expected-error {{'@differentiable' attribute cannot be applied to this declaration}}
let x: Float = 1

@differentiable(vjp: dfoo) // expected-error {{'@differentiable' attribute cannot be applied to this declaration}}
protocol P {}

@differentiable() // ok!
func no_jvp_or_vjp(_ x: Float) -> Float {
  return x * x
}

@differentiable // expected-error {{duplicate '@differentiable' attribute}}
@differentiable
func dupe_attributes(arg: Float) -> Float { return arg }

@differentiable(wrt: arg1) // expected-error {{duplicate '@differentiable' attribute}}
@differentiable(wrt: arg1)
@differentiable(wrt: arg2) // expected-error {{duplicate '@differentiable' attribute}}
@differentiable(wrt: arg2)
func dupe_attributes(arg1: Float, arg2: Float) -> Float { return arg1 }

class Class {}
// expected-error @+1 {{class objects and protocol existentials ('Class') cannot be differentiated with respect to}}
@differentiable(wrt: x)
func invalidDiffWrtClass(_ x: Class) -> Class {
  return x
}

protocol Proto {}
// expected-error @+1 {{class objects and protocol existentials ('Proto') cannot be differentiated with respect to}}
@differentiable(wrt: x)
func invalidDiffWrtExistential(_ x: Proto) -> Proto {
  return x
}

// expected-error @+1 {{functions ('@differentiable (Float) -> Float') cannot be differentiated with respect to}}
@differentiable(wrt: fn)
func invalidDiffWrtFunction(_ fn: @differentiable(Float) -> Float) -> Float {
  return fn(.pi)
}

// JVP

@differentiable(jvp: jvpSimpleJVP)
func jvpSimple(x: Float) -> Float {
  return x
}

func jvpSimpleJVP(x: Float) -> (Float, ((Float) -> Float)) {
  return (x, { v in v })
}

@differentiable(wrt: y, jvp: jvpWrtSubsetJVP)
func jvpWrtSubset1(x: Float, y: Float) -> Float {
  return x + y
}

@differentiable(wrt: (y), jvp: jvpWrtSubsetJVP)
func jvpWrtSubset2(x: Float, y: Float) -> Float {
  return x + y
}

func jvpWrtSubsetJVP(x: Float, y: Float) -> (Float, (Float) -> Float) {
  return (x + y, { v in v })
}

@differentiable(jvp: jvp2ParamsJVP)
func jvp2Params(x: Float, y: Float) -> Float {
  return x + y
}

func jvp2ParamsJVP(x: Float, y: Float) -> (Float, (Float, Float) -> Float) {
  return (x + y, { (a, b) in a + b })
}

// expected-error @+1 {{unknown parameter name 'y'}}
@differentiable(wrt: (y))
func jvpUnknownParam(x: Float) -> Float {
  return x
}

// expected-error @+1 {{parameter names must be specified in original order}}
@differentiable(wrt: (y, x))
func jvpParamOrderNotIncreasing(x: Float, y: Float) -> Float {
  return x * y
}

// expected-error @+1 {{'jvpWrongTypeJVP' does not have expected type '(Float) -> (Float, (Float.TangentVector) -> Float.TangentVector)' (aka '(Float) -> (Float, (Float) -> Float)'}}
@differentiable(jvp: jvpWrongTypeJVP)
func jvpWrongType(x: Float) -> Float {
  return x
}

func jvpWrongTypeJVP(x: Float) -> (Float, (Float) -> Int) {
  return (x, { v in Int(v) })
}

// expected-error @+1 {{specify at least one parameter to differentiate with respect to}}
@differentiable(jvp: jvpSimpleJVP)
func jvpNonDiffParam(x: Int) -> Float {
  return Float(x)
}

// expected-error @+1 {{can only differentiate functions with results that conform to 'Differentiable', but 'Int' does not conform to 'Differentiable'}}
@differentiable(jvp: jvpSimpleJVP)
func jvpNonDiffResult(x: Float) -> Int {
  return Int(x)
}

// expected-error @+1 {{can only differentiate functions with results that conform to 'Differentiable', but 'Int' does not conform to 'Differentiable'}}
@differentiable(jvp: jvpSimpleJVP)
func jvpNonDiffResult2(x: Float) -> (Float, Int) {
  return (x, Int(x))
}

// expected-error @+1 {{ambiguous or overloaded identifier 'jvpAmbiguousVJP' cannot be used in '@differentiable' attribute}}
@differentiable(jvp: jvpAmbiguousVJP)
func jvpAmbiguous(x: Float) -> Float {
  return x
}
func jvpAmbiguousVJP(_ x: Float) -> (Float, (Float) -> Float) {
  return (x, { $0 })
}
func jvpAmbiguousVJP(x: Float) -> (Float, (Float) -> Float) {
  return (x, { $0 })
}

// TF-153: Class methods are not supported yet.
class Foo {
  // Direct differentiation case.
  // expected-error @+1 {{class members cannot be marked with '@differentiable'}}
  @differentiable
  func foo(_ x: Float) -> Float {
    return x
  }
}

struct JVPStruct {
  let p: Float

  @differentiable(wrt: (self), jvp: storedPropJVP)
  let storedImmutableOk: Float

  // expected-error @+1 {{'storedPropJVP' does not have expected type '(JVPStruct) -> () -> (Double, (JVPStruct.TangentVector) -> Double.TangentVector)' (aka '(JVPStruct) -> () -> (Double, (JVPStruct) -> Double)'}}
  @differentiable(wrt: (self), jvp: storedPropJVP)
  let storedImmutableWrongType: Double

  @differentiable(wrt: (self), jvp: storedPropJVP)
  var storedMutableOk: Float

  // expected-error @+1 {{'storedPropJVP' does not have expected type '(JVPStruct) -> () -> (Double, (JVPStruct.TangentVector) -> Double.TangentVector)' (aka '(JVPStruct) -> () -> (Double, (JVPStruct) -> Double)'}}
  @differentiable(wrt: (self), jvp: storedPropJVP)
  var storedMutableWrongType: Double
}

extension JVPStruct {
  func storedPropJVP() -> (Float, (JVPStruct) -> Float) {
    fatalError("unimplemented")
  }
}

extension JVPStruct : VectorNumeric {
  static var zero: JVPStruct { fatalError("unimplemented") }
  static func + (lhs: JVPStruct, rhs: JVPStruct) -> JVPStruct {
    fatalError("unimplemented")
  }
  static func - (lhs: JVPStruct, rhs: JVPStruct) -> JVPStruct {
    fatalError("unimplemented")
  }
  typealias Scalar = Float
  static func * (lhs: Float, rhs: JVPStruct) -> JVPStruct {
    fatalError("unimplemented")
  }
}

extension JVPStruct : Differentiable {
  typealias TangentVector = JVPStruct
  typealias CotangentVector = JVPStruct
}

extension JVPStruct {
  @differentiable(wrt: x, jvp: wrtAllNonSelfJVP)
  func wrtAllNonSelf(x: Float) -> Float {
    return x + p
  }

  func wrtAllNonSelfJVP(x: Float) -> (Float, (Float) -> Float) {
    return (x + p, { v in v })
  }
}

extension JVPStruct {
  @differentiable(wrt: (self, x), jvp: wrtAllJVP)
  func wrtAll(x: Float) -> Float {
    return x + p
  }

  func wrtAllJVP(x: Float) -> (Float, (JVPStruct, Float) -> Float) {
    return (x + p, { (a, b) in a.p + b })
  }
}

extension JVPStruct {
  @differentiable(jvp: computedPropJVP)
  var computedPropOk1: Float {
    return 0
  }

  var computedPropOk2: Float {
    @differentiable(jvp: computedPropJVP)
    get {
      return 0
    }
  }

  // expected-error @+1 {{'computedPropJVP' does not have expected type '(JVPStruct) -> () -> (Double, (JVPStruct.TangentVector) -> Double.TangentVector)' (aka '(JVPStruct) -> () -> (Double, (JVPStruct) -> Double)'}}
  @differentiable(jvp: computedPropJVP)
  var computedPropWrongType: Double {
    return 0
  }

  var computedPropWrongAccessor: Float {
    get {
      return 0
    }
    // expected-error @+1 {{'@differentiable' attribute cannot be applied to this declaration}}
    @differentiable(jvp: computedPropJVP)
    set {
      fatalError("unimplemented")
    }
  }

  func computedPropJVP() -> (Float, (JVPStruct) -> Float) {
    fatalError("unimplemented")
  }
}

// VJP

@differentiable(vjp: vjpSimpleVJP)
func vjpSimple(x: Float) -> Float {
  return x
}

func vjpSimpleVJP(x: Float) -> (Float, ((Float) -> Float)) {
  return (x, { v in v })
}

@differentiable(wrt: (y), vjp: vjpWrtSubsetVJP)
func vjpWrtSubset(x: Float, y: Float) -> Float {
  return x + y
}

func vjpWrtSubsetVJP(x: Float, y: Float) -> (Float, (Float) -> Float) {
  return (x + y, { v in v })
}

@differentiable(vjp: vjp2ParamsVJP)
func vjp2Params(x: Float, y: Float) -> Float {
  return x + y
}

func vjp2ParamsVJP(x: Float, y: Float) -> (Float, (Float) -> (Float, Float)) {
  return (x + y, { v in (v, v) })
}

// expected-error @+1 {{'vjpWrongTypeVJP' does not have expected type '(Float) -> (Float, (Float.CotangentVector) -> Float.CotangentVector)' (aka '(Float) -> (Float, (Float) -> Float)'}}
@differentiable(vjp: vjpWrongTypeVJP)
func vjpWrongType(x: Float) -> Float {
  return x
}

func vjpWrongTypeVJP(x: Float) -> (Float, (Float) -> Int) {
  return (x, { v in Int(v) })
}

// expected-error @+1 {{specify at least one parameter to differentiate with respect to}}
@differentiable(vjp: vjpSimpleVJP)
func vjpNonDiffParam(x: Int) -> Float {
  return Float(x)
}

// expected-error @+1 {{can only differentiate functions with results that conform to 'Differentiable', but 'Int' does not conform to 'Differentiable'}}
@differentiable(vjp: vjpSimpleVJP)
func vjpNonDiffResult(x: Float) -> Int {
  return Int(x)
}

// expected-error @+1 {{can only differentiate functions with results that conform to 'Differentiable', but 'Int' does not conform to 'Differentiable'}}
@differentiable(vjp: vjpSimpleVJP)
func vjpNonDiffResult2(x: Float) -> (Float, Int) {
  return (x, Int(x))
}

struct VJPStruct {
  let p: Float

  @differentiable(vjp: storedPropVJP)
  let storedImmutableOk: Float

  // expected-error @+1 {{'storedPropVJP' does not have expected type '(VJPStruct) -> () -> (Double, (Double.CotangentVector) -> VJPStruct.CotangentVector)' (aka '(VJPStruct) -> () -> (Double, (Double) -> VJPStruct)'}}
  @differentiable(vjp: storedPropVJP)
  let storedImmutableWrongType: Double

  @differentiable(vjp: storedPropVJP)
  var storedMutableOk: Float

  // expected-error @+1 {{'storedPropVJP' does not have expected type '(VJPStruct) -> () -> (Double, (Double.CotangentVector) -> VJPStruct.CotangentVector)' (aka '(VJPStruct) -> () -> (Double, (Double) -> VJPStruct)'}}
  @differentiable(vjp: storedPropVJP)
  var storedMutableWrongType: Double
}

extension VJPStruct {
  func storedPropVJP() -> (Float, (Float) -> VJPStruct) {
    fatalError("unimplemented")
  }
}

extension VJPStruct : VectorNumeric {
  static var zero: VJPStruct { fatalError("unimplemented") }
  static func + (lhs: VJPStruct, rhs: VJPStruct) -> VJPStruct {
    fatalError("unimplemented")
  }
  static func - (lhs: VJPStruct, rhs: VJPStruct) -> VJPStruct {
    fatalError("unimplemented")
  }
  typealias Scalar = Float
  static func * (lhs: Float, rhs: VJPStruct) -> VJPStruct {
    fatalError("unimplemented")
  }
}

extension VJPStruct : Differentiable {
  typealias TangentVector = VJPStruct
  typealias CotangentVector = VJPStruct
}

extension VJPStruct {
  @differentiable(wrt: x, vjp: wrtAllNonSelfVJP)
  func wrtAllNonSelf(x: Float) -> Float {
    return x + p
  }

  func wrtAllNonSelfVJP(x: Float) -> (Float, (Float) -> Float) {
    return (x + p, { v in v })
  }
}

extension VJPStruct {
  @differentiable(wrt: (self, x), vjp: wrtAllVJP)
  func wrtAll(x: Float) -> Float {
    return x + p
  }

  func wrtAllVJP(x: Float) -> (Float, (Float) -> (VJPStruct, Float)) {
    fatalError("unimplemented")
  }
}

extension VJPStruct {
  @differentiable(vjp: computedPropVJP)
  var computedPropOk1: Float {
    return 0
  }

  var computedPropOk2: Float {
    @differentiable(vjp: computedPropVJP)
    get {
      return 0
    }
  }

  // expected-error @+1 {{'computedPropVJP' does not have expected type '(VJPStruct) -> () -> (Double, (Double.CotangentVector) -> VJPStruct.CotangentVector)' (aka '(VJPStruct) -> () -> (Double, (Double) -> VJPStruct)'}}
  @differentiable(vjp: computedPropVJP)
  var computedPropWrongType: Double {
    return 0
  }

  var computedPropWrongAccessor: Float {
    get {
      return 0
    }
    // expected-error @+1 {{'@differentiable' attribute cannot be applied to this declaration}}
    @differentiable(vjp: computedPropVJP)
    set {
      fatalError("unimplemented")
    }
  }

  func computedPropVJP() -> (Float, (Float) -> VJPStruct) {
    fatalError("unimplemented")
  }
}

// expected-error @+2 {{empty 'where' clause in '@differentiable' attribute}}
// expected-error @+1 {{expected type}}
@differentiable(where)
func emptyWhereClause<T>(x: T) -> T {
  return x
}

// expected-error @+1 {{trailing 'where' clause in '@differentiable' attribute of non-generic function 'nongenericWhereClause(x:)'}}
@differentiable(where T : Differentiable)
func nongenericWhereClause(x: Float) -> Float {
  return x
}

@differentiable(jvp: jvpWhere1, vjp: vjpWhere1 where T : Differentiable)
func where1<T>(x: T) -> T {
  return x
}
func jvpWhere1<T : Differentiable>(x: T) -> (T, (T.TangentVector) -> T.TangentVector) {
  return (x, { v in v })
}
func vjpWhere1<T : Differentiable>(x: T) -> (T, (T.CotangentVector) -> T.CotangentVector) {
  return (x, { v in v })
}

struct Tensor<Scalar> : AdditiveArithmetic {}
extension Tensor : Differentiable where Scalar : Differentiable {
  typealias TangentVector = Tensor
  typealias CotangentVector = Tensor
  typealias AllDifferentiableVariables = Tensor
  func moved(along direction: Tensor) -> Tensor { return self }
  func tangentVector(from cotangent: Tensor) -> Tensor { return cotangent }
}
@differentiable(where Scalar : Differentiable)
func where2<Scalar : Numeric>(x: Tensor<Scalar>) -> Tensor<Scalar> {
  return x
}
func adjWhere2<Scalar : Numeric & Differentiable>(seed: Tensor<Scalar>, originalResult: Tensor<Scalar>, x: Tensor<Scalar>) -> Tensor<Scalar> {
  return seed
}
func jvpWhere2<Scalar : Numeric & Differentiable>(x: Tensor<Scalar>) -> (Tensor<Scalar>, (Tensor<Scalar>) -> Tensor<Scalar>) {
  return (x, { v in v })
}
func vjpWhere2<Scalar : Numeric & Differentiable>(x: Tensor<Scalar>) -> (Tensor<Scalar>, (Tensor<Scalar>) -> Tensor<Scalar>) {
  return (x, { v in v })
}

struct A<T> {
  struct B<U, V> {
    @differentiable(wrt: x where T : Differentiable, V : Differentiable, V.TangentVector == V)
    func whereInGenericContext<T>(x: T) -> T {
      return x
    }
  }
}

extension FloatingPoint {
  @differentiable(wrt: (self) where Self : Differentiable)
  func whereClauseExtension() -> Self {
    return self
  }
}

protocol MethodDiffReq {
  // expected-error @+1 {{'vjpFoo' does not have expected type '<Self where Self : Differentiable, Self : MethodDiffReq> (Self) -> () -> (Self, (Self.CotangentVector) -> Self.CotangentVector)'}}
  @differentiable(wrt: self, vjp: vjpFoo where Self : Differentiable)
  func foo() -> Self
}

extension MethodDiffReq where Self : Differentiable {
  func vjpFoo(x: Self) -> (Self, (Self.CotangentVector) -> Self.CotangentVector) {
    return (self, { $0 })
  }
}

// expected-error @+1 {{'vjpNonvariadic' does not have expected type '(Float, Int32...) -> (Float, (Float.CotangentVector) -> Float.CotangentVector)' (aka '(Float, Int32...) -> (Float, (Float) -> Float)')}}
@differentiable(wrt: x, vjp: vjpNonvariadic)
func variadic(_ x: Float, indices: Int32...) -> Float {
  return x
}
func vjpNonvariadic(_ x: Float, indices: [Int32]) -> (Float, (Float) -> Float) {
  return (x, { $0 })
}

// expected-error @+2 {{type 'Scalar' constrained to non-protocol, non-class type 'Float'}}
// expected-error @+1 {{specify at least one parameter to differentiate with respect to}}
@differentiable(where Scalar : Float)
func invalidRequirementConformance<Scalar>(x: Scalar) -> Scalar {
  return x
}

// expected-error @+2 {{layout constraints are only allowed inside '_specialize' attributes}}
// expected-error @+1 {{empty 'where' clause in '@differentiable' attribute}}
@differentiable(where Scalar : _Trivial)
func invalidRequirementLayout<Scalar>(x: Scalar) -> Scalar {
  return x
}

protocol DiffReq : Differentiable {
  // expected-note @+2 {{protocol requires function 'f1'}}
  @differentiable(wrt: (self, x))
  func f1(_ x: Float) -> Float

  // expected-note @+2 {{protocol requires function 'f2'}}
  @differentiable(wrt: (self, x, y))
  func f2(_ x: Float, _ y: Float) -> Float
}

// expected-error @+1 {{does not conform to protocol 'DiffReq'}}
struct ConformingWithErrors : DiffReq {
  // expected-note @+1 {{candidate is missing attribute '@differentiable(wrt: (self, x))'}}
  func f1(_ x: Float) -> Float {
    return x
  }

  // expected-note @+2 {{candidate is missing attribute '@differentiable(wrt: (self, x, y))'}}
  @differentiable(wrt: (self, x))
  func f2(_ x: Float, _ y: Float) -> Float {
    return x + y
  }
}

protocol DifferentiableInit : Differentiable {
  // expected-note @+2 {{protocol requires initializer 'init(x:y:)' with type '(x: Float, y: Float)'}}
  @differentiable
  init(x: Float, y: Float)

  // expected-note @+2 {{protocol requires initializer 'init(x:y:)' with type '(x: Float, y: Int)'}}
  @differentiable(wrt: x)
  init(x: Float, y: Int)
}
// expected-error @+1 {{does not conform to protocol 'DifferentiableInit'}}
struct DifferentiableInitStruct : DifferentiableInit {
  var x: Float
  var y: Float

  // FIXME(TF-284): Fix unexpected diagnostic.
  // expected-note @+2 {{candidate is missing attribute '@differentiable'}}
  // expected-note @+1 {{candidate is missing attribute '@differentiable(wrt: x)'}}
  init(x: Float, y: Float) {
    self.x = x
    self.y = y
  }

  // FIXME(TF-284): Fix unexpected diagnostic.
  // expected-note @+2 {{candidate is missing attribute '@differentiable(wrt: x)'}}
  // expected-note @+1 {{candidate is missing attribute '@differentiable'}}
  init(x: Float, y: Int) {
    self.x = x
    self.y = Float(y)
  }
}


protocol NotRefiningDiffable {
  @differentiable(wrt: x)
  // expected-note @+1 {{protocol requires function 'a' with type '(Float) -> Float'; do you want to add a stub?}}
  func a(_ x: Float) -> Float
}

// expected-error @+1 {{type 'CertainlyNotDiffableWrtSelf' does not conform to protocol 'NotRefiningDiffable'}}
struct CertainlyNotDiffableWrtSelf : NotRefiningDiffable {
  // expected-note @+1 {{candidate is missing attribute '@differentiable(wrt: x)'}}
  func a(_ x: Float) -> Float { return x * 5.0 }
}


protocol TF285 : Differentiable {
  @differentiable(wrt: (x, y))
  @differentiable(wrt: x)
  // expected-note @+1 {{protocol requires function 'foo(x:y:)' with type '(Float, Float) -> Float'; do you want to add a stub?}}
  func foo(x: Float, y: Float) -> Float
}

// expected-error @+1 {{type 'TF285MissingOneDiffAttr' does not conform to protocol 'TF285'}}
struct TF285MissingOneDiffAttr : TF285 {
  // Requirement is missing an attribute.
  @differentiable(wrt: x)
  // expected-note @+2 {{candidate is missing attribute '@differentiable(wrt: x)}}
  // expected-note @+1 {{candidate is missing attribute '@differentiable(wrt: (x, y))}}
  func foo(x: Float, y: Float) -> Float {
    return x
  }
}


// TF-296: Infer `@differentiable` wrt parameters to be to all parameters that conform to `Differentiable`.

@differentiable
func infer1(_ a: Float, _ b: Int) -> Float {
  return a + Float(b)
}

@differentiable
func infer2(_ fn: @differentiable(Float) -> Float, x: Float) -> Float {
  return fn(x)
}

struct DiffableStruct : Differentiable {
  var a: Float

  @differentiable
  func fn(_ b: Float, _ c: Int) -> Float {
    return a + b + Float(c)
  }
}

struct NonDiffableStruct {
  var a: Float

  @differentiable
  func fn(_ b: Float) -> Float {
    return a + b
  }
}
