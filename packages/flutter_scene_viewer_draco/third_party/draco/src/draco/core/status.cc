// Copyright 2022 The Draco Authors.
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
#include "draco/core/status.h"

#include <cstring>
#include <string>

namespace draco {

Status::Status()
    : code_(OK),
      controlled_error_msg_(FsvDecodeAllocator<char>(nullptr)) {}

Status::Status(Code code)
    : code_(code),
      controlled_error_msg_(FsvDecodeAllocator<char>(nullptr)) {}

Status::Status(const Status &status) : Status(status, nullptr) {}

Status::Status(const Status &status, FsvDecodeControl *control)
    : code_(status.code_),
      control_(control),
      controlled_error_msg_(FsvDecodeAllocator<char>(control)) {
  if (control == nullptr || !control->ShouldStopDecoding()) {
    const std::string_view message(status.error_msg(),
                                   std::strlen(status.error_msg()));
    if (control == nullptr) {
      error_msg_.assign(message.begin(), message.end());
    } else {
      controlled_error_msg_.assign(message.begin(), message.end());
    }
  }
}

Status::Status(Status &&status) : Status(status, nullptr) {}

Status::Status(Status &&status, FsvDecodeControl *control)
    : code_(status.code_),
      control_(control),
      controlled_error_msg_(FsvDecodeAllocator<char>(control)) {
  if (control != nullptr && control->ShouldStopDecoding()) {
    return;
  }
  if (control == nullptr) {
    if (status.control_ == nullptr) {
      error_msg_ = std::move(status.error_msg_);
    } else {
      error_msg_.assign(status.controlled_error_msg_.begin(),
                        status.controlled_error_msg_.end());
    }
  } else if (status.control_ == control) {
    controlled_error_msg_ = std::move(status.controlled_error_msg_);
  } else {
    const char *const message = status.error_msg();
    controlled_error_msg_.assign(message, message + std::strlen(message));
  }
}

Status::Status(Code code, const std::string &error_msg)
    : Status(code, std::string_view(error_msg), nullptr) {}

Status::Status(Code code, const std::string &error_msg,
               FsvDecodeControl *control)
    : Status(code, std::string_view(error_msg), control) {}

Status::Status(Code code, const char *error_msg)
    : Status(code, std::string_view(error_msg), nullptr) {}

Status::Status(Code code, const char *error_msg, FsvDecodeControl *control)
    : Status(code, std::string_view(error_msg), control) {}

Status::Status(Code code, std::string_view error_msg,
               FsvDecodeControl *control)
    : code_(code),
      control_(control),
      controlled_error_msg_(FsvDecodeAllocator<char>(control)) {
  // FSV LOCAL MODIFICATION (Apache-2.0 section 4(b)): once cancellation,
  // deadline, budget, or heap failure has stopped the request, do not attempt
  // to allocate a diagnostic from that terminal allocator.
  if (control == nullptr || !control->ShouldStopDecoding()) {
    if (control == nullptr) {
      error_msg_.assign(error_msg.begin(), error_msg.end());
    } else {
      controlled_error_msg_.assign(error_msg.begin(), error_msg.end());
    }
  }
}

Status MoveStatusPreservingControl(Status &&status) {
  return Status(std::move(status), status.fsv_decode_control());
}

const std::string &Status::error_msg_string() const {
  if (control_ == nullptr) {
    return error_msg_;
  }
  public_error_cache_.assign(controlled_error_msg_.begin(),
                             controlled_error_msg_.end());
  return public_error_cache_;
}

const char *Status::error_msg() const {
  return control_ == nullptr ? error_msg_.c_str()
                             : controlled_error_msg_.c_str();
}

Status &Status::operator=(const Status &status) {
  code_ = status.code_;
  if (control_ != nullptr && control_->ShouldStopDecoding()) {
    controlled_error_msg_.clear();
    return *this;
  }
  const char *const message = status.error_msg();
  if (control_ == nullptr) {
    error_msg_.assign(message, message + std::strlen(message));
  } else {
    controlled_error_msg_.assign(message, message + std::strlen(message));
  }
  return *this;
}

Status &Status::operator=(Status &&status) {
  return *this = static_cast<const Status &>(status);
}

std::string Status::code_string() const {
  switch (code_) {
    case Code::OK:
      return "OK";
    case Code::DRACO_ERROR:
      return "DRACO_ERROR";
    case Code::IO_ERROR:
      return "IO_ERROR";
    case Code::INVALID_PARAMETER:
      return "INVALID_PARAMETER";
    case Code::UNSUPPORTED_VERSION:
      return "UNSUPPORTED_VERSION";
    case Code::UNKNOWN_VERSION:
      return "UNKNOWN_VERSION";
    case Code::UNSUPPORTED_FEATURE:
      return "UNSUPPORTED_FEATURE";
  }
  return "UNKNOWN_STATUS_VALUE";
}

std::string Status::code_and_error_string() const {
  return code_string() + ": " + std::string(error_msg());
}

}  // namespace draco
