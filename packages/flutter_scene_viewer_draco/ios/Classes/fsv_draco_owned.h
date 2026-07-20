#ifndef FSV_DRACO_OWNED_H_
#define FSV_DRACO_OWNED_H_

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <map>
#include <memory>
#include <new>
#include <set>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

#include "fsv_draco_control.h"

template <typename T>
class FsvDracoAllocator {
 public:
  using value_type = T;
  using propagate_on_container_move_assignment = std::true_type;
  using propagate_on_container_swap = std::true_type;
  using is_always_equal = std::false_type;

  FsvDracoAllocator() noexcept = default;
  explicit FsvDracoAllocator(
      fsv_draco::FsvDecodeControl* control) noexcept
      : control_(control) {
    Acquire();
  }

  FsvDracoAllocator(const FsvDracoAllocator& other) noexcept
      : control_(other.control_) {
    Acquire();
  }

  template <typename U>
  FsvDracoAllocator(const FsvDracoAllocator<U>& other) noexcept
      : control_(other.control()) {
    Acquire();
  }

  FsvDracoAllocator(FsvDracoAllocator&& other) noexcept
      : control_(other.control_) {
    Acquire();
  }

  ~FsvDracoAllocator() { Release(); }

  FsvDracoAllocator& operator=(const FsvDracoAllocator& other) noexcept {
    if (control_ != other.control_) {
      Release();
      control_ = other.control_;
      Acquire();
    }
    return *this;
  }

  FsvDracoAllocator& operator=(FsvDracoAllocator&& other) noexcept {
    return *this = other;
  }

  T* allocate(size_t count) {
    if (control_ == nullptr) {
      return std::allocator<T>{}.allocate(count);
    }
    const size_t value_count = count == 0 ? 1 : count;
    if (value_count > std::numeric_limits<size_t>::max() / sizeof(T)) {
      throw std::bad_array_new_length();
    }
    const size_t payload_bytes = value_count * sizeof(T);
    const size_t alignment =
        alignof(T) < alignof(AllocationHeader) ? alignof(AllocationHeader)
                                               : alignof(T);
    const size_t prefix = sizeof(AllocationHeader) + alignment - 1;
    if (payload_bytes > std::numeric_limits<size_t>::max() - prefix) {
      throw std::bad_array_new_length();
    }
    const size_t allocation_bytes = prefix + payload_bytes;
    const fsv_draco::FsvDecodeAllocationResult record =
        control_->AllocateMemory(allocation_bytes, alignment);
    switch (record.outcome) {
      case fsv_draco::FsvDecodeAllocationOutcome::kSuccess:
        break;
      case fsv_draco::FsvDecodeAllocationOutcome::kStopped:
        throw fsv_draco::FsvDecodeStopped();
      case fsv_draco::FsvDecodeAllocationOutcome::kBudgetExceeded:
        throw fsv_draco::FsvDecodeBudgetExceeded();
      case fsv_draco::FsvDecodeAllocationOutcome::kHeapFailure:
        throw std::bad_alloc();
    }
    const uintptr_t value_address =
        (reinterpret_cast<uintptr_t>(record.allocation) +
         sizeof(AllocationHeader) + alignment - 1) &
        ~(static_cast<uintptr_t>(alignment) - 1);
    auto* const header = reinterpret_cast<AllocationHeader*>(
        value_address - sizeof(AllocationHeader));
    ::new (header) AllocationHeader{kMagic, control_, record};
    return reinterpret_cast<T*>(value_address);
  }

  void deallocate(T* values, size_t count) noexcept {
    if (values == nullptr) {
      return;
    }
    if (control_ == nullptr) {
      std::allocator<T>{}.deallocate(values, count);
      return;
    }
    auto* const header = reinterpret_cast<AllocationHeader*>(
        reinterpret_cast<uintptr_t>(values) - sizeof(AllocationHeader));
    if (header->magic != kMagic || header->control != control_) {
      std::terminate();
    }
    const size_t value_count = count == 0 ? 1 : count;
    const size_t payload_bytes = value_count * sizeof(T);
    const size_t alignment =
        alignof(T) < alignof(AllocationHeader) ? alignof(AllocationHeader)
                                               : alignof(T);
    const size_t allocation_bytes =
        sizeof(AllocationHeader) + alignment - 1 + payload_bytes;
    fsv_draco::FsvDecodeAllocationResult* const record = &header->record;
    header->magic = 0;
    if (!control_->ReleaseMemory(record, record->allocation, allocation_bytes,
                                 alignment)) {
      std::terminate();
    }
  }

  fsv_draco::FsvDecodeControl* control() const noexcept { return control_; }

  template <typename U>
  bool operator==(const FsvDracoAllocator<U>& other) const noexcept {
    return control_ == other.control();
  }

  template <typename U>
  bool operator!=(const FsvDracoAllocator<U>& other) const noexcept {
    return !(*this == other);
  }

 private:
  template <typename>
  friend class FsvDracoAllocator;

  struct AllocationHeader {
    uint64_t magic;
    fsv_draco::FsvDecodeControl* control;
    fsv_draco::FsvDecodeAllocationResult record;
  };

  static constexpr uint64_t kMagic = UINT64_C(0x4653564252494447);

  void Acquire() noexcept {
    if (control_ != nullptr) {
      control_->AcquireOwner();
    }
  }

  void Release() noexcept {
    if (control_ != nullptr) {
      control_->ReleaseOwner();
    }
  }

  fsv_draco::FsvDecodeControl* control_ = nullptr;
};

using FsvDracoString =
    std::basic_string<char, std::char_traits<char>, FsvDracoAllocator<char>>;

template <typename T>
using FsvDracoVector = std::vector<T, FsvDracoAllocator<T>>;

using FsvDracoByteVector = FsvDracoVector<uint8_t>;

template <typename T, typename LeftAllocator, typename RightAllocator>
bool operator==(const std::vector<T, LeftAllocator>& left,
                const std::vector<T, RightAllocator>& right) {
  return left.size() == right.size() &&
         std::equal(left.begin(), left.end(), right.begin());
}

template <typename T, typename LeftAllocator, typename RightAllocator>
bool operator!=(const std::vector<T, LeftAllocator>& left,
                const std::vector<T, RightAllocator>& right) {
  return !(left == right);
}

template <typename Key, typename Value>
using FsvDracoMap =
    std::map<Key, Value, std::less<>,
             FsvDracoAllocator<std::pair<const Key, Value>>>;

template <typename Value>
using FsvDracoSet =
    std::set<Value, std::less<>, FsvDracoAllocator<Value>>;

#endif  // FSV_DRACO_OWNED_H_
