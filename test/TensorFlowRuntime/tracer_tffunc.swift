// RUN: %target-run-eager-swift %swift-tensorflow-test-run-extra-options
// REQUIRES: executable_test
// REQUIRES: swift_test_mode_optimize
//
// Tracer tests.

import TensorFlow
#if TPU
import TensorFlowUnittestTPU
#else
import TensorFlowUnittest
#endif
import StdlibUnittest

var TracerTests = TestSuite("TracerTFFunction")

extension Tensor : _TensorArrayProtocolEnhanced {
  public func _makeInstance<C: Collection>(owning inputs: C) -> Tensor
    where C.Element == CTensorHandle {
    assert(inputs.count == 1)
    return Tensor(handle: TensorHandle<Scalar>(_owning: inputs.first!))
  }
}

TracerTests.testAllBackends("SimpleTFFunction") {
  func cond(i: Tensor<Int32>, n: Tensor<Int32>) -> (Tensor<Int32>) {
    return (Tensor<Int32>(i .< n))
  }

  func body(i: Tensor<Int32>) -> Tensor<Int32> {
    return i + 1
  }

  let tffunc = _tffunc(with: Tensor<Int32>(0), in: cond)

  func runWhile(_ n: Int32) -> Tensor<Int32> {
    return #tfop(
      "While",
      Tensor<Int32>(0),
      T$dtype: [Int32.tensorFlowDataType],
      cond$func: tffunc(Tensor<Int32>(n)),
      body$func: _tffunc(body))
  }

  expectEqualWithScalarTensor(10, runWhile(10))
  expectEqualWithScalarTensor(300, runWhile(300))
}

runAllTests()
