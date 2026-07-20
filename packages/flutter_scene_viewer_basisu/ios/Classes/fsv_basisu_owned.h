#ifndef FSV_BASISU_OWNED_H_
#define FSV_BASISU_OWNED_H_

#include <algorithm>
#include <cstddef>
#include <cstdint>
#include <limits>
#include <memory>
#include <new>
#include <string>
#include <type_traits>
#include <utility>
#include <vector>

#include "fsv_basisu_control.h"

template <typename T>
class FsvBasisuAllocator {
 public:
  using value_type = T;
  using propagate_on_container_move_assignment = std::true_type;
  using propagate_on_container_swap = std::true_type;
  using is_always_equal = std::false_type;

  FsvBasisuAllocator() noexcept = default;
  explicit FsvBasisuAllocator(
      fsv_basisu::FsvDecodeControl* control) noexcept
      : control_(control) {
    Acquire();
  }
  FsvBasisuAllocator(const FsvBasisuAllocator& other) noexcept
      : control_(other.control_) {
    Acquire();
  }
  template <typename U>
  FsvBasisuAllocator(const FsvBasisuAllocator<U>& other) noexcept
      : control_(other.control()) {
    Acquire();
  }
  FsvBasisuAllocator(FsvBasisuAllocator&& other) noexcept
      : control_(other.control_) {
    Acquire();
  }
  ~FsvBasisuAllocator() { Release(); }

  FsvBasisuAllocator& operator=(const FsvBasisuAllocator& other) noexcept {
    if (control_ != other.control_) {
      Release();
      control_ = other.control_;
      Acquire();
    }
    return *this;
  }
  FsvBasisuAllocator& operator=(FsvBasisuAllocator&& other) noexcept {
    return *this = other;
  }

  T* allocate(size_t count) {
    if (control_ == nullptr) return std::allocator<T>{}.allocate(count);
    const size_t value_count = count == 0 ? 1 : count;
    if (value_count > std::numeric_limits<size_t>::max() / sizeof(T)) {
      AllocationFailed();
    }
    const size_t payload_bytes = value_count * sizeof(T);
    const size_t alignment =
        alignof(T) < alignof(AllocationHeader) ? alignof(AllocationHeader)
                                               : alignof(T);
    const size_t prefix = sizeof(AllocationHeader) + alignment - 1;
    if (payload_bytes > std::numeric_limits<size_t>::max() - prefix) {
      AllocationFailed();
    }
    const size_t allocation_bytes = prefix + payload_bytes;
    basisu::fsv_allocation_result record =
        control_->fsv_allocate(allocation_bytes, alignment);
    if (record.m_outcome != basisu::fsv_allocation_outcome::kSuccess ||
        record.m_p == nullptr) {
      AllocationFailed();
    }
    const uintptr_t value_address =
        (reinterpret_cast<uintptr_t>(record.m_p) + sizeof(AllocationHeader) +
         alignment - 1) &
        ~(static_cast<uintptr_t>(alignment) - 1);
    auto* header = reinterpret_cast<AllocationHeader*>(
        value_address - sizeof(AllocationHeader));
    ::new (header) AllocationHeader(kMagic, control_, std::move(record));
    return reinterpret_cast<T*>(value_address);
  }

  void deallocate(T* values, size_t count) noexcept {
    if (values == nullptr) return;
    if (control_ == nullptr) {
      std::allocator<T>{}.deallocate(values, count);
      return;
    }
    auto* header = reinterpret_cast<AllocationHeader*>(
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
    basisu::fsv_allocation_result* record = &header->record;
    header->magic = 0;
    if (!control_->fsv_release(*record, record->m_p, allocation_bytes,
                               alignment)) {
      std::terminate();
    }
  }

  fsv_basisu::FsvDecodeControl* control() const noexcept { return control_; }

  template <typename U>
  bool operator==(const FsvBasisuAllocator<U>& other) const noexcept {
    return control_ == other.control();
  }
  template <typename U>
  bool operator!=(const FsvBasisuAllocator<U>& other) const noexcept {
    return !(*this == other);
  }

 private:
  template <typename>
  friend class FsvBasisuAllocator;

  struct AllocationHeader {
    AllocationHeader(uint64_t magic_value,
                     fsv_basisu::FsvDecodeControl* control_value,
                     basisu::fsv_allocation_result&& record_value) noexcept
        : magic(magic_value),
          control(control_value),
          record(std::move(record_value)) {}

    uint64_t magic;
    fsv_basisu::FsvDecodeControl* control;
    basisu::fsv_allocation_result record;
  };

  static constexpr uint64_t kMagic = UINT64_C(0x4653564241534953);

  [[noreturn]] static void AllocationFailed() {
#if defined(__cpp_exceptions) || defined(__EXCEPTIONS) || defined(_CPPUNWIND)
    throw std::bad_alloc();
#else
    std::terminate();
#endif
  }

  void Acquire() noexcept {
    if (control_ != nullptr) control_->fsv_retain_owner();
  }
  void Release() noexcept {
    if (control_ != nullptr) control_->fsv_release_owner();
  }

  fsv_basisu::FsvDecodeControl* control_ = nullptr;
};

using FsvBasisuString = std::basic_string<char, std::char_traits<char>,
                                          FsvBasisuAllocator<char>>;

template <typename T>
class FsvBasisuVector : public std::vector<T, FsvBasisuAllocator<T>> {
 public:
  using Base = std::vector<T, FsvBasisuAllocator<T>>;
  using Base::Base;
  using Base::operator=;

  FsvBasisuVector() = default;
  FsvBasisuVector(const FsvBasisuVector&) = default;
  FsvBasisuVector(FsvBasisuVector&&) noexcept = default;
  FsvBasisuVector& operator=(const FsvBasisuVector&) = default;
  FsvBasisuVector& operator=(FsvBasisuVector&&) noexcept = default;

  template <typename Allocator>
  FsvBasisuVector& operator=(const std::vector<T, Allocator>& values) {
    this->assign(values.begin(), values.end());
    return *this;
  }
};

using FsvBasisuByteVector = FsvBasisuVector<uint8_t>;

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

#endif  // FSV_BASISU_OWNED_H_
