// RUN: %target-run-eager-swift %swift-tensorflow-test-run-extra-options
// REQUIRES: executable_test
// REQUIRES: swift_test_mode_optimize
//
// Trivial model tests.

import TensorFlow
#if TPU
import TensorFlowUnittestTPU
#else
import TensorFlowUnittest
#endif
import StdlibUnittest

var ModelTests = TestSuite("Model")

ModelTests.testAllBackends("StraightLineXORTraining") {
  // FIXME: TPU execution on TAP is timing out. (b/74155319)
  guard !_RuntimeConfig.executionMode.isTPU else { return }

  // Hyper-parameters
  let iterationCount = 2000
  let learningRate: Float = 0.2
  var loss = Float.infinity

  // Parameters
  var w1: Tensor<Float> = [[0.69414073, 0.017726839, 0.3128785, 0.74679214],
                           [0.80624646, 0.8905365, 0.7302696, 0.18774611]]
  var w2: Tensor<Float> = [[0.38796782], [0.18304485], [0.8680929], [0.8904212]]
  var b1 = Tensor<Float>(zeros: [1, 4])
  var b2 = Tensor<Float>(zeros: [1, 1])

  // Training data
  let x: Tensor<Float> = [[0, 0], [0, 1], [1, 0], [1, 1]]
  let y: Tensor<Float> = [[0], [1], [1], [0]]

  for i in 0..<iterationCount {
    let z1 = matmul(x, w1) + b1
    let h1 = sigmoid(z1)
    let z2 = matmul(h1, w2) + b2
    let pred = sigmoid(z2)

    let dz2 = pred - y
    let dw2 = matmul(h1.transposed(withPermutations: 1, 0), dz2)
    let db2 = dz2.sum(squeezingAxes: 0)
    let dz1 = matmul(dz2, w2.transposed(withPermutations: 1, 0)) * h1 * (1 - h1)
    let dw1 = matmul(x.transposed(withPermutations: 1, 0), dz1)
    let db1 = dz1.sum(squeezingAxes: 0)

    w1 -= dw1 * learningRate
    b1 -= db1 * learningRate
    w2 -= dw2 * learningRate
    b2 -= db2 * learningRate

    loss = dz2.squared().mean(squeezingAxes: 1, 0).scalarized()
  }
  expectLT(loss, 0.01)
}

ModelTests.testAllBackends("XORClassifierTraining") {
  // FIXME: XORClassifierTraining_TPU crashes with SIGSEGV. (b/74155319)
  guard !_RuntimeConfig.executionMode.isTPU else { return }

  // The classifier struct.
  struct MLPClassifier {
    var w1, w2, b1, b2: Tensor<Float>

    init() {
      w1 = [[0.69414073, 0.017726839, 0.3128785, 0.74679214],
            [0.80624646, 0.8905365, 0.7302696, 0.18774611]]
      w2 = [[0.38796782], [0.18304485], [0.8680929], [0.8904212]]
      b1 = Tensor(zeros: [1, 4])
      b2 = Tensor(zeros: [1, 1])
    }

    func prediction(for x: Tensor<Float>) -> Tensor<Float> {
      let o1 = sigmoid(matmul(x, w1) + b1)
      return sigmoid(matmul(o1, w2) + b2)
    }

    func prediction(for x: Bool, _ y: Bool) -> Bool {
      let input = Tensor<Float>(Tensor([x, y]).reshaped(to: [1, 2]))
      let floatPred = prediction(for: input).scalarized()
      return abs(floatPred - 1) < 0.1
    }

    func loss(of prediction: Tensor<Float>,
              from exampleOutput: Tensor<Float>) -> Float {
      return (prediction - exampleOutput).squared()
        .mean(squeezingAxes: 0, 1).scalarized()
    }

    mutating func train(inputBatch x: Tensor<Float>,
                        outputBatch y: Tensor<Float>,
                        iterationCount: Int, learningRate: Float) {
      for i in 0..<iterationCount {
        let z1 = matmul(x, w1) + b1
        let h1 = sigmoid(z1)
        let z2 = matmul(h1, w2) + b2
        let pred = sigmoid(z2)

        let dz2 = pred - y
        let dw2 = matmul(h1.transposed(withPermutations: 1, 0), dz2)
        let db2 = dz2.sum(squeezingAxes: 0)
        let dz1 = matmul(dz2, w2.transposed(withPermutations: 1, 0)) * h1 * (1 - h1)
        let dw1 = matmul(x.transposed(withPermutations: 1, 0), dz1)
        let db1 = dz1.sum(squeezingAxes: 0)

        w1 -= dw1 * learningRate
        b1 -= db1 * learningRate
        w2 -= dw2 * learningRate
        b2 -= db2 * learningRate
      }
    }
  }

  var classifier = MLPClassifier()
  classifier.train(
    inputBatch: [[0, 0], [0, 1], [1, 0], [1, 1]],
    outputBatch: [[0], [1], [1], [0]],
    iterationCount: 2000,
    learningRate: 0.2
  )
  expectEqual(classifier.prediction(for: true, false), true)
}

runAllTests()
