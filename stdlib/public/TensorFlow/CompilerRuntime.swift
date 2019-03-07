//===-- CompilerRuntime.swift ---------------------------------*- swift -*-===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//
//
// This file defines the Swift runtime support for TensorFlow computation.
//
// This file should only contain internal details: runtime-related public APIs
// should be defined in `Execution.swift`.
//
// Design notes on TF eager based runtime:
//
// 1. A global context (`_ExecutionContext.global`) is used to manage all tensor
// computation and transfers.
//
// 2. When the tensor computation involves N device functions, run them in N
// threads (but with the same execution/eager context). In addition, run the
// host-side of sends/recvs in the main thread. These N + 1 threads form
// "coroutines", and use sends/recvs mechanisms to communicate and unblock each
// other's progress.
// 2a) The sends/recvs mechanism between host and TF is the enqueue / dequeue
// operations on TF (CPU-based) Fifo queues. Only tensor handles are transferred
// in these enqueue / dequeue operations. For host to consume the content of the
// tensor sent from TF, it uses TFE_TensorHandleResolve().
// 2b) The sends/recvs mechanism between TF devices is the _Send / _Recv TF ops.
//
// Potential TODOs:
// - Support async on platforms other than Linux and FreeBSD.
// - Revisit the concurrency model and see if Dispatch can be built without
//   Foundation.
//
//===----------------------------------------------------------------------===//

#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
import Darwin
#else
import Glibc
#endif
import CTensorFlow

// @_frozen // SR-9739
public enum _ExecutionMode : Equatable {
  /// CPU or GPU execution.
  case auto
  /// TPU execution.
  // TODO: assess if we can pass this bit of info from compiler settings (when
  // enableTPU() is called), and avoid having this additional runtime bit.
  case tpu
  /// XLA jit-compilation backend (will use GPU when available, and otherwise
  /// CPU).
  case xla

  public var isTPU: Bool {
    switch self {
    case .tpu: return true
    default: return false
    }
  }
}

/// TraceContext contains the state needed to build a trace graph function
/// (TF_Function). As eager ops are executed in tracing mode, their
/// corresponding nodes are added to the trace graph (via
/// `addEagerOpToGraph()`). When the trace is finalized (via `finalize()`), the
/// trace graph function can then be executed (via `execute()`) by the eager
/// runtime.
private class TraceContext {
  let status: CTFStatus = TF_NewStatus()

  /// The trace graph, which will be converted to a trace graph function
  /// (TF_Function) upon finalizing.
  let graph = TF_NewGraph()

  /// The list of inputs to the trace graph function. It starts with the inputs
  /// to the function that we trace (referred to as the "tracee function" or
  /// "tracee"), followed by possible additional inputs that correspond to
  /// concrete tensors produced within the trace function.
  ///
  /// For example, if the tracee is:
  /// func foo(x: TensorPair) -> Tensor {
  ///   let y = Tensor<Float>(1.0)
  ///   return x.first + x.second + y
  /// }
  ///
  /// Then the generated trace graph function has 3 input tensors: x.first,
  /// x.second, and y.
  ///
  /// These symbolic tensors corresond to PlaceHolder nodes in the trace graph,
  /// and will be filled in when we execute the trace graph function.
  //
  // TODO: If some tensors in `x` are not used within `foo()`, they can be
  // pruned away in the inputs to the trace graph function.
  var symbolicInputs: [TF_Output] = []

  /// The outputs obtained by executing the `tracee` for computing the trace.
  var tracedOutputs: [CTensorHandle] = []

  /// The trace context object used in TF C API calls that convert eager ops to
  /// (trace) graph nodes.
  let cTraceContext: CTFETraceContext

  /// The trace graph function created by `finalize()`.
  var traceGraphFn: CTFFunction?

  /// The number of additional input tensors to the trace graph function,
  /// created from concrete intermediate tensors in the tracee, such as `y` in
  /// the code snippet above.
  var additionalInputTensorCount: Int32 = -1

  /// `dtypes` is the (flattened) list of TF_DataType of input tensors
  /// to the trace function.
  init(dtypes: [TF_DataType]) {
    debugLog("Instiantiating TraceContext with \(dtypes.count) input tensors.")
    for (i, dtype) in dtypes.enumerated() {
      let desc = TF_NewOperation(graph, "Placeholder", "input_\(i)")
      TF_SetAttrType(desc, "dtype", dtype)
      let result = TF_FinishOperation(desc, status)
      checkOk(status)
      symbolicInputs.append(TF_Output(oper: result, index: 0))
    }
    cTraceContext = TFE_NewTraceContext(graph)
  }

  deinit {
    TFE_DeleteTraceContext(cTraceContext)
    TF_DeleteGraph(graph)
    TF_DeleteStatus(status)
  }

  func addEagerOpToGraph(_ op: CTFEOp,
                      _ retvals: UnsafeMutablePointer<OpaquePointer?>,
                      _ retvalCount: UnsafeMutablePointer<Int32>,
                      _ status: CTFStatus) {
    TFE_AddEagerOpToGraph(op, cTraceContext, retvals, retvalCount, status)
    checkOk(status)
  }

  /// Finalize the trace graph function.
  func finalize(traceeBasicName: String) {
    internalConsistencyCheck(traceGraphFn == nil)
    var symbolicOutputs: [TF_Output] = []
    // Only add symbolic output tensors as the outputs of the trace graph function.
    // For example, let the tracee be:
    //   func foo(x: Tensor) -> (Tensor, Tensor) {
    //     let y = Tensor<Float>(1.0)
    //     return (x + x, y)
    //   }
    //
    // Here foo() returns 2 tensors, but only the first one (as computed by x +
    // x) is symbolic. The second one for y is concrete, and is computed at
    // trace creation time, not trace execution time.
    // Also see the comment block above finalizeAndExecuteTraceFn().
    for (i, tracedOutput) in tracedOutputs.enumerated()
        where TFE_TensorHandleIsConcrete(tracedOutput) == 0 {
      debugLog("Adding symbolic tracedOutput \(i) as a trace graph func output.")
      symbolicOutputs.append(TFE_GetTFOutputFromTensorHandle(tracedOutput ,status))
      checkOk(status)
    }

    let traceeInputCount = symbolicInputs.count
    // Append concrete tensors created within the tracee as symbolic inputs to
    // the generated trace graph function.
    additionalInputTensorCount = TFE_FinalizeInputTensorsFromTraceContext(
      cTraceContext)
    for i in 0..<additionalInputTensorCount {
      symbolicInputs.append(TFE_GetInputGraphNodeFromTraceContext(
                              cTraceContext, UInt32(i)))
    }

    let tracedFunctionName =
      "\(traceeBasicName)_\(_RuntimeConfig.traceGraphFunctionCounter)"
    _RuntimeConfig.traceGraphFunctionCounter += 1
    debugLog("""
               Finalizing trace graph func \(tracedFunctionName), with \
               \(traceeInputCount) tracee inputs and \
               \(additionalInputTensorCount) additional inputs, and up to \
               \(tracedOutputs.count) return values.
               """)
    traceGraphFn =
      TF_GraphToFunction(graph, tracedFunctionName,
                         /*append_hash_to_fn_name*/ 0,
                         /*num_opers*/ -1,
                         /*opers*/ nil,
                         /*numinputs*/ Int32(symbolicInputs.count),
                         /*inputs*/ symbolicInputs,
                         /*noutputs*/ Int32(symbolicOutputs.count),
                         /*outputs*/ symbolicOutputs,
                         /*outputnames*/ nil,
                         /*functionoptions*/ nil, "", status)
    checkOk(status)

    if _RuntimeConfig.printsDebugLog {
      var len: Int = 0
      let funcDebugStr = TF_FunctionDebugString(traceGraphFn, &len)!
      debugLog("The traced function is:\n\(String(cString: funcDebugStr))")
      free(funcDebugStr)
    }

    // TODO: Consider garbage-collecting these trace graph functions if we end
    // up with many of them.
    let eagerContext = _TFCGetGlobalEagerContext()
    TFE_ContextAddFunction(eagerContext, traceGraphFn, status)
    checkOk(status)
  }

  /// Execute the trace graph function, and return the list of output tensors
  /// from the trace execution. These output tensors are owned by the caller.
  func execute(traceeInputs: [_AnyTensorHandle]) -> [CTensorHandle] {
    // We must be in the `notTracing` enum mode.
    internalConsistencyCheck(_RuntimeConfig.traceState.context == nil)
    internalConsistencyCheck(traceGraphFn != nil)

    let tracedFunctionName = TF_FunctionName(traceGraphFn)
    internalConsistencyCheck(tracedFunctionName != nil)
    let eagerContext = _TFCGetGlobalEagerContext()
    let op: CTFEOp! = TFE_NewOp(eagerContext, tracedFunctionName, status)
    checkOk(status)

    let deviceName = _ExecutionContext.global.currentDeviceName
    if let deviceName = deviceName {
      debugLog("Placing the trace func on device \(deviceName).")
      TFE_OpSetDevice(op, deviceName, status)
      checkOk(status)
    }

    debugLog("Adding \(traceeInputs.count) tracee input tensors.")
    internalConsistencyCheck(symbolicInputs.count == traceeInputs.count
                               + Int(additionalInputTensorCount))
    for input in traceeInputs {
      _TFCOpAddInputFromTensorHandle(op, input, status)
      checkOk(status)
    }

    debugLog("Adding \(additionalInputTensorCount) additional input tensors.")
    for i in 0..<additionalInputTensorCount {
      let input = TFE_ConsumeInputConcreteTensorFromTraceContext(cTraceContext,
                                                                 UInt32(i))
      internalConsistencyCheck(input != nil)
      debugLog("""
                 Adding additional input tensor of idx \
                 \(traceeInputs.count+Int(additionalInputTensorCount)):\
                 \(input!).
                 """)
      TFE_OpAddInput(op, input, status)
      checkOk(status)
    }

    // Tell TensorFlow to execute the graph function we built, containing
    // the trace.
    let maxReturnValueCount = tracedOutputs.count
    debugLog("""
               Executing trace func \(tracedFunctionName!) with up to \
               \(maxReturnValueCount) return values.
               """)
    var returnValues = [CTensorHandle?](repeating: nil,
                                        count: maxReturnValueCount)
    var outputReturnValueCount = Int32(maxReturnValueCount)
    TFE_Execute(op, &returnValues, &outputReturnValueCount, status)
    checkOk(status)
    debugLog("""
               returnValues.count=\(returnValues.count), \
               outputReturnValueCount=\(outputReturnValueCount).
               """)
    internalConsistencyCheck(outputReturnValueCount <= returnValues.count)

    // Now that all the output elements have been filled in, remove a level of
    // optional, and also add concrete outputs.
    var traceGraphOutputs: [CTensorHandle] = []
    // Points to an element in `returnValues`.
    var returnValueIdx = 0
    // See the comment block within finalize() below on why we handle concrete
    // and symbolic output tensors differently.
    for tracedOutput in tracedOutputs {
      if TFE_TensorHandleIsConcrete(tracedOutput) != 0 {
        // These concrete tensors are owned by some other objects, so we make a
        // copy here.
        let newOutput = TFE_TensorHandleCopySharingTensor(tracedOutput, status)
        checkOk(status)
        internalConsistencyCheck(newOutput != nil)
        traceGraphOutputs.append(newOutput!)
      } else {
        // These symbolic tensors are produced by TFE_Execute() above, and we
        // need not make an extra copy.
        internalConsistencyCheck(returnValues[returnValueIdx] != nil)
        traceGraphOutputs.append(returnValues[returnValueIdx]!)
        returnValueIdx += 1
      }
    }
    internalConsistencyCheck(returnValueIdx == outputReturnValueCount)
    return traceGraphOutputs
  }

