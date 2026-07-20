#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <new>
#include <vector>

#include "draco/core/fsv_decode_allocator.h"

namespace {

struct alignas(256) OverAlignedValue {
  uint8_t value = 0;
};

class Control final : public draco::FsvDecodeControl {
 public:
  explicit Control(uint64_t limit) : limit_(limit) {}

  bool ShouldStopDecoding() const override { return false; }

  AllocationResult AllocateMemory(size_t bytes,
                                  size_t alignment) noexcept override {
    ++reserve_calls_;
    if (bytes > limit_ || live_ > limit_ - bytes) {
      budget_exhausted_ = true;
      return {nullptr, AllocationOutcome::kBudgetExceeded};
    }
    live_ += bytes;
    if (fail_next_allocation_) {
      fail_next_allocation_ = false;
      live_ -= bytes;
      ++release_calls_;
      return {nullptr, AllocationOutcome::kHeapFailure};
    }
    void* allocation = nullptr;
    if (alignment <= alignof(std::max_align_t)) {
      allocation = std::malloc(bytes);
    }
    if (allocation == nullptr) {
      live_ -= bytes;
      ++release_calls_;
    }
    return {allocation, bytes, alignment,
            allocation == nullptr ? AllocationOutcome::kHeapFailure
                                  : AllocationOutcome::kSuccess};
  }

  bool ReleaseMemory(AllocationResult* allocation_record,
                     void* allocation, size_t bytes,
                     size_t alignment) noexcept override {
    if (allocation_record == nullptr ||
        allocation_record->allocation != allocation ||
        allocation_record->bytes != bytes ||
        allocation_record->alignment != alignment ||
        allocation_record->outcome != AllocationOutcome::kSuccess) {
      return false;
    }
    *allocation_record = AllocationResult();
    static_cast<void>(alignment);
    ++release_calls_;
    live_ -= bytes;
    std::free(allocation);
    return true;
  }

  bool budget_exhausted() const { return budget_exhausted_; }

  uint64_t live() const { return live_; }
  uint64_t reserve_calls() const { return reserve_calls_; }
  uint64_t release_calls() const { return release_calls_; }
  void FailNextAllocation() { fail_next_allocation_ = true; }

 private:
  uint64_t limit_;
  uint64_t live_ = 0;
  uint64_t reserve_calls_ = 0;
  uint64_t release_calls_ = 0;
  bool budget_exhausted_ = false;
  bool fail_next_allocation_ = false;
};

}  // namespace

int main() {
  Control zero(1);
  {
    draco::FsvDecodeAllocator<uint32_t> allocator(&zero);
    uint32_t* const allocation = allocator.allocate(0);
    if (allocation == nullptr || zero.live() != 1) {
      return 10;
    }
    allocator.deallocate(allocation, 0);
  }
  if (zero.live() != 0 || zero.reserve_calls() != 1 ||
      zero.release_calls() != 1) {
    return 11;
  }

  Control exact(4 * sizeof(uint32_t));
  {
    std::vector<uint32_t, draco::FsvDecodeAllocator<uint32_t>> values{
        draco::FsvDecodeAllocator<uint32_t>(&exact)};
    values.resize(4);
    if (exact.reserve_calls() != 1 || exact.live() != 4 * sizeof(uint32_t)) {
      return 1;
    }
  }
  if (exact.live() != 0 || exact.release_calls() != 1) {
    return 2;
  }

  Control too_small(sizeof(uint32_t));
  try {
    std::vector<uint32_t, draco::FsvDecodeAllocator<uint32_t>> values{
        draco::FsvDecodeAllocator<uint32_t>(&too_small)};
    values.resize(2);
    return 3;
  } catch (const draco::FsvDecodeBudgetExceeded&) {
  } catch (...) {
    return 4;
  }
  if (!too_small.budget_exhausted() || too_small.live() != 0 ||
      too_small.release_calls() != 0) {
    return 5;
  }

  Control heap_failure(8);
  heap_failure.FailNextAllocation();
  draco::FsvDecodeAllocator<uint8_t> allocator(&heap_failure);
  try {
    static_cast<void>(allocator.allocate(8));
    return 6;
  } catch (const std::bad_alloc&) {
  }
  if (heap_failure.budget_exhausted() || heap_failure.live() != 0 ||
      heap_failure.reserve_calls() != 1 || heap_failure.release_calls() != 1) {
    return 7;
  }

  draco::FsvDecodeAllocator<OverAlignedValue> fallback_allocator;
  std::vector<OverAlignedValue*> fallback_allocations;
  for (size_t count = 1; count <= 32; ++count) {
    OverAlignedValue* allocation = fallback_allocator.allocate(count);
    fallback_allocations.push_back(allocation);
    if (reinterpret_cast<uintptr_t>(allocation) % alignof(OverAlignedValue) !=
        0) {
      return 8;
    }
  }
  for (size_t index = 0; index < fallback_allocations.size(); ++index) {
    fallback_allocator.deallocate(fallback_allocations[index], index + 1);
  }
  return 0;
}
