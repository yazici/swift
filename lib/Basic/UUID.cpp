//===--- UUID.cpp - UUID generation ---------------------------------------===//
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
// This is an interface over the standard OSF uuid library that gives UUIDs
// sane value semantics and operators.
//
//===----------------------------------------------------------------------===//

#include "swift/Basic/UUID.h"

// WIN32 doesn't natively support <uuid/uuid.h>. Instead, we use Win32 APIs.
#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <objbase.h>
#include <string>
#elif defined(__APPLE__)
#include <uuid/uuid.h>
#else
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>

struct UUIDb {
  uint32_t h;
  uint16_t m;
  uint16_t l;
  uint8_t c[2];
  uint8_t s[6];
};

bool uuid_parse(const char *s, UUIDb* ref){
  UUIDb temp;
  const char strScanFormat[] = "%08" SCNx32 "-%04" SCNx16 "-%04" SCNx16 "-%02"
      SCNx8 "%02" SCNx8 "-%02" SCNx8 "%02" SCNx8 "%02" SCNx8 "%02" SCNx8 "%02"
      SCNx8 "%02" SCNx8;

  if (sscanf(s, strScanFormat,
        &temp.h, &temp.m, &temp.l,
        &temp.c[0], &temp.c[1],
        &temp.s[0], &temp.s[1], &temp.s[2], &temp.s[3], &temp.s[4], &temp.s[5])
    != 11)
    return false;

  memcpy(ref, &temp, sizeof(UUIDb));
  return true;
}

bool uuid_random(unsigned char *buf) {
  int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
  if (!fd)
    return false;

  size_t offset = 0;
  size_t readlen = swift::UUID::Size;
  do {
    int partial = read(fd, buf + offset, readlen);
    if (partial > 0) {
      offset += partial;
      readlen -= partial;
    }
  } while (readlen > 0);
  close(fd);

  // Twiddle the high value to add the version
  uint16_t p3 = buf[6];
  p3 = (p3 << 8) | buf[7];
  p3 = (4 << 12) | (p3 & 0x0fff);
  buf[7] = p3;
  p3 >>= 8;
  buf[6] = p3;

  // Twiddle the clock to add the version
  buf[8] = 0x80 | (buf[8] & 0x3f);
  return true;
}

#endif

using namespace swift;

swift::UUID::UUID(FromRandom_t) {
#if defined(_WIN32)
  ::UUID uuid;
  ::CoCreateGuid(&uuid);

  memcpy(Value, &uuid, Size);
#elif defined(__APPLE__)
  uuid_generate_random(Value);
#else
  uuid_random(Value);
#endif
}

swift::UUID::UUID(FromTime_t) {
#if defined(_WIN32)
  ::UUID uuid;
  ::CoCreateGuid(&uuid);

  memcpy(Value, &uuid, Size);
#elif defined(__APPLE__)
  uuid_generate_time(Value);
#else
  uuid_random(Value);
#endif
}

swift::UUID::UUID() {
#if defined(_WIN32)
  ::UUID uuid = *((::UUID *)&Value);
  UuidCreateNil(&uuid);

  memcpy(Value, &uuid, Size);
#elif defined(__APPLE__)
  uuid_clear(Value);
#else
  uuid_random(Value);
#endif
}

Optional<swift::UUID> swift::UUID::fromString(const char *s) {
#if defined(_WIN32)
  RPC_CSTR t = const_cast<RPC_CSTR>(reinterpret_cast<const unsigned char*>(s));

  ::UUID uuid;
  RPC_STATUS status = UuidFromStringA(t, &uuid);
  if (status == RPC_S_INVALID_STRING_UUID) {
    return None;
  }

  swift::UUID result = UUID();
  memcpy(result.Value, &uuid, Size);
  return result;
#elif defined(__APPLE__)
  swift::UUID result;
  if (uuid_parse(s, result.Value))
    return None;
  return result;
#else
  swift::UUID result;
  if (strlen(s) != 36)
    return None;

  UUIDb temp;
  if (!uuid_parse(s, &temp))
    return None;

  memcpy(result.Value, &temp, Size);
  return result;
#endif
}

void swift::UUID::toString(llvm::SmallVectorImpl<char> &out) const {
  out.resize(UUID::StringBufferSize);
#if defined(_WIN32)
  ::UUID uuid;
  memcpy(&uuid, Value, Size);

  RPC_CSTR str;
  UuidToStringA(&uuid, &str);

  char* signedStr = reinterpret_cast<char*>(str);
  memcpy(out.data(), signedStr, StringBufferSize);
#elif defined(__APPLE__)
  uuid_unparse_upper(Value, out.data());
#else
  // Low
  uint32_t p1 = Value[0];
  p1 = (p1 << 8) | Value[1];
  p1 = (p1 << 8) | Value[2];
  p1 = (p1 << 8) | Value[3];

  // Mid
  uint16_t p2 = Value[4];
  p2 = (p2 << 8) | Value[5];

  // High/version
  uint16_t p3 = Value[6];
  p3 = (p3 << 8) | Value[7];

  // Clock
  uint16_t p4 = Value[8];
  p4 = (p4 << 8) | Value[9];

  sprintf(out.data(), "%08X-%04X-%04X-%02X%02X-%02X%02X%02X%02X%02X%02X",
    p1, p2, p3, Value[8], Value[9], Value[10], Value[11], Value[12],
    Value[13], Value[14], Value[15]);
#endif
  // Pop off the null terminator.
  assert(out.back() == '\0' && "did not null-terminate?!");
  out.pop_back();
}

int swift::UUID::compare(UUID y) const {
#if defined(_WIN32)
  RPC_STATUS s;
  ::UUID uuid1;
  memcpy(&uuid1, Value, Size);

  ::UUID uuid2;
  memcpy(&uuid2, y.Value, Size);

  return UuidCompare(&uuid1, &uuid2, &s);
#elif defined(__APPLE__)
  return uuid_compare(Value, y.Value);
#else

  // FIXME: binary comparsion instead of structured comparsion
  return memcmp(Value, y.Value, Size);
#endif
}

llvm::raw_ostream &swift::operator<<(llvm::raw_ostream &os, UUID uuid) {
  llvm::SmallString<UUID::StringBufferSize> buf;
  uuid.toString(buf);
  os << buf;
  return os;
}