  /// Bind data to the inputs of the graph and return the specialized graph.
  func specializeTFFunction(with dataTensors: [CTensorHandle]) -> String {
    let specializedGraph = TF_NewGraph()!

    TF_GraphCopyFunction(
      specializedGraph, traceGraphFn, /*gradient*/ nil, status)
    checkOk(status)

    let tracedFunctionName = TF_FunctionName(traceGraphFn)
    internalConsistencyCheck(tracedFunctionName != nil)
    let tracedOpDesc = TF_NewOperation(
      specializedGraph, tracedFunctionName, "tracedFn")

    // Create and append the inputs to the graph function.
    let traceeInputs = symbolicInputs.dropLast(
      dataTensors.count + Int(additionalInputTensorCount))
    var inputs: [TF_Output] = []
    for (i, traceeInput) in traceeInputs.enumerated() {
      let desc = TF_NewOperation(specializedGraph, "Placeholder", "input_\(i)")
      TF_SetAttrType(desc, "dtype", TF_OperationOutputType(traceeInput))
      let result = TF_FinishOperation(desc, status)
      checkOk(status)
      let input = TF_Output(oper: result, index: 0)
      TF_AddInput(tracedOpDesc, input)
      inputs.append(input)
    }

    // Wire the data to the corresponding inputs of the tracedOp.
    for (i, cTensorHandle) in dataTensors.enumerated() {
      let cTensor = TFE_TensorHandleResolve(cTensorHandle, status)
      checkOk(status)
      let desc = TF_NewOperation(specializedGraph, "Const", "input_const_\(i)")
      TF_SetAttrType(desc, "dtype", TFE_TensorHandleDataType(cTensorHandle))
      TF_SetAttrTensor(desc, "value", cTensor, status)
      checkOk(status)
      let result = TF_FinishOperation(desc, status)
      checkOk(status)
      TF_AddInput(tracedOpDesc, TF_Output(oper: result, index: 0))
    }

    var nextConst = dataTensors.count
    debugLog("Adding \(additionalInputTensorCount) additional input tensors.")
    for i in 0..<additionalInputTensorCount {
      let cTensorHandle =
        TFE_ConsumeInputConcreteTensorFromTraceContext(cTraceContext, UInt32(i))
      internalConsistencyCheck(cTensorHandle != nil)
      let cTensor = TFE_TensorHandleResolve(cTensorHandle, status)
      checkOk(status)
      let desc = TF_NewOperation(
        specializedGraph, "Const", "input_const_\(nextConst)")
      nextConst += 1
      TF_SetAttrType(desc, "dtype", TFE_TensorHandleDataType(cTensorHandle))
      TF_SetAttrTensor(desc, "value", cTensor, status)
      checkOk(status)
      debugLog("""
                 Adding additional input tensor of idx \
                 \(traceeInputs.count+Int(additionalInputTensorCount)):\
                 \(cTensorHandle!).
                 """)
      let result = TF_FinishOperation(desc, status)
      checkOk(status)
      TF_AddInput(tracedOpDesc, TF_Output(oper: result, index: 0))
    }

    let tracedOp = TF_FinishOperation(tracedOpDesc, status)
    checkOk(status)

    // Set up outputs.
    var outputIndex: Int32 = 0
    var outputs: [TF_Output] = []
    // Get the symbolic outputs from the output.
    for output in tracedOutputs
      where TFE_TensorHandleIsConcrete(output) == 0 {
      outputs.append(TF_Output(oper: tracedOp, index: outputIndex))
      outputIndex += 1
    }
    // Create constants for the concrete outputs.
    for output in tracedOutputs
      where TFE_TensorHandleIsConcrete(output) != 0 {
      let cTensor = TFE_TensorHandleResolve(output, status)
      checkOk(status)
      let desc = TF_NewOperation(
        specializedGraph, "Const", "output_const_\(outputIndex)")
      TF_SetAttrType(desc, "dtype", TFE_TensorHandleDataType(output))
      TF_SetAttrTensor(desc, "value", cTensor, status);
      checkOk(status)
      let result = TF_FinishOperation(desc, status)
      checkOk(status)
      outputs.append(TF_Output(oper: result, index: outputIndex))
      outputIndex += 1
    }
    let specializedTFFuncName =
      "specialized_tffunc_\(_RuntimeConfig.traceGraphFunctionCounter)"
    _RuntimeConfig.traceGraphFunctionCounter += 1

    let tffunc =
      TF_GraphToFunction(specializedGraph, specializedTFFuncName,
                         /*append_hash_to_fn_name*/ 0,
                         /*num_opers*/ -1,
                         /*opers*/ nil,
                         /*numinputs*/ Int32(inputs.count),
                         /*inputs*/ inputs,
                         /*noutputs*/ Int32(outputs.count),
                         /*outputs*/ outputs,
                         /*outputnames*/ nil,
                         /*functionoptions*/ nil, "", status)
    checkOk(status)

    if _RuntimeConfig.printsDebugLog {
      var len: Int = 0
      let funcDebugStr = TF_FunctionDebugString(tffunc, &len)!
      debugLog("Specialized TF_Function is:\n\(String(cString: funcDebugStr))")
      free(funcDebugStr)
    }
    let eagerContext = _TFCGetGlobalEagerContext()
    TFE_ContextAddFunction(eagerContext, tffunc, status)
    checkOk(status)
    return specializedTFFuncName
  }
}

// This enum keeps track of whether we are building or executing a trace.
private enum TracingState {
  case notTracing
  case tracing(TraceContext)

  // Return nil if we are not in tracing mode.
  var context: TraceContext? {
    guard case let .tracing(context) = self else { return nil }
    return context
  }
}

/// The configuration for the compiler runtime.
// TODO(hongm): Revisit the longer-term design.
// @_frozen // SR-9739
public enum _RuntimeConfig {
  // TODO: change this and subsequent properties from static to thread local.
  fileprivate static var traceState: TracingState = .notTracing

  /// Used to create unique trace graph function names.
  fileprivate static var traceGraphFunctionCounter = 0

  /// When false, tensorflow runtime will be initialized before running any
  /// tensor program in this process.
  static public var tensorFlowRuntimeInitialized = false

  /// When true, run the entire tensor computation in
  /// _TFCStartTensorComputation(), instead of running it on a separate thread.
  /// - Note: Set to true only for debugging purposes, as it has limited
  ///   functionality (e.g. no sends/recvs support).
  static public var usesSynchronousExecution = false

  /// For CPU and GPU execution without XLA, use the auto mode. For XLA and/or
  /// TPU execution, set the enum value accordingly.
  static public var executionMode: _ExecutionMode = .auto

  /// When true, let TensorFlow GPU memory allocation start small and grow as
  /// needed. Otherwise, The entire GPU memory region is pre-allocated.
  static public var gpuMemoryAllowGrowth = true

  /// The number of CPU devices.
  static public var cpuDeviceCount: UInt32 = 1

  /// When non-nil, run metadata (with full trace) of each session execution
  /// will be dumped to the give path.
  static public var runMetadataOutputPath: String? = nil

  /// Specifies whether the TensorFlow computation runs in a local (in-process)
  /// session, or a remote session with the specified server definition.
  // @_frozen // SR-9739
  public enum RuntimeSession {
    case local
    case remote(serverDef: String)
  }
  static public var session: RuntimeSession = .local

  /// When true, prints various debug messages on the runtime state.
  ///
  /// If the value is true when running tensor computation for the first time in
  /// the process, INFO log from TensorFlow will also get printed.
  static public var printsDebugLog = false

  /// Specifies the verbose log level in TensorFlow; a higher level prints out
  /// more log. Only meaningful when `printsDebugLog` is true, and must be
  /// within [0, 4] in that case.
  static public var tensorflowVerboseLogLevel: Int32 = 0 {
    willSet {
      debugLog("About to set tensorflowVerboseLogLevel to \(newValue)")
      guard newValue >= 0 && newValue <= 4 else {
        fatalError("Invalid tensorflowVerboseLogLevel value \(newValue)")
      }
    }
  }
}

