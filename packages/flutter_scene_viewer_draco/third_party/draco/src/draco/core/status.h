// Copyright 2017 The Draco Authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
#ifndef DRACO_CORE_STATUS_H_
#define DRACO_CORE_STATUS_H_

#include <ostream>
#include <string>
#include <string_view>
#include <utility>

#include "draco/core/fsv_decode_allocator.h"

namespace draco {

// FSV LOCAL MODIFICATION (Apache-2.0 section 4(b)): controlled decode status
// text is request-owned and ordinary copies detach from source controls.
// Class encapsulating a return status of an operation with an optional error
// message. Intended to be used as a return type for functions instead of bool.
class Status {
 public:
  enum Code {
    OK = 0,
    DRACO_ERROR = -1,          // Used for general errors.
    IO_ERROR = -2,             // Error when handling input or output stream.
    INVALID_PARAMETER = -3,    // Invalid parameter passed to a function.
    UNSUPPORTED_VERSION = -4,  // Input not compatible with the current version.
    UNKNOWN_VERSION = -5,      // Input was created with an unknown version of
                               // the library.
    UNSUPPORTED_FEATURE = -6,  // Input contains feature that is not supported.
  };

  Status();
  Status(const Status &status);
  Status(const Status &status, FsvDecodeControl *control);
  Status(Status &&status);
  Status(Status &&status, FsvDecodeControl *control);
  explicit Status(Code code);
  Status(Code code, const std::string &error_msg);
  Status(Code code, const std::string &error_msg, FsvDecodeControl *control);
  Status(Code code, std::string_view error_msg, FsvDecodeControl *control);
  Status(Code code, const char *error_msg);
  Status(Code code, const char *error_msg, FsvDecodeControl *control);

  Code code() const { return code_; }
  const std::string &error_msg_string() const;
  const char *error_msg() const;
  std::string code_string() const;
  std::string code_and_error_string() const;

  bool operator==(Code code) const { return code == code_; }
  bool ok() const { return code_ == OK; }

  Status &operator=(const Status &status);
  Status &operator=(Status &&status);

 private:
  FsvDecodeControl *fsv_decode_control() const { return control_; }

  Code code_;
  FsvDecodeControl *control_ = nullptr;
  std::string error_msg_;
  FsvString controlled_error_msg_;
  mutable std::string public_error_cache_;

  friend Status MoveStatusPreservingControl(Status &&status);
};

Status MoveStatusPreservingControl(Status &&status);

inline std::ostream &operator<<(std::ostream &os, const Status &status) {
  os << status.error_msg_string();
  return os;
}

inline Status OkStatus(FsvDecodeControl *control = nullptr) {
  return Status(Status::OK, std::string_view(), control);
}
inline Status ErrorStatus(const std::string &msg,
                          FsvDecodeControl *control = nullptr) {
  return Status(Status::DRACO_ERROR, msg, control);
}
inline Status ErrorStatus(const char *msg,
                          FsvDecodeControl *control = nullptr) {
  return Status(Status::DRACO_ERROR, msg, control);
}

// Evaluates an expression that returns draco::Status. If the status is not OK,
// the macro returns the status object.
#define DRACO_RETURN_IF_ERROR(expression)                           \
  {                                                                 \
    draco::Status _local_status = (expression);                      \
    if (!_local_status.ok()) {                                      \
      return draco::MoveStatusPreservingControl(                    \
          std::move(_local_status));                                \
    }                                                               \
  }

}  // namespace draco

#endif  // DRACO_CORE_STATUS_H_
