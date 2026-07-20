// Copyright 2026 flutter_scene_viewer authors.
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
#ifndef DRACO_CORE_FSV_DECODE_ALLOCATOR_H_
#define DRACO_CORE_FSV_DECODE_ALLOCATOR_H_

#include <cstddef>
#include <cstdint>
#include <exception>
#include <functional>
#include <limits>
#include <map>
#include <memory>
#include <new>
#include <string>
#include <type_traits>
#include <unordered_map>
#include <utility>
#include <vector>

namespace draco {

// FSV LOCAL MODIFICATION (Apache-2.0 section 4(b)): request-scoped decode
// cancellation and allocation interface. Implementations are owned by one
// decode request. The vendored codec never stores this pointer beyond decode.
class FsvDecodeControl {
 public:
  virtual ~FsvDecodeControl() = default;
  virtual bool ShouldStopDecoding() const = 0;
  enum class AllocationOutcome {
    kSuccess,
    kStopped,
    kBudgetExceeded,
    kHeapFailure,
  };
  struct AllocationResult {
    AllocationResult() = default;
    AllocationResult(void* value, AllocationOutcome value_outcome)
        : allocation(value), outcome(value_outcome) {}
    AllocationResult(void* value, size_t value_bytes, size_t value_alignment,
                     AllocationOutcome value_outcome)
        : allocation(value),
          bytes(value_bytes),
          alignment(value_alignment),
          outcome(value_outcome) {}
    void* allocation = nullptr;
    size_t bytes = 0;
    size_t alignment = 0;
    AllocationOutcome outcome = AllocationOutcome::kHeapFailure;
  };
  virtual AllocationResult AllocateMemory(size_t bytes,
                                          size_t alignment) noexcept = 0;
  virtual bool ReleaseMemory(AllocationResult* allocation_record,
                             void* allocation, size_t bytes,
                             size_t alignment) noexcept = 0;
};

// Thrown only when the request allocator rejected a reservation. A null
// allocation with no rejected reservation remains std::bad_alloc so the bridge
// can distinguish budget exhaustion from a codec/host allocation failure.
class FsvDecodeBudgetExceeded final : public std::bad_alloc {
 public:
  const char* what() const noexcept override {
    return "Draco request working-memory budget exceeded";
  }
};

// Thrown only when allocation was rejected because caller cancellation or a
// deadline already won the request's first-wins stop race.
class FsvDecodeStopped final : public std::exception {
 public:
  const char* what() const noexcept override {
    return "Draco decode stopped before allocation";
  }
};

// Base for request-owned polymorphic objects that must retain ordinary
// std::unique_ptr<T> ownership. The allocation header preserves the request
// allocation pointer and exact reservation until virtual deletion.
class FsvDecodeAllocated {
 public:
  static void* operator new(size_t bytes) {
    return AllocateObject(bytes, alignof(std::max_align_t), nullptr);
  }
  static void* operator new(size_t bytes, FsvDecodeControl* control) {
    return AllocateObject(bytes, alignof(std::max_align_t), control);
  }
#if defined(__cpp_aligned_new)
  static void* operator new(size_t bytes, std::align_val_t alignment) {
    return AllocateObject(bytes, static_cast<size_t>(alignment), nullptr);
  }
  static void* operator new(size_t bytes, std::align_val_t alignment,
                            FsvDecodeControl* control) {
    return AllocateObject(bytes, static_cast<size_t>(alignment), control);
  }
#endif

  static void operator delete(void* object) noexcept { ReleaseObject(object); }
  static void operator delete(void* object, size_t) noexcept {
    ReleaseObject(object);
  }
  static void operator delete(void* object, FsvDecodeControl*) noexcept {
    ReleaseObject(object);
  }
#if defined(__cpp_aligned_new)
  static void operator delete(void* object, std::align_val_t) noexcept {
    ReleaseObject(object);
  }
  static void operator delete(void* object, size_t,
                              std::align_val_t) noexcept {
    ReleaseObject(object);
  }
  static void operator delete(void* object, std::align_val_t,
                              FsvDecodeControl*) noexcept {
    ReleaseObject(object);
  }
#endif

 protected:
  FsvDecodeAllocated() = default;
  ~FsvDecodeAllocated() = default;

 private:
  struct AllocationHeader {
    uint64_t magic;
    FsvDecodeControl* control;
    void* allocation;
    size_t bytes;
    size_t alignment;
  };

  static constexpr uint64_t kAllocationMagic = UINT64_C(0x4653564f424a4543);

  static void* AllocateObject(size_t object_bytes, size_t object_alignment,
                              FsvDecodeControl* control) {
    const size_t alignment =
        object_alignment < alignof(AllocationHeader)
            ? alignof(AllocationHeader)
            : object_alignment;
    const size_t prefix = sizeof(AllocationHeader) + alignment - 1;
    if (object_bytes > std::numeric_limits<size_t>::max() - prefix) {
      throw std::bad_array_new_length();
    }
    const size_t allocation_bytes = prefix + object_bytes;
    void* allocation = nullptr;
    if (control == nullptr) {
#if defined(__cpp_aligned_new)
      if (alignment > __STDCPP_DEFAULT_NEW_ALIGNMENT__) {
        allocation = ::operator new(allocation_bytes,
                                    std::align_val_t(alignment));
      } else {
#endif
        allocation = ::operator new(allocation_bytes);
#if defined(__cpp_aligned_new)
      }
#endif
    } else {
      const FsvDecodeControl::AllocationResult result =
          control->AllocateMemory(allocation_bytes, alignment);
      switch (result.outcome) {
        case FsvDecodeControl::AllocationOutcome::kSuccess:
          allocation = result.allocation;
          break;
        case FsvDecodeControl::AllocationOutcome::kBudgetExceeded:
          throw FsvDecodeBudgetExceeded();
        case FsvDecodeControl::AllocationOutcome::kStopped:
          throw FsvDecodeStopped();
        case FsvDecodeControl::AllocationOutcome::kHeapFailure:
          throw std::bad_alloc();
      }
      if (allocation == nullptr) {
        throw std::bad_alloc();
      }
    }
    const uintptr_t object_address =
        (reinterpret_cast<uintptr_t>(allocation) + sizeof(AllocationHeader) +
         alignment - 1) &
        ~(static_cast<uintptr_t>(alignment) - 1);
    auto* const header = reinterpret_cast<AllocationHeader*>(
        object_address - sizeof(AllocationHeader));
    ::new (header) AllocationHeader{kAllocationMagic, control, allocation,
                                    allocation_bytes, alignment};
    return reinterpret_cast<void*>(object_address);
  }