private func configureRuntimeFromEnvironment() {
  if let value = getenv("SWIFT_TENSORFLOW_ENABLE_DEBUG_LOGGING"),
    String(cString: value).lowercased() == "true" {
      _RuntimeConfig.printsDebugLog = true
      debugLog("Turning on debug logging from env.")
  }

  if let value = getenv("SWIFT_TENSORFLOW_VERBOSE_LOG_LEVEL") {
    guard var verboseLevel = Int32(String(cString: value)) else {
      fatalError("SWIFT_TENSORFLOW_VERBOSE_LOG_LEVEL must take an int value.")
    }
    if verboseLevel > 4 {
      verboseLevel = 4
    }
    _RuntimeConfig.tensorflowVerboseLogLevel = verboseLevel
    debugLog("Setting TF logging verbose level to \(verboseLevel) from env.")
  }

  if let value = getenv("SWIFT_TENSORFLOW_USE_TPU_INFEED"),
    String(cString: value).lowercased() == "true" {
      _RuntimeConfig.executionMode = .tpu
      debugLog("Setting TPU execution with infeed from env.")
  }

  if let value = getenv("SWIFT_TENSORFLOW_SYNC_EXECUTION"),
    String(cString: value).lowercased() == "true" {
      _RuntimeConfig.usesSynchronousExecution = true
      debugLog("Using sync execution from env.")
  }

  if let value = getenv("SWIFT_TENSORFLOW_SERVER_ADDRESS") {
    let address = String(cString: value)
    debugLog("Env var SWIFT_TENSORFLOW_SERVER_ADDRESS has value \(address).")
    if address == "local" {
      _RuntimeConfig.session = .local
      debugLog("Using local TF session.")
    } else {
      guard let idx = address.firstIndex(of: ":"),
         let endIdx = address.index(idx, offsetBy: 3, limitedBy: address.endIndex),
         address[idx..<endIdx] == "://" else {
        fatalError("SWIFT_TENSORFLOW_SERVER_ADDRESS must start with 'grpc://'.")
      }

      let `protocol` = address[address.startIndex..<idx]
      let target = address[endIdx..<address.endIndex]
      _RuntimeConfig.session = .remote(serverDef: """
        cluster {
          job {
            name: "localhost"
            tasks {
              key: 0
              value: "127.0.0.1:0"
            }
            tasks {
              key: 1
              value: "\(target)"
            }
          }
        }
        job_name: "localhost"
        task_index: 0
        protocol: "\(`protocol`)"
        """)
      debugLog("Setting TF server address to \(address) from env.")
    }
  }

  if let value = getenv("SWIFT_TENSORFLOW_RUN_METADATA_OUTPUT") {
    let path = String(cString: value)
    _RuntimeConfig.runMetadataOutputPath = path
    debugLog("Setting run metadata output path to \(path) from env.")
  }
}

/// Initialize the TPU system.
/// - Note: This should be called only once.
/// - Precondition: The given session must contain the given graph.
// TODO(b/77572335): Reassess how to reset TPU after execution error.
private func initializeTPU(withSession session: CTFSession, graph: CTFGraph,
                           status: CTFStatus) {
  debugLog("Initializing TPU.")
  let configOp = TF_GraphOperationByName(graph, "ConfigureDistributedTPU")
  internalConsistencyCheck(configOp != nil)
  var configNode = TF_Output(oper: configOp, index: 0)
  var dummyOutput: CTensor?
  TF_SessionRun(session, nil, nil, nil, 0, &configNode, &dummyOutput, 1, nil,
                0, nil, status)
  checkOk(status)
  TF_DeleteTensor(dummyOutput)
}

/// The host of any tensor computation.
@_fixed_layout
public final class _ExecutionContext {
  /// Global context storing all available devices, loaded functions, etc.
  public static let global: _ExecutionContext = _ExecutionContext()

  // TODO: When we use remote session, we need to set cpu device to a local
  // device.  There is no C API yet to find the local device. So, we are
  // hard-coding the value for now.
  fileprivate let cpuDeviceNamePrefix = "/job:localhost/replica:0/task:0/device:CPU:"

  /// Only set when there is some usable GPU.
  fileprivate let gpuDeviceNamePrefix: String?

  /// Only set when there is some usable TPU.
  fileprivate let tpuDeviceNamePrefix: String?

  /// The buffer storing a serialized TensorFlow config proto.
  public let tensorFlowConfig: UnsafeMutablePointer<TF_Buffer>

  /// The TFE_Context object.
  @usableFromInline let eagerContext: CTFEContext

  // NOTE: the following properties are intentionally not implemented as an enum
  // due to high churn, *please do not refactor for Swiftiness*.
  /// The set of all loaded programs indexed by their unique address.
  private var loadedPrograms: [UnsafeRawPointer : CTFGraph] = [:]

  /// The status for checking TensorFlow errors.
  private let status: CTFStatus = TF_NewStatus()

  /// The mutex for preventing potential concurrent access.
  private var mutex: pthread_mutex_t = pthread_mutex_t()

  /// Initializes a new execution context by initializing available devices.
  @usableFromInline
  init() {
    configureRuntimeFromEnvironment()

    // Suppress TensorFlow logging, unless the user specified a log level.
    setenv("TF_CPP_MIN_LOG_LEVEL", "3", /*override*/ 0)

    debugLog("Initializing global context.")

    // Initialize the TF runtime exactly once. Only affects local execution
    // (when _RuntimeConfig.tensorFlowServer is set to "").
    if !_RuntimeConfig.tensorFlowRuntimeInitialized {
      InitTensorFlowRuntime(_RuntimeConfig.printsDebugLog ? 1 : 0,
                            _RuntimeConfig.tensorflowVerboseLogLevel)
      _RuntimeConfig.tensorFlowRuntimeInitialized = true
    }

    guard let opts = TFE_NewContextOptions() else {
      fatalError("ContextOptions object can never be nil.")
    }

    // Create TF config object.
    if _RuntimeConfig.executionMode == .xla {
      debugLog("Enable XLA execution.")
    }
    if _RuntimeConfig.gpuMemoryAllowGrowth {
      debugLog("Allowing growth for GPU memory allocator.")
    }
    self.tensorFlowConfig = TF_CreateConfig(
      _RuntimeConfig.executionMode == .xla ? 1 : 0,
      _RuntimeConfig.gpuMemoryAllowGrowth ? 1 : 0,
      _RuntimeConfig.cpuDeviceCount)
    TFE_ContextOptionsSetConfig(opts,
                                tensorFlowConfig.pointee.data,
                                tensorFlowConfig.pointee.length,
                                status)
    checkOk(status)

    let ctx = TFE_NewContext(opts, status)
    checkOk(status)
    self.eagerContext = ctx!
    TFE_DeleteContextOptions(opts)
    checkOk(status)

    if case .remote(let serverDef) = _RuntimeConfig.session {
      debugLog("Setting up the server def to \(serverDef)...")
      let serverDef: UnsafeMutablePointer! =
        TFE_GetServerDef(serverDef, status)
      checkOk(status)
      TFE_ContextSetServerDef(eagerContext, /*keep_alive_secs*/0,
        serverDef.pointee.data, serverDef.pointee.length, status)
      checkOk(status)
      TF_DeleteBuffer(serverDef)
    }

    // Initialize GPU device.
    // While the code here is only needed when _RuntimeConfig.executionMode is
    // set to .gpu, running it in all code paths helps keep things simple
    // (e.g. so that the cpuDeviceNamePrefix property is always set.)
    let devices = TFE_ContextListDevices(eagerContext, status)
    checkOk(status)
    defer { TF_DeleteDeviceList(devices!) }

    // Sanity check and gather/log device info. When `gpuCount` > 0, set
    // `self.gpuDeviceNamePrefix`. Likewise with `tpuCount`.
    let deviceCount = TF_DeviceListCount(devices!)
    debugLog("There are \(deviceCount) devices.")
    var foundCPU = false
    var gpuCount = 0
    var tpuCount = 0
    for deviceId in 0..<deviceCount {
      let cDeviceName = TF_DeviceListName(devices, deviceId, status)
      checkOk(status)
      let deviceName = String(cString: cDeviceName!)
      let cDeviceType = TF_DeviceListType(devices, deviceId, status)
      checkOk(status)
      let deviceType = String(cString: cDeviceType!)
      debugLog(
        "Device \(deviceId) has type \(deviceType) and name \(deviceName)."
      )
      if deviceType == "CPU", deviceName.starts(with: cpuDeviceNamePrefix) {
        foundCPU = true
      }
      if deviceType == "GPU" {
        gpuCount += 1
      }
      if deviceType == "TPU" {
        tpuCount += 1
      }
    }
    guard foundCPU else {
      fatalError("CPU should always be an available device.")
    }
    // We ignore the number of GPUs for now. It might be useful to cross check
    // that against the number of GPUs that user intends to use (e.g. via the
    // `withDevice` syntax).
    if gpuCount > 0 {
      self.gpuDeviceNamePrefix = "/job:localhost/replica:0/task:0/device:GPU:"
    } else {
      self.gpuDeviceNamePrefix = nil
    }

    if tpuCount > 0 {
      // According to server def generated when you set
      // SWIFT_TENSORFLOW_SERVER_ADDRESS, the TPUs will all be on task 1.
      self.tpuDeviceNamePrefix = "/job:localhost/replica:0/task:1/device:TPU:"
    } else {
      self.tpuDeviceNamePrefix = nil
    }

    // Initialize the mutex.
    pthread_mutex_init(&mutex, nil)
  }

  deinit {
    debugLog("De-initializing global context.")
    // Delete all loaded programs.
    TFE_DeleteContext(eagerContext)
    TF_DeleteBuffer(tensorFlowConfig)
    TF_DeleteStatus(status)
    pthread_mutex_destroy(&mutex)
  }
}

// Elements in `outputs` can come from two sources:
// a) Symbolic tensors produced by tensor ops, and added as trace graph nodes.
// b) Concrete tensors produced by host code (e.g. Tensor(1.0)).
fileprivate func finalizeTraceFunction(_ name: String) -> TraceContext {
  guard let traceContext = _RuntimeConfig.traceState.context else {
    fatalError("Not in tracing mode!.")
  }
  _RuntimeConfig.traceState = .notTracing
  traceContext.finalize(traceeBasicName: name)
  return traceContext
}

