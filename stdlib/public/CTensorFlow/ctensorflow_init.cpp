#include "ctensorflow_init.h"

#include "tensorflow/c/c_api.h"
#include "tensorflow/c/c_api_experimental.h"
#include "tensorflow/c/eager/c_api.h"
#include "tensorflow/core/platform/init_main.h"

#include <assert.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <vector>

extern "C" {

void handle_sigint(int signal) {
  printf("Caught interrupt signal, exiting...\n");
  exit(1);
}

void InitTensorFlowRuntime(unsigned char enable_debug_logging,
                           int verbose_level) {
  // Install a signal handler to ensure we exit when interrupted.
  signal(SIGINT, handle_sigint);

  // Synthesize argc and argv
  char arg0[] = "dummyProgramName";
  std::vector<char*> my_argv;
  my_argv.push_back(&arg0[0]);
  // This allows us to dump TF logging to the output of a swift binary.
  // We can only dump to stderr, since there is no flag alsologtostdout.
  char arg1[] = "--alsologtostderr";
  if (enable_debug_logging > 0) {
    my_argv.push_back(&arg1[0]);
  }
  char arg2[] = "--v=?";
  if (verbose_level > 0) {
    assert(verbose_level <= 4);
    arg2[4] = verbose_level + '0';
    my_argv.push_back(&arg2[0]);
  }
  int my_argc = my_argv.size();
  char** tmpArgv = my_argv.data();
  // Initialize GPU devices.
  tensorflow::port::InitMain(/*usage=*/nullptr, &my_argc, &tmpArgv);
}

static bool setValue(TF_DataType tfDtype, int64_t val, void *ptr) {
  switch (tfDtype) {
  case TF_INT8:
    *reinterpret_cast<int8_t *>(ptr) = static_cast<int8_t>(val);
    return false;
  case TF_UINT8:
    *reinterpret_cast<uint8_t *>(ptr) = static_cast<uint8_t>(val);
    return false;
  case TF_INT16:
    *reinterpret_cast<int16_t *>(ptr) = static_cast<int16_t>(val);
    return false;
  case TF_UINT16:
    *reinterpret_cast<uint16_t *>(ptr) = static_cast<uint16_t>(val);
    return false;
  case TF_INT32:
    *reinterpret_cast<int32_t *>(ptr) = static_cast<int32_t>(val);
    return false;
  case TF_UINT32:
    *reinterpret_cast<uint32_t *>(ptr) = static_cast<uint32_t>(val);
    return false;
  case TF_INT64:
    *reinterpret_cast<int64_t *>(ptr) = static_cast<int64_t>(val);
    return false;
  case TF_UINT64:
    *reinterpret_cast<uint64_t *>(ptr) = static_cast<uint64_t>(val);
    return false;
  default:
    return true;
  }
}

void *swift_tfc_CreateIntTensor(int32_t num_dims, int64_t *dims, int64_t *vals,
                                int32_t dtype_int, TF_Status *status) {
  auto dtype = (TF_DataType)dtype_int;
  auto dtypeSize = TF_DataTypeSize(dtype);

  // Compute the total memory size of the tensor value.
  // totalElements can be 0 if shape is [] (i.e., num_dims = 1, dims[0] = 0).
  size_t totalElements = 1;
  for (int32_t i = 0; i < num_dims; ++i)
    totalElements *= dims[i];

  // Leave the code around for debugging. Can write it to TF LOG via an
  // experimental C API if needed.
  // printf("num_dims: %d, dtype: %d, total elts: %llu\n", num_dims, dtype_int,
  //       totalElements);

  // Make an uninitialized tensor that is big enough for our value.
  auto *tensor =
      TF_AllocateTensor(dtype, dims, num_dims, dtypeSize * totalElements);

  // Set up its contents, element-wise.
  // FIXME: This will need a byte swap for big endian hosts.
  auto *ptr = (char *)TF_TensorData(tensor);
  for (size_t i = 0; i < totalElements; ++i) {
    if (setValue(dtype, vals[i], ptr)) {
      TF_MakeInternalErrorStatus(status, "Unsupported data type");
      return nullptr;
    }
    ptr += dtypeSize;
  }
  return tensor;
}

void *swift_tfc_CreateFloatTensor(int32_t num_dims, int64_t *dims, float *vals,
                                  TF_Status *status) {
  // Compute the total memory size of the tensor value.
  size_t totalElements = 1;
  for (int32_t i = 0; i < num_dims; ++i)
    totalElements *= dims[i];

  // printf("num_dims: %d, total elts: %llu\n", num_dims, totalElements);

  auto dtypeSize = TF_DataTypeSize(TF_FLOAT);
  if (dtypeSize != sizeof(float)) {
    TF_MakeInternalErrorStatus(
        status, "The size of TF_FLOAT does not match that of a float");
    return nullptr;
  }

  // Make an uninitialized tensor that is big enough for our value.
  auto *tensor =
      TF_AllocateTensor(TF_FLOAT, dims, num_dims, dtypeSize * totalElements);

  // Set up its contents, element-wise.
  // FIXME: This will need a byte swap for big endian hosts.
  auto *ptr = (char *)TF_TensorData(tensor);
  for (size_t i = 0; i < totalElements; ++i) {
    *reinterpret_cast<float *>(ptr) = vals[i];
    ptr += dtypeSize;
  }
  return tensor;
}

/// A default deallocator function to pass in `TF_NewTensor`.
static void tensorDataDeallocator(void *data, size_t len, void *arg) {
  free(data);
};

// Also see convertValuesToTensor() in TFLowerGraph.cpp
void *swift_tfc_CreateScalarStringTensor(char *val, int32_t valLen,
                                         TF_Status *status) {
  // printf is kept for debugging purposes.
  // printf("string val: %s, with len %d \n", val, valLen);

  size_t offsetsSize = sizeof(uint64_t);
  size_t totalSize = offsetsSize + TF_StringEncodedSize(valLen);

  totalSize += offsetsSize;

  void *baseAddr = malloc(totalSize);
  auto *tensor =
      TF_NewTensor(TF_STRING, /*dims*/ nullptr, /*num_dims*/ 0, baseAddr,
                   totalSize, tensorDataDeallocator, nullptr);

  uint64_t *offsets = (uint64_t *)baseAddr;
  *offsets = 0;
  char *dataStart = (char *)baseAddr + offsetsSize;
  (void)TF_StringEncode(val, valLen, dataStart, totalSize, status);

  return tensor;
}

}  // extern "C"