  static void ReleaseObject(void* object) noexcept {
    if (object == nullptr) {
      return;
    }
    auto* const header = reinterpret_cast<AllocationHeader*>(
        reinterpret_cast<uintptr_t>(object) - sizeof(AllocationHeader));
    if (header->magic != kAllocationMagic) {
      std::terminate();
    }
    FsvDecodeControl* const control = header->control;
    void* const allocation = header->allocation;
    const size_t bytes = header->bytes;
    const size_t alignment = header->alignment;
    header->magic = 0;
    if (control != nullptr) {
      FsvDecodeControl::AllocationResult record{
          allocation, bytes, alignment,
          FsvDecodeControl::AllocationOutcome::kSuccess};
      if (!control->ReleaseMemory(&record, allocation, bytes, alignment)) {
        std::terminate();
      }
      return;
    }
#if defined(__cpp_aligned_new)
    if (alignment > __STDCPP_DEFAULT_NEW_ALIGNMENT__) {
      ::operator delete(allocation, std::align_val_t(alignment));
    } else {
#endif
      ::operator delete(allocation);
#if defined(__cpp_aligned_new)
    }
#endif
  }
};

template <typename T>
class FsvDecodeAllocator {
 public:
  using value_type = T;
  using propagate_on_container_move_assignment = std::true_type;
  using propagate_on_container_swap = std::true_type;
  using is_always_equal = std::false_type;

  FsvDecodeAllocator() noexcept = default;
  explicit FsvDecodeAllocator(FsvDecodeControl* control) noexcept
      : control_(control) {}

  template <typename U>
  FsvDecodeAllocator(const FsvDecodeAllocator<U>& other) noexcept
      : control_(other.control()) {}

  T* allocate(size_t count) {
    if (count > std::numeric_limits<size_t>::max() / sizeof(T)) {
      throw std::bad_array_new_length();
    }
    const size_t payload_bytes = count * sizeof(T);
    const size_t bytes = payload_bytes == 0 ? 1 : payload_bytes;
    if (control_ == nullptr) {
      return std::allocator<T>().allocate(count);
    }
    const FsvDecodeControl::AllocationResult result =
        control_->AllocateMemory(bytes, alignof(T));
    switch (result.outcome) {
      case FsvDecodeControl::AllocationOutcome::kSuccess:
        if (result.allocation == nullptr) {
          throw std::bad_alloc();
        }
        return static_cast<T*>(result.allocation);
      case FsvDecodeControl::AllocationOutcome::kBudgetExceeded:
        throw FsvDecodeBudgetExceeded();
      case FsvDecodeControl::AllocationOutcome::kStopped:
        throw FsvDecodeStopped();
      case FsvDecodeControl::AllocationOutcome::kHeapFailure:
        throw std::bad_alloc();
    }
    throw std::bad_alloc();
  }

  void deallocate(T* allocation, size_t count) noexcept {
    if (control_ == nullptr) {
      std::allocator<T>().deallocate(allocation, count);
      return;
    }
    const size_t payload_bytes = count * sizeof(T);
    const size_t bytes = payload_bytes == 0 ? 1 : payload_bytes;
    FsvDecodeControl::AllocationResult record{
        allocation, bytes, alignof(T),
        FsvDecodeControl::AllocationOutcome::kSuccess};
    if (!control_->ReleaseMemory(&record, allocation, bytes, alignof(T))) {
      std::terminate();
    }
  }

  FsvDecodeControl* control() const noexcept { return control_; }

  template <typename U>
  bool operator==(const FsvDecodeAllocator<U>& other) const noexcept {
    return control_ == other.control();
  }

  template <typename U>
  bool operator!=(const FsvDecodeAllocator<U>& other) const noexcept {
    return !(*this == other);
  }

 private:
  template <typename>
  friend class FsvDecodeAllocator;

  FsvDecodeControl* control_ = nullptr;
};

template <typename T>
using FsvVector = std::vector<T, FsvDecodeAllocator<T>>;

using FsvString =
    std::basic_string<char, std::char_traits<char>, FsvDecodeAllocator<char>>;

template <typename Key, typename Value, typename Compare = std::less<Key>>
using FsvMap =
    std::map<Key, Value, Compare,
             FsvDecodeAllocator<std::pair<const Key, Value>>>;

template <typename Key, typename Value, typename Hash = std::hash<Key>,
          typename KeyEqual = std::equal_to<Key>>
using FsvUnorderedMap =
    std::unordered_map<Key, Value, Hash, KeyEqual,
                       FsvDecodeAllocator<std::pair<const Key, Value>>>;

}  // namespace draco

#endif  // DRACO_CORE_FSV_DECODE_ALLOCATOR_H_