private extension TensorArrayProtocol {
  // The returned handles are owned by the caller.
  var cTensorHandles: [CTensorHandle] {
    debugLog("Getting \(self._tensorHandleCount) C handles.")
    let buffer = UnsafeMutablePointer<CTensorHandle>.allocate(
      capacity: Int(self._tensorHandleCount))
    debugLog("Unpacking handles into buffer.")
    _unpackTensorHandles(into: buffer)
    let status = TF_NewStatus()
    debugLog("Copying buffer content to output handles.")
    var output: [CTensorHandle] = []
    for i in 0..<Int(_tensorHandleCount) {
      let address = buffer.advanced(by: i)
      let isConcrete = TFE_TensorHandleIsConcrete(address.pointee) != 0
      debugLog("""
                 Copying the \(i)-th C handle \(address.pointee) with \
                 concrete=\(isConcrete).
                 """)
      let newHandle = TFE_TensorHandleCopySharingTensor(address.pointee,
                                                        status)
      checkOk(status)
      internalConsistencyCheck(newHandle != nil)
      debugLog("""
                 Copying the \(i)-th C handle \(address.pointee) with \
                 concrete=\(isConcrete) to C handle create \(newHandle!).
                 """)
      output.append(newHandle!)
    }
    TF_DeleteStatus(status)
    return output
  }
}

private extension TensorGroup {
  // The tensors in `input` are NOT owned by this instance.
  init<C: Collection>(_copying input: C) where C.Element == CTensorHandle {
    assert(Self._tensorHandleCount == input.count)
    let buffer = UnsafeMutablePointer<CTensorHandle>.allocate(
      capacity: input.count)
    let status = TF_NewStatus()
    // copy input to buffer
    for (i, inputTensorHandle) in input.enumerated() {
      let address = buffer.advanced(by: i)
      // Each tensor can be symbolic (e.g. when using this API to create a
      // symbolic input instance to tracee) or concrete (e.g. when creating the
      // final output of the tracee).
      let newHandle = TFE_TensorHandleCopySharingTensor(inputTensorHandle,
                                                        status)
      checkOk(status)
      address.initialize(to: newHandle!)
    }
    TF_DeleteStatus(status)
    self.init(_owning: buffer)
  }
}

// TODO: Fold this protocol into TensorArrayProtocol.
// This requires that we move concrete implementation such as
// Tensor._makeInstance() to TensorGroup.swift.
public protocol _TensorArrayProtocolEnhanced : TensorArrayProtocol {
  // Create an instance based on `inputs`, which can be symbolic (e.g. when
  // creating a symbolic input to tracee) or concrete (e.g. when creating a
  // final output of executing the tracee).
  func _makeInstance<C: Collection>(owning inputs: C) -> Self
    where C.Element == CTensorHandle
}


extension _TensorArrayProtocolEnhanced {
  var _dtypes: [TF_DataType] {
    let count = Int(_tensorHandleCount)
    let buffer =
        UnsafeMutableBufferPointer<CTensorHandle>.allocate(capacity: count)
    defer { buffer.deallocate() }
    _unpackTensorHandles(into: buffer.baseAddress)
    return buffer.map { TFE_TensorHandleDataType($0) }
  }
}

/// Trace `fn` with newly created tensor handles and return a trace context.
private func _trace(
  with dtypes: [TF_DataType],
  in fn: ([CTensorHandle]) -> [CTensorHandle]
) -> TraceContext {
  debugLog("""
             Tracing over a function with \(dtypes.count) inputs.
             """)

  // Verify that we are not already tracing.
  internalConsistencyCheck(_RuntimeConfig.traceState.context == nil,
                           "Should not be in tracing mode already!")

  // Switch to tracing mode.
  let traceCtx = TraceContext(dtypes: dtypes)
  _RuntimeConfig.traceState = .tracing(traceCtx)

  // Handle inputs.
  let inputSymbolicTensors = traceCtx.symbolicInputs.map {
    TFE_NewTensorHandleFromTFOutput($0, TF_OperationOutputType($0))!
  }
  internalConsistencyCheck(inputSymbolicTensors.count == dtypes.count)

  // Run tracee to build the trace, adding ops to the trace graph function.
  // The tracee output can contain a mixture of symbolic and concrete tensors
  // (see the comment block within TraceContext.finalize()).
   debugLog("Running tracee in tracing mode.")
  traceCtx.tracedOutputs = fn(inputSymbolicTensors)

  debugLog("Finalizing trace graph function.")
  // TAP means tensor array protocol.
  let opType = "MyTraceFn_TAP"
  return finalizeTraceFunction(opType)
}

private func _graphInternal<State : _TensorArrayProtocolEnhanced,
                            Data : TensorGroup,
                            Result : TensorGroup>(
  with state: State,
  in fn: (State, Data) -> (State, Result?)
) -> (State, Data) -> (State, Result?) {
  let traceContext: TraceContext = withoutActuallyEscaping(fn) { escapableFn in
    let wrappedFn = { (inputs: [CTensorHandle]) -> [CTensorHandle] in
      let symbolicState = state._makeInstance(
        owning: inputs.dropLast(Data._typeList.count))
      let symbolicData = Data(
        _copying: inputs.dropFirst(Int(state._tensorHandleCount)))
      let (outputState, outputResult) = escapableFn(symbolicState, symbolicData)

      debugLog("Assembling output tensor handles.")
      let outputs =
        outputResult != nil
          ? (outputState.cTensorHandles + outputResult!.cTensorHandles)
          : outputState.cTensorHandles
      return outputs
    }
    let dtypes = state._dtypes + Data._typeList.map { $0._cDataType }
    return _trace(with: dtypes, in: wrappedFn)
  }
  // The result is a closure that captures and executes the trace graph
  // function in the trace context.
  return { (oldState: State, data: Data) -> (State, Result?) in
    debugLog("Running trace function over state \(oldState) and data \(data).")

    debugLog("Getting input state tensor handles.")
    let inputStateTensorHandles =  oldState.cTensorHandles
    var inputTensors = inputStateTensorHandles.map {
      _TFCCreateTensorHandleFromC($0)
    }
    debugLog("Getting input data tensor handles.")
    let inputDataTensorHandles =  data.cTensorHandles
    inputTensors.append(contentsOf: inputDataTensorHandles.map {
      _TFCCreateTensorHandleFromC($0)
    })

    debugLog("Executing trace graph function.")
    let returnValues = traceContext.execute(traceeInputs: inputTensors)

    debugLog("Creating output model instance.")
    let newState = state._makeInstance(owning: returnValues.prefix(
                                         Int(state._tensorHandleCount)))
    let resultValues = returnValues.dropFirst(Int(state._tensorHandleCount))
    let result = resultValues.isEmpty ? nil : Result(_copying: resultValues)
    return (newState, result)
  }
}

// TODO: rename this to `graph` when it's ready for end users.
public func _graph<State : _TensorArrayProtocolEnhanced,
                   Data : TensorGroup,
                   Result : TensorGroup>(
  with state: State,
  in fn: (State, Data) -> (State, Result)
) -> (State, Data) -> (State, Result) {
  let graphFunction = _graphInternal(with: state, in: fn)
  return { (state: State, data: Data) in
    let result = graphFunction(state, data)
    internalConsistencyCheck(result.1 != nil)
    return (result.0, result.1!)
  }
}

// TODO: rename this to `graph` when it's ready for end users.
public func _graph<State : _TensorArrayProtocolEnhanced,
                   Data : TensorGroup>(
  with state: State,
  in fn: (State, Data) -> State
) -> (State, Data) -> State {
  let graphFunction: (State, Data) -> (State, Tensor<Float>?) =
    withoutActuallyEscaping(fn) { escapableFn in
      let wrappedFn = {
        // The result argument needs to a type that conforms to TensorGroup.
        // We are arbitrarily picking Tensor<Float> here.
        (s: State, d: Data) -> (State, Tensor<Float>?) in
          (escapableFn(s, d), nil)
      }
      return _graphInternal(with: state, in: wrappedFn)
    }
  return { (state: State, data: Data) in graphFunction(state, data).0 }
}

/// Trace the given function `fn` and return a closure that can be used to
/// create a `TF_Function(State)` specialized for `data`.
public func _tffunc<State : _TensorArrayProtocolEnhanced,
                    Data : TensorGroup>(
  with state: State,
  in fn: (State, Data) -> State
) -> (Data) -> (String) {
  let traceContext: TraceContext = withoutActuallyEscaping(fn) { escapableFn in
    let wrappedFn = { (inputs: [CTensorHandle]) -> [CTensorHandle] in
      let symbolicState = state._makeInstance(
        owning: inputs.dropLast(Data._typeList.count))
      let symbolicData = Data(
        _copying: inputs.dropFirst(Int(state._tensorHandleCount)))
      let outputState = escapableFn(symbolicState, symbolicData)
      return outputState.cTensorHandles
    }
    let dtypes = state._dtypes + Data._typeList.map { $0._cDataType }
    return _trace(with: dtypes, in: wrappedFn)
  }
  return {
    data in traceContext.specializeTFFunction(with: data.cTensorHandles)
  }
}

/// Trace the given function and return the name of the corresponding
/// `TF_Function: In -> Out` that was created.
public func _tffunc<In : TensorGroup, Out : TensorGroup>(
  _ fn: (In) -> Out
) -> String {
  let traceContext: TraceContext = withoutActuallyEscaping(fn) { escapableFn in
    let wrappedFn = {
      (inputs: [CTensorHandle]) -> [CTensorHandle] in
      let buffer = UnsafeMutablePointer<CTensorHandle>.allocate(
        capacity: Int(inputs.count))
      var ptr = buffer
      for input in inputs {
        ptr.initialize(to: input)
        ptr = ptr.advanced(by: 1)
      }
      let symbolicIn = In(_owning: buffer)
      let symbolicOut = escapableFn(symbolicIn)
      return symbolicOut.cTensorHandles
    }
    
    let dtypes = In._typeList.map { $0._cDataType }
    return _trace(with: dtypes, in: wrappedFn)
  }
  return traceContext.specializeTFFunction(with: [])
}

/// Returns a valid TF device string such as
/// "/job:localhost/replica:0/task:0/device:CPU:0", which corresponds to the
/// closest enclosing withDevice() construct.
/// A return value of nil indicates the absence of withDevice().
internal extension _ExecutionContext {
  @usableFromInline
  var currentDeviceName: String? {
    if let (kind, index) = _ThreadLocalState.value._currentDevice {
      switch kind {
      case .cpu:
        return "\(cpuDeviceNamePrefix)\(index)"
      case .gpu:
        return "\(gpuDeviceNamePrefix!)\(index)"
      case .tpu:
        return "\(tpuDeviceNamePrefix!)\(index)"
      }
    }
    return nil
  }
}

internal extension _ExecutionContext {
  /// Synchronously execute the body, preventing asynchronous computation from
  /// corrupting the context data.
  private func sync<Result>(
    execute body: () throws -> Result
  ) rethrows -> Result {
    let lockStatus = pthread_mutex_lock(&mutex)
    internalConsistencyCheck(lockStatus == 0)
    defer {
      let unlockStatus = pthread_mutex_unlock(&mutex)
      internalConsistencyCheck(unlockStatus == 0)
      // Create a cancellation point.
      pthread_testcancel()
    }
    return try body()
  }
}

fileprivate extension _ExecutionContext {
  /// Load the graph functions of a serialized TensorFlow GraphDef binary proto
  /// into the context, if that has not been done yet. Return the graph.
  /// - Parameters:
  ///   - address: The address of the serialized program in memory.
  ///   - count: The size of the program in bytes.
  func loadProgramInBytes(_ address: UnsafeRawPointer, count: Int) -> CTFGraph {
    return sync {
      debugLog("Loading a program.")
       // If the program is already loaded, do nothing.
      if let graph = loadedPrograms[address] {
        return graph
      }
      // Here we have to do a fairly awkward dance to load the graph functions
      // and populate them into the TFE_Context.  We load the program as a
      // TF_Graph, then copy the functions out of it, then copy them into the
      // TFE_Context.
      debugLog("Loading graph functions.")
      let graph = TF_NewGraph()!
      // TensorFlow loads things through TF_Buffer.  Create one that avoids
      // redundantly copying the program bytes.
      var programBuf = TF_Buffer(data: address, length: count,
                                 data_deallocator: nil)
      let graphDefOptions = TF_NewImportGraphDefOptions()
      TF_GraphImportGraphDef(graph, &programBuf, graphDefOptions, self.status)
      TF_DeleteImportGraphDefOptions(graphDefOptions)
      checkOk(self.status)
      // Now that we have all of the TF_Function objects in the graph, copy them
      // to standalone TF_Function's.
      let funcCount = TF_GraphNumFunctions(graph)
      // Allocate an array to accept functions.
      var funcs: [CTFFunction?] = Array(repeating: nil, count: Int(funcCount))
      TF_GraphGetFunctions(graph, &funcs, funcCount, self.status)
      checkOk(self.status)

      // Add functions to the context.
      debugLog("Adding \(funcCount) functions to context.")
      for function in UnsafeBufferPointer(start: funcs, count: Int(funcCount)) {
        TFE_ContextAddFunction(self.eagerContext, function, self.status)
        checkOk(self.status)
        debugLog("Added func \(String(cString: TF_FunctionName(function))).")
        TF_DeleteFunction(function)
      }

       // Memorize the loaded program by address.
      loadedPrograms[address] = graph
      debugLog("Done loading a new program.")
      return graph
    }
  }
}

public extension _ExecutionContext {
  /// Load functions from a graph encoded as a byte-pointer and length into the
  /// tensorflow eagerContext.
  func loadFunctionsFromGraph(byteAddress: UnsafeRawPointer, byteCount: Int) {
    _ = loadProgramInBytes(byteAddress, count: byteCount)
  }
}

@usableFromInline
internal func dumpTensorContent<Scalar : _TensorFlowDataTypeCompatible>(
  _ inputTensor: CTensorHandle, _: Scalar.Type
) {
  assert(TFE_TensorHandleIsConcrete(inputTensor) != 0)

  let array = ShapedArray<Scalar>(cTensorHandle: inputTensor)
  debugLog("Rank is \(array.rank), shape is \(array.shape).")
  debugLog("""
    The content of the \(array.scalars.count) scalars are: \
    \(array.scalars).
    """)
}

@usableFromInline
internal func dumpCTensorHandleContent(
  _ idx: Int,
  _ inputTensorHandle: CTensorHandle) {
  if TFE_TensorHandleIsConcrete(inputTensorHandle) == 0 {
    debugLog("Skip dumpping a symbolic tensor handle.")
    return
  }

  let dType: TF_DataType = TFE_TensorHandleDataType(inputTensorHandle)
  debugLog("Tensor \(idx) has TF data type \(dType).")
  switch dType {
  case TF_UINT8: dumpTensorContent(inputTensorHandle, UInt8.self)
  case TF_INT8: dumpTensorContent(inputTensorHandle, Int8.self)
  case TF_UINT16: dumpTensorContent(inputTensorHandle, UInt16.self)
  case TF_INT16: dumpTensorContent(inputTensorHandle, Int16.self)
  case TF_UINT32: dumpTensorContent(inputTensorHandle, UInt32.self)
  case TF_INT32: dumpTensorContent(inputTensorHandle, Int32.self)
  case TF_UINT64: dumpTensorContent(inputTensorHandle, UInt64.self)
  case TF_INT64: dumpTensorContent(inputTensorHandle, Int64.self)
  case TF_FLOAT: dumpTensorContent(inputTensorHandle, Float.self)
  case TF_DOUBLE: dumpTensorContent(inputTensorHandle, Double.self)
  case TF_BOOL: dumpTensorContent(inputTensorHandle, Bool.self)
  // TODO: Handle `TF_BFloat16`? BFloat16 does not have a host-side
  // representation and cannot be printed directly. Consider calling into TF
  // runtime.
  default: fatalError("Unsupported dtype \(dType)")
  }
}

private class TFEState {
  let status: CTFStatus = TF_NewStatus()
  /// The set of graph functions to be concurrently executed (as TFE ops).
  ///
  /// The first one is on the primary device, handling input and output
  /// tensors. The other ones are helper functions that are executed only for
  /// their side effects (e.g. sending and receiving tensors with the primary
  /// function).
  var ops: [CTFEOp] = []
  init(_ programByteAddress: UnsafeRawPointer,
       programByteCount: Int,
       helperFunctionCount: Int,
       entryFunctionBaseNameAddress: UnsafePointer<Int8>) {

    // Given an input like "foo.tf_13" (prefix if a SIL graph function like
    // "foo.tf_13_CPU.device_partition"), extract and return "13" as the device
    // index.
    func deviceIndexSubstring(from opTypePrefix: Substring) -> Substring {
      let underscorePos = opTypePrefix.lastIndex(of: "_")
      internalConsistencyCheck(
        underscorePos != nil,
        "Malformed op type prefix \(opTypePrefix)")
      let startPos = opTypePrefix.index(after: underscorePos!)
      let deviceIndexStr = opTypePrefix.suffix(from: startPos)
      return deviceIndexStr
    }

    let context = _ExecutionContext.global
    // Make sure the program is loaded into the context.
    let graph = context.loadProgramInBytes(programByteAddress,
                                           count: programByteCount)

    let entryFunctionBaseName = String(cString: entryFunctionBaseNameAddress)
    debugLog("Looking up op(s) from func base name \(entryFunctionBaseName).")
    for i in 0...helperFunctionCount {
      // Also look up in the TensorFlow program a function name (op type) based
      // on the op name. e.g. given op name "tfc_func_S4mainyycfU_.tf", return
      // op type "S4mainyycfU_.tf_CPU.device_partition". TFE ops are created by
      // the op types.
      var opName = "tfc_func_" + entryFunctionBaseName;
      if i > 0 {
        opName += "_helper_\(i-1)"
      }
      let funcNode = TF_GraphOperationByName(graph, opName)
      internalConsistencyCheck(
        funcNode != nil,
        "Cannot find func node name \(opName)"
      )

      let opType = String(cString: TF_OperationOpType(funcNode))
      debugLog("Creating a new op based on type \(opType).")
      let op: CTFEOp? = TFE_NewOp(context.eagerContext, opType, status)
      checkOk(status)
      let deviceName: String?
      if opType.hasSuffix("_RUNTIME.device_partition") {
        deviceName = _ExecutionContext.global.currentDeviceName
      } else if opType.hasSuffix("_CPU.device_partition") {
        // The op type can be: tmp3_main.tf_17_CPU.device_partition. We want to
        // extract the device index "17" out of the above name, and use it to
        // form a TF device string like
        // "/job:localhost/replica:0/task:0/device:CPU:17".
        let opTypePrefix = opType.dropLast("_CPU.device_partition".count)
        let deviceIndexStr = deviceIndexSubstring(from: opTypePrefix)
        deviceName = context.cpuDeviceNamePrefix + deviceIndexStr
      } else {
        // TODO: support TPU as well.
        internalConsistencyCheck(opType.hasSuffix("_GPU.device_partition"))
        internalConsistencyCheck(context.gpuDeviceNamePrefix != nil)
        let opTypePrefix = opType.dropLast("_GPU.device_partition".count)
        let deviceIndexStr = deviceIndexSubstring(from: opTypePrefix)
        deviceName = context.gpuDeviceNamePrefix! + deviceIndexStr
      }
      if let deviceName = deviceName {
        debugLog("Placing the op on device \(deviceName).")
        TFE_OpSetDevice(op, deviceName, status)
        checkOk(status)
      } else {
        debugLog("Not placing the op on any device.")
      }
      ops.append(op!)
    }
  }
  deinit {
    for op in ops {
      TFE_DeleteOp(op)
    }
    TF_DeleteStatus(status)
  }
}

extension TFEState {
  func addInput(_ inputTensorHandle: CTensorHandle) {
    TFE_OpAddInput(ops[0], inputTensorHandle, status)
  }
}

//===----------------------------------------------------------------------===//
// - MARK: Tensor computation
//===----------------------------------------------------------------------===//

/// Tensor computation.
///
/// - Note: The call sequence for the APIs below must be one of the two:
///   `init -> terminate()` or `init -> finish()`.
///   The finish/terminate APIs may only be called once.
@_fixed_layout
public final class _TensorComputation {
  /// The status for checking TensorFlow errors.
  let status: CTFStatus = TF_NewStatus()

  /// The base name for the set of graph functions to execute in this instance.
  let entryFunctionBaseName: String

  /// The number of helper functions associated with this TF graph
  /// execution. For a graph execution over N TF devices, there is a single
  /// *primary* graph function, responsible for taking input and producing
  /// output tensors as part of the SessionRun() spec. The other N-1 graph
  /// functions are *helper* functions, executed together with the primary one
  /// for their side-effects, such as sending/receiving tensors, "helping" the
  /// primary function produce the desired output tensors and side effects as
  /// needed by the SessionRun() call.
  let helperFunctionCount: Int

  /// The tensor handles returned by the tensor program.
  // TODO(hongm): Retire returnValues when eager based runtime is removed.
  var returnValues: [CTensorHandle?]

  private var state: TFEState

  /// The threads to run tensor computation in. In eager mode, we use N threads
  /// when the tensor computation involves N device functions. In non-eager
  /// mode, we use a single thread (that's sufficient as these N device
  /// functions can be sent to the same TF_SessionRun() call.)
  ///
  /// The global config flag '_RuntimeConfig.usesSynchronousExecution' decides
  /// whether tensor computation should be synchronous: if true, this property
  /// will always be empty. Otherwise, this property is non-empty only when the
  /// tensor computation is on-going.
  /// TODO: Remove the `usesSynchronousExecution` mode as it is very limiting
  /// (e.g. does not support running multiple device functions).
  private var pthreads: [pthread_t] = []

  /// The data structure to pass into pthread creation API.
  /// We cannot have the ThreadBody closure below close over on `threadIndex`,
  /// because ThreadBody is of C convention.
  private class ThreadParam {
    let computation: _TensorComputation
    let threadIndex: Int

    init(computation: _TensorComputation, threadIndex: Int) {
      self.computation = computation
      self.threadIndex = threadIndex
    }
  }

  /// Loads the TF program from a binary TF FunctionDef proto given by
  /// 'programByteAddress' and 'programByteCount', and start the computation.
  ///
  /// - Parameters:
  ///   - programByteAddress: The address of the raw program.
  ///   - programByteCount: The number of bytes in the program.
  ///   - entryFunctionBaseNameAddress: The base name of the functions to run.
  ///   - tensorArgumentAddress: The address to the buffer containing tensor
  ///     arguments as CTensorHandle.
  ///   - tensorArgumentCount: The number of tensor arguments to pass in.
  ///   - helperFunctionCount: The number of helper functions to run.
  ///   - resultCount: The number of output tensors.
  ///
  /// - TODO(clattner): `resultCount` should go away when the runtime is
  ///   implemented with an async design.
  @usableFromInline
  init(programByteAddress: UnsafeRawPointer,
       programByteCount: Int,
       entryFunctionBaseNameAddress: UnsafePointer<Int8>,
       tensorArgumentAddress: UnsafePointer<CTensorHandle>,
       tensorArgumentCount: Int,
       helperFunctionCount: Int,
       resultCount: Int) {
    configureRuntimeFromEnvironment()

    let inputTensorHandles = UnsafeBufferPointer(start: tensorArgumentAddress,
                                                 count: tensorArgumentCount)

    // Initialize global execution context if that's not yet done. It caches all
    // our tensor programs.
    _ = _ExecutionContext.global

    if _RuntimeConfig.printsDebugLog {
      let buffer = UnsafeBufferPointer(
        start: programByteAddress.assumingMemoryBound(to: UInt8.self),
        count: programByteCount)
      debugLog("The program bytes are \(Array(buffer)).")
    }

    // Now that we have them in our context, we can get ready to get the top
    // level function and create an op.
    self.entryFunctionBaseName = String(cString: entryFunctionBaseNameAddress)
    debugLog("""
      Creating a new op with func base name \
      \(String(cString: entryFunctionBaseNameAddress)).
      """)
    self.helperFunctionCount = helperFunctionCount
    self.state = TFEState(
        programByteAddress,
        programByteCount: programByteCount,
        helperFunctionCount: helperFunctionCount,
        entryFunctionBaseNameAddress: entryFunctionBaseNameAddress)
      debugLog("Done initializing TFE-specific state.")

    debugLog("Populating the op's input list.")
    for (i, inputTensorHandle) in inputTensorHandles.enumerated() {
      if _RuntimeConfig.printsDebugLog {
        dumpCTensorHandleContent(i, inputTensorHandle)
      }
      state.addInput(inputTensorHandle)
    }

    debugLog("Created returning info.")
    self.returnValues = Array(repeating: nil, count: resultCount)

    debugLog("Starting TF graph execution.")

    // If it's asynchronous, we execute the tensor computation via threads.
    if !_RuntimeConfig.usesSynchronousExecution {
      let threadCount = helperFunctionCount + 1
      for threadIndex in 0..<threadCount {
        // The function to launch in the parallel thread.
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        typealias ThreadBody = @convention(c)
          (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer?
#else
        typealias ThreadBody = @convention(c)
          (UnsafeMutableRawPointer?) -> UnsafeMutableRawPointer?
#endif
        let body: ThreadBody = { arg in
          // Set the cancelability of the detached thread.
          pthread_setcanceltype(Int32(PTHREAD_CANCEL_DEFERRED), nil)
          // Execute the tensor computation.
#if !(os(macOS) || os(iOS) || os(watchOS) || os(tvOS))
          let arg = arg!
#endif
          let param: ThreadParam =
            Unmanaged.fromOpaque(arg).takeRetainedValue()
          param.computation.execute(threadIndex: param.threadIndex)
          checkOk(param.computation.status)
          return nil
        }
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
        var newThread: pthread_t!
#else
        var newThread = pthread_t()
#endif
        let creationStatus = pthread_create(
          &newThread, nil, body,
          Unmanaged.passRetained(
            ThreadParam(computation: self,
                        threadIndex: threadIndex)).toOpaque()
        )
        // TODO(hongm): do error handling.
        internalConsistencyCheck(creationStatus == 0)
        pthreads.append(newThread)
      }
    }
    // If it's synchronous, we call execute() on the main thread directly.
    else {
      // Log a debug message to differentiate from async computation.
      debugLog("Running tensor computation synchronously.")
      execute(threadIndex: 0)
    }
    debugLog("Exiting _TensorComputation.init().")
  }

  deinit {
    debugLog("De-initializing _TensorComputation.")
    TF_DeleteStatus(status)
  }
}

private extension _TensorComputation {
  /// In eager mode, runs a device function in a corresponding thread given by
  /// `threadIndex`. Otherwise, runs all devices functions of the tensor
  /// program. Aborts the process on error, and emits an error string to STDERR.
  // NOTE: This is to be called by the initializer. The computation gets
  // executed on initialization, thus this method will not be exposed to users.
  private func execute(threadIndex: Int) {
    debugLog("Executing thread \(threadIndex).")
    internalConsistencyCheck(threadIndex <= helperFunctionCount)
    let op = state.ops[threadIndex]
    if threadIndex == 0 {
      var returnValueCount = Int32(returnValues.count)
      TFE_Execute(op, &returnValues, &returnValueCount, status)
      debugLog("""
                 returnValues.count=\(returnValues.count), \
                 returnValueCount=\(returnValueCount).
                 """)
      internalConsistencyCheck(returnValueCount == returnValues.count)
    } else {
      var returnValueCountForHelper: Int32 = 0
      TFE_Execute(op, /*returnValues*/nil, &returnValueCountForHelper, status)
      internalConsistencyCheck(returnValueCountForHelper == 0)
    }
    checkOk(status)

    debugLog("Done execution with eager.")
  }
}

public extension _TensorComputation {
  /// Terminates the computation, and clean up the state.
  func terminate() {
    for pthread in pthreads {
      // TODO(hongm): Assess TF's thread cancel support.
      let cancelStatus = pthread_cancel(pthread)
      internalConsistencyCheck(cancelStatus == 0)
    }
    pthreads.removeAll()
  }

  /// Waits for completion the computation as given by 'program', and returns
  /// output handles, whose underlying tensors may live on CPU or GPU.
  /// Aborts the process on error, and emits an error string to STDERR.
  func finish() -> [CTensorHandle] {
    debugLog("Calling _TensorComputation.finish().")
    if pthreads.isEmpty {
      internalConsistencyCheck(
        _RuntimeConfig.usesSynchronousExecution, """
          finish() is called in async execution mode with pthread == nil -- \
          Was finish() already called?
          """)
    }
    for pthread in pthreads {
      debugLog("Waiting for thread to join.")
      let joinStatus = pthread_join(pthread, nil)
      internalConsistencyCheck(joinStatus == 0)
    }
    pthreads.removeAll()
    debugLog("Done executing TF graph.")

    // Now that all the elements have been filled in, remove a level of
    // optional.
    return returnValues.map { $0! }
  }
}

@usableFromInline
@_cdecl("_swift_tfc_EagerExecute")
func _TFCEagerExecute(_ op: CTFEOp,
                      _ retvals: UnsafeMutablePointer<OpaquePointer?>,
                      _ retvalCount: UnsafeMutablePointer<Int32>,
                      _ status: CTFStatus) {
  if _RuntimeConfig.printsDebugLog {
    debugLog("Calling _TFCEagerExecute() over: ")
    TFE_OpPrintDebugString(op)
  }
  if let traceContext = _RuntimeConfig.traceState.context {
    // convert this eager op into a trace graph node
    debugLog("Adding eager op \(op) to trace graph.")
    traceContext.addEagerOpToGraph(op, retvals, retvalCount, status)
    checkOk(status)
  } else {
    debugLog("Executing eager op \(op).")
    TFE_Execute(op, retvals, retvalCount, status)
  }
}

//===----------------------------------------------------------------------===//
// - MARK: Compiler runtime entrypoints
//===----------------------------------------------------------------------===//
// These are the entrypoints that are well-known to the compiler internals.  The
// signatures and forms must not be changed without updating the compiler.  Any
// code put into the body of these functions will end up being inlined into the
// user code, so they are generally just wrappers around the implementation
// above.

/// Loads the TF computation from a binary TF FunctionDef proto given by 'bytes'
/// and 'size', start the computation, and return a _TensorComputation object as
/// a unique identifier for that computation.
///
/// - Parameters:
///   - programByteAddress: The address of the raw program.
///   - programByteCount: The number of bytes in the program.
///   - entryFunctionBaseNameAddress: The base name of the functions to run.
///   - tensorArgumentAddress: The address to the buffer containing tensor
///     arguments as CTensorHandle.
///   - tensorArgumentCount: The number of tensor arguments to pass in.
///   - helperFunctionCount: The number of helper functions to run.
///   - resultCount: The number of output tensors.
@inlinable
@_silgen_name("_swift_tfc_StartTensorComputation")
public func _TFCStartTensorComputation(
  _ programByteAddress: UnsafeRawPointer,
  _ programByteCount: Int,
  _ entryFunctionBaseNameAddress: UnsafePointer<Int8>,
  _ tensorArgumentAddress: UnsafePointer<CTensorHandle>,
  _ tensorArgumentCount: Int,
  _ helperFunctionCount: Int,
  _ resultCount: Int
) -> _TensorComputation {

  debugLog("""
    _TFCStartTensorComputation() is called with \(programByteCount) \
    program bytes, \(tensorArgumentCount) input tensors \
    \(String(cString:entryFunctionBaseNameAddress)) as the func base name, \
    \(helperFunctionCount) helper functions, and \(resultCount) output tensors.
    """)

  internalConsistencyCheck(programByteCount > 0, "Cannot run an empty graph!")

  return _TensorComputation(programByteAddress: programByteAddress,
                            programByteCount: programByteCount,
                            entryFunctionBaseNameAddress: entryFunctionBaseNameAddress,
                            tensorArgumentAddress: tensorArgumentAddress,
                            tensorArgumentCount: tensorArgumentCount,
                            helperFunctionCount: helperFunctionCount,
                            resultCount: resultCount)
}

/// Waits for completion of the computation as given by `computation`, and
/// returns results.
/// Aborts the process on error, and emits an error string to STDERR.
///
/// - Parameters:
///   - computation: The tensor computation to finish.
///   - tensorResultAddress: The address to an uninitialized buffer to accept
///     results of the computation, where the output tensors may live on CPU or
///     GPU.
///   - tensorResultCount: The number of results to accept from the computation.
/// - Note: The result address as passed in is pointing to uninitialized memory,
///   this must initialize the memory, transferring ownership of the tensor
///   handles to the caller.
@inlinable
@_silgen_name("_swift_tfc_FinishTensorComputation")
public func _TFCFinishTensorComputation(
  _ computation: _TensorComputation,
  _ tensorResultAddress: UnsafeMutablePointer<CTensorHandle>,
  _ tensorResultCount: Int
) {
  debugLog("Expecting \(tensorResultCount) output tensors.")
  let results = computation.finish()
  internalConsistencyCheck(results.count == tensorResultCount,
    "internal compiler error: result count mismatch!")
  tensorResultAddress.initialize(from: results, count: tensorResultCount)
}

/// Terminates the computation as given by 'program', and clean up the state.
///
/// - Parameters:
///   - program: The tensor program to terminate.
/// - Note: If the execution was synchronous, then this function does nothing.
@inlinable
@_silgen_name("_swift_tfc_TerminateTensorComputation")
public func _TFCTerminateTensorComputation(_ computation: _TensorComputation) {
  computation.terminate()
}

/// Registers all functions in a graph into the eager context if in eager mode.
///
/// - Parameters:
///   - programByteAddress: The address of the raw program.
///   - programByteCount: The number of bytes in the program.
@inlinable
@_silgen_name("_swift_tfc_RegisterTensorFunctions")
public func _TFCRegisterTensorFunctions(
  _ programByteAddress: UnsafeRawPointer,
  _ programByteCount: Int
) {
  _ExecutionContext.global.loadFunctionsFromGraph(byteAddress: programByteAddress,
                                                  byteCount: programByteCount)
}

/// Creates a scalar CTensorHandle value for the given data type.
///
/// - Parameters:
///   - value: The scalar value.
///   - dtype: The TF data type of the tensor handle to create.
/// - Returns: A new CTensorHandle representing the scalar.
/// - Precondition: T must conform to _TensorFlowDataTypeCompatible and 'dtype'
///   must be equal to T's corresponding data type.
/// - TODO(rxwei): Constrain T to _TensorFlowDataTypeCompatible and remove the
///   precondition. This requires the compiler to emit a call to the generic
///   function.
@inlinable
@_silgen_name("_swift_tfc_CreateCTensorHandle")
public func _TFCCreateCTensorHandle<T>(_ value: T,
                                       _ dtype: TF_DataType) -> CTensorHandle {
  // Create a new CTensor and initialize it to the scalar value.
  let tensor = TF_AllocateTensor(dtype, nil, 0, MemoryLayout<T>.stride)
  TF_TensorData(tensor).assumingMemoryBound(to: T.self).initialize(to: value)
  // Create a new CTensorHandle from the CTensor.
  let status = TF_NewStatus()
  let cTensorHandle = TFE_NewTensorHandle(tensor, status)
  checkOk(status)
  TF_DeleteStatus(status)
  TF_DeleteTensor(tensor)
  return cTensorHandle!
}

//===----------------------------------------------------------------------===//
// - MARK: Dynamic compilation (per-op dispatch) entrypoints
//===----------------------------------------------------------------------===//

@usableFromInline
@_cdecl("_swift_tfc_GetGlobalEagerContext")
func _TFCGetGlobalEagerContext() -> CTFEContext {
  debugLog("Calling _GetGlobalEagerContext()")
  return _ExecutionContext.global.eagerContext
}

// Some of the functions are marked with @silgen_name instead of @_cdecl,
// because their input/output data types are not C-compatible
// (e.g. AnyTensorHandle).

/// Adds `handle` as an input to `op`.
@usableFromInline
@_silgen_name("_swift_tfc_OpAddInputFromTensorHandle")
func _TFCOpAddInputFromTensorHandle(_ op: CTFEOp,
                                    _ handle: _AnyTensorHandle,
                                    _ status: CTFStatus) {
  TFE_OpAddInput(op, handle._cTensorHandle, status)
}

/// Adds `t` as an input or inputs to `op`. Returns the number of inputs added.
@usableFromInline
@_silgen_name("_swift_tfc_OpAddInputFromTensorGroup")
func _TFCOpAddInputFromTensorGroup<T : TensorArrayProtocol>(
    _ op: CTFEOp, _ t: T, _ status: CTFStatus
) -> Int32 {
  let count = t._tensorHandleCount
  let buffer =
      UnsafeMutableBufferPointer<CTensorHandle>.allocate(capacity: Int(count))
  defer { buffer.deallocate() }
  t._unpackTensorHandles(into: buffer.baseAddress)
  for handle in buffer {
    TFE_OpAddInput(op, handle, status)
    guard TF_GetCode(status) == TF_OK else {
      return 0
    }
  }
  return count
}

/// Initializes a TensorGroup value, taking ownership of all the tensor
/// handles in `tensorHandles`.
@usableFromInline
@_silgen_name("_swift_tfc_InitTensorGroup")
func _TFCInitTensorGroup<T : TensorGroup>(
    _ tensorHandles: UnsafeMutablePointer<CTensorHandle>
) -> T {
  return T(_owning: tensorHandles)
}

/// Allocates a buffer of CTensorHandles on the heap.
@usableFromInline
@_silgen_name("_swift_tfc_AllocateCHandleBuffer")
func _TFCAllocateCHandleBuffer(_ capacity: Int32)
    -> UnsafeMutablePointer<CTensorHandle> {
  return UnsafeMutablePointer.allocate(capacity: Int(capacity))
}

/// Deallocates a buffer of CTensorHandles.
@usableFromInline
@_silgen_name("_swift_tfc_DeallocateCHandleBuffer")
func _TFCDeallocateCHandleBuffer(
    _ buffer: UnsafeMutablePointer<CTensorHandle>
) {
  buffer.deallocate()
}

/// Returns the number of CTensorHandles in a TensorGroup of type T.
@_silgen_name("_swift_tfc_GetTensorGroupCHandleCount")
public func _TFCGetTensorGroupCHandleCount<T : TensorGroup>(
    _ type: T.Type
) -> Int32 {
  return T._tensorHandleCount
}

@inlinable
@_silgen_name("_swift_tfc_CreateTensorHandleFromC")
public func _TFCCreateTensorHandleFromC(
  _ cHandle: CTensorHandle
) -> _AnyTensorHandle {
  let dtype = TFE_TensorHandleDataType(cHandle)
  switch dtype {
  case TF_BFLOAT16: return TensorHandle<BFloat16>(_owning: cHandle)
  case TF_UINT8: return TensorHandle<UInt8>(_owning: cHandle)
  case TF_INT8: return TensorHandle<Int8>(_owning: cHandle)
  case TF_UINT16: return TensorHandle<UInt16>(_owning: cHandle)
  case TF_INT16: return TensorHandle<Int16>(_owning: cHandle)
  case TF_UINT32: return TensorHandle<UInt32>(_owning: cHandle)
  case TF_INT32: return TensorHandle<Int32>(_owning: cHandle)
  case TF_UINT64: return TensorHandle<UInt64>(_owning: cHandle)
  case TF_INT64: return TensorHandle<Int64>(_owning: cHandle)
  case TF_FLOAT: return TensorHandle<Float>(_owning: cHandle)
  case TF_DOUBLE: return TensorHandle<Double>(_owning: cHandle)
  case TF_BOOL: return TensorHandle<Bool>(_owning: cHandle)
  case TF_STRING: return TensorHandle<String>(_owning: cHandle)
  case TF_RESOURCE: return ResourceHandle(owning: cHandle)
  case TF_VARIANT: return VariantHandle(owning: cHandle)
  default: fatalError("Unsupported dtype \(dtype)")
  }
}

// _TFCOpSetAttr*Array functions are wrappers around TFE_OpSetAttr*List
// functions. The wrappers handle converting the Swift Stdlib Array<T> values
// into buffers that TFE_OpSetAttr*List functions can read.

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrBoolArray")
func _TFCOpSetAttrBoolArray(_ op: CTFEOp,
                            _ attrName: UnsafePointer<Int8>,
                            _ value: Array<Bool>) {
  value.map({ $0 ? UInt8(1) : UInt8(0) }).withUnsafeBufferPointer { buffer in
    TFE_OpSetAttrBoolList(op, attrName, buffer.baseAddress, Int32(buffer.count))
  }
}

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrInt32Array")
func _TFCOpSetAttrInt32Array(_ op: CTFEOp,
                             _ attrName: UnsafePointer<Int8>,
                             _ value: Array<Int32>) {
  value.map(Int64.init).withUnsafeBufferPointer { buffer in
    TFE_OpSetAttrIntList(op, attrName, buffer.baseAddress, Int32(buffer.count))
  }
}

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrInt64Array")
func _TFCOpSetAttrInt64Array(_ op: CTFEOp,
                             _ attrName: UnsafePointer<Int8>,
                             _ value: Array<Int64>) {
  value.withUnsafeBufferPointer { buffer in
    TFE_OpSetAttrIntList(op, attrName, buffer.baseAddress, Int32(buffer.count))
  }
}

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrDoubleArray")
func _TFCOpSetAttrDoubleArray(_ op: CTFEOp,
                              _ attrName: UnsafePointer<Int8>,
                              _ value: Array<Double>) {
  value.map(Float.init).withUnsafeBufferPointer { buffer in
    TFE_OpSetAttrFloatList(op, attrName, buffer.baseAddress, Int32(buffer.count))
  }
}

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrFloatArray")
func _TFCOpSetAttrFloatArray(_ op: CTFEOp,
                             _ attrName: UnsafePointer<Int8>,
                             _ value: Array<Float>) {
  value.withUnsafeBufferPointer { buffer in
    TFE_OpSetAttrFloatList(op, attrName, buffer.baseAddress, Int32(buffer.count))
  }
}

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrTypeArray")
func _TFCOpSetAttrTypeArray(_ op: CTFEOp,
                            _ attrName: UnsafePointer<Int8>,
                            _ value: Array<TensorDataType>) {
  value.withUnsafeBufferPointer { buffer in
    buffer.withMemoryRebound(to: TF_DataType.self) { reboundBuffer in
      TFE_OpSetAttrTypeList(op, attrName, reboundBuffer.baseAddress,
                            Int32(reboundBuffer.count))
    }
  }
}

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrTensorShape")
func _TFCOpSetAttrTensorShape(_ op: CTFEOp,
                              _ attrName: UnsafePointer<Int8>,
                              _ shape: TensorShape,
                              _ status: CTFStatus) {
  let dimensions: [Int64] = shape.dimensions.map(Int64.init)
  dimensions.withUnsafeBufferPointer { buffer in
    TFE_OpSetAttrShape(op, attrName, buffer.baseAddress, Int32(buffer.count),
                       status)
  }
}

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrOptionalTensorShape")
func _TFCOpSetAttrOptionalTensorShape(_ op: CTFEOp,
                                      _ attrName: UnsafePointer<Int8>,
                                      _ optionalShape: TensorShape?,
                                      _ status: CTFStatus) {
  guard let shape = optionalShape else {
    TFE_OpSetAttrShape(op, attrName, nil, -1, status)
    return
  }
  _TFCOpSetAttrTensorShape(op, attrName, shape, status)
}

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrTensorShapeArray")
func _TFCOpSetAttrTensorShapeArray(_ op: CTFEOp,
                                   _ attrName: UnsafePointer<Int8>,
                                   _ value: Array<TensorShape>,
                                   _ status: CTFStatus) {
  let flattenedDims = value.flatMap { $0.dimensions.map(Int64.init) }
  let ranks = value.map { $0.rank }
  setAttrShapeList(op: op, attrName: attrName, flattenedDims: flattenedDims,
                   ranks: ranks, status: status)
}

@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrOptionalTensorShapeArray")
func _TFCOpSetAttrOptionalTensorShapeArray(_ op: CTFEOp,
                                           _ attrName: UnsafePointer<Int8>,
                                           _ value: Array<TensorShape?>,
                                           _ status: CTFStatus) {
  let flattenedDims = value.flatMap { (tensorShapeOpt) -> [Int64] in
    if let tensorShape = tensorShapeOpt {
      return tensorShape.dimensions.map(Int64.init)
    }
    return []
  }
  let ranks = value.map { tensorShapeOpt -> Int32 in
    if let tensorShape = tensorShapeOpt {
      return tensorShape.rank
    }
    return -1
  }
  setAttrShapeList(op: op, attrName: attrName, flattenedDims: flattenedDims,
                   ranks: ranks, status: status)
}

/// Given dimensions and ranks in the form described below, makes the
/// appropriate call to TFE_OpSetAttrShapeList(op, attrName, ..., status).
///
/// - Parameters
///   - flattenedDims: all the shapes' dimensions concatenated together in
///     order
///   - ranks: all the shapes' ranks (-1 denotes unknown rank)
func setAttrShapeList(op: CTFEOp, attrName: UnsafePointer<Int8>,
                      flattenedDims: Array<Int64>, ranks: Array<Int32>,
                      status: CTFStatus) {
  flattenedDims.withUnsafeBufferPointer { flattenedDimsBuffer in
    var dimsPtr: UnsafePointer<Int64>? = flattenedDimsBuffer.baseAddress
    var dims: [UnsafePointer<Int64>?] = []
    for rank in ranks {
      dims.append(dimsPtr)
      if rank >= 0 {
        dimsPtr = dimsPtr.map { $0.advanced(by: Int(rank)) }
      }
    }
    dims.withUnsafeMutableBufferPointer { dimsBuffer in
      ranks.withUnsafeBufferPointer { ranksBuffer in
        TFE_OpSetAttrShapeList(op, attrName, dimsBuffer.baseAddress,
                               ranksBuffer.baseAddress,
                               Int32(ranksBuffer.count), status)
      }
    }
  }
}

/// Wrapper around TFE_OpSetAttrString that handles converting the Swift Stdlib
/// String into a buffer that TFE_OpSetAttrString can read.
@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrString")
func _TFCOpSetAttrString(_ op: CTFEOp,
                         _ attrName: UnsafePointer<Int8>,
                         _ value: String) {
  value.utf8CString.withUnsafeBufferPointer { buffer in
    // utf8CString is null-terminated; TFE_OpSetAttrString wants
    // non-null-terminated.
    TFE_OpSetAttrString(op, attrName, buffer.baseAddress, buffer.count - 1)
  }
}

/// Wrapper around TFE_OpSetAttrFunctionName that handles converting the Swift
/// Stdlib String into a buffer that TFE_OpSetAttrFunctionName can read.
@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrFunctionName")
func _TFCOpSetAttrFunctionName(_ op: CTFEOp,
                               _ attrName: UnsafePointer<Int8>,
                               _ value: String) {
  value.utf8CString.withUnsafeBufferPointer { buffer in
    // utf8CString is null-terminated; TFE_OpSetAttrFunctionName wants
    // non-null-terminated.
    TFE_OpSetAttrFunctionName(op, attrName, buffer.baseAddress, buffer.count - 1)
  }
}

/// Wrapper around TFE_OpSetAttrStringList that handles converting the Swift
/// Strings into buffers that TFE_OpSetAttrStringList can read.
@usableFromInline
@_silgen_name("_swift_tfc_OpSetAttrStringArray")
func _TFCOpSetAttrStringArray(_ op: CTFEOp,
                             _ attrName: UnsafePointer<Int8>,
                             _ strings: [String]) {
  // Collect all the strings' utf8 bytes into a single array so that we can
  // address all the strings with a single
  // `flattenedStringBytes.withUnsafeBufferPointer`.
  var flattenedStringBytes: [CChar] = []
  var lengths: [Int] = []
  for string in strings {
    // Don't include the null-terminator because TFE_OpSetAttrStringList uses
    // lengths instead of null-terminators.
    let stringBytes = string.utf8CString.dropLast()
    flattenedStringBytes.append(contentsOf: stringBytes)
    lengths.append(stringBytes.count)
  }

  // Calculate the addresses of all the strings within our single buffer, and
  // then call TFE_OpSetAttrStringList.
  flattenedStringBytes.withUnsafeBufferPointer { flattenedStringBytesBuffer in
    var stringAddrs: [UnsafeRawPointer?] = []
    var currentStringAddr =
        flattenedStringBytesBuffer.baseAddress.map(UnsafeRawPointer.init)
    for length in lengths {
      stringAddrs.append(currentStringAddr)
      currentStringAddr = currentStringAddr?.advanced(by: length)
    }

    stringAddrs.withUnsafeBufferPointer { stringAddrsBuffer in
      lengths.withUnsafeBufferPointer { lengthsBuffer in
        TFE_OpSetAttrStringList(op, attrName, stringAddrsBuffer.baseAddress,
                                lengthsBuffer.baseAddress, Int32(strings.count))
      }
    }
  }
}

@usableFromInline
class _ThreadLocalState {
  var deviceScopes: [(kind: DeviceKind, index: UInt)?] = []

  private static let key: pthread_key_t = {
    var key = pthread_key_t()
    pthread_key_create(&key) {
#if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
      let _: AnyObject = Unmanaged.fromOpaque($0).takeRetainedValue()
#else
      let _: AnyObject = Unmanaged.fromOpaque($0!).takeRetainedValue()
#endif
    }
    return key
  }()

  var _currentDevice: (DeviceKind, UInt)? {
    return deviceScopes.last ?? nil
  }

  @usableFromInline
  func pushDevice(_ device: (DeviceKind, UInt)?) {
    deviceScopes.append(device)
  }

  @usableFromInline
  func popDevice() {
    internalConsistencyCheck(deviceScopes.popLast() != nil)
  }

  @usableFromInline
  static var value: _ThreadLocalState {
    if let state = pthread_getspecific(key) {
      return Unmanaged.fromOpaque(state).takeUnretainedValue()
    }
    let state = _ThreadLocalState()
    pthread_setspecific(key, Unmanaged.passRetained(state).toOpaque())
    return state
  }
}

@usableFromInline
@_cdecl("_swift_tfc_OpSetDeviceFromScope")
func _TFCOpSetDeviceFromScope(_ op: CTFEOp, _ status: CTFStatus) {
  if let deviceName = _ExecutionContext.global.currentDeviceName {
    TFE_OpSetDevice(op, deviceName, status)
  }
}

@usableFromInline
@_cdecl("_swift_tfc_CheckOk")
func _TFCCheckOk(_ s: CTFStatus) {
  checkOk(s)
}
