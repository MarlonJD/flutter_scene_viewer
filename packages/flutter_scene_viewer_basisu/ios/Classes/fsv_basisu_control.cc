#include "fsv_basisu_control.h"

#include <algorithm>
#include <cstdlib>
#include <new>

namespace fsv_basisu {

FsvDecodeControl::FsvDecodeControl(uint64_t working_byte_limit,
                                   FsvAllocationHeap* heap)
    : working_byte_limit_(working_byte_limit), heap_(heap) {}

FsvDecodeControl::~FsvDecodeControl() {
  if (owner_count_.load() != 0 || live_bytes_.load() != 0) std::abort();
}

bool FsvDecodeControl::Cancel() {
  FsvDecodeStopReason reason = FsvDecodeStopReason::kNone;
  return stop_reason_.compare_exchange_strong(
      reason, FsvDecodeStopReason::kCallerCancelled);
}

bool FsvDecodeControl::Deadline() {
  FsvDecodeStopReason reason = FsvDecodeStopReason::kNone;
  return stop_reason_.compare_exchange_strong(
      reason, FsvDecodeStopReason::kDeadline);
}

bool FsvDecodeControl::IsCancelled() const {
  const FsvDecodeStopReason reason = stop_reason_.load();
  return reason == FsvDecodeStopReason::kCallerCancelled ||
         reason == FsvDecodeStopReason::kDeadline;
}

bool FsvDecodeControl::TryReserve(uint64_t bytes) {
  if (stop_reason_.load() != FsvDecodeStopReason::kNone) {
    reserve_rejection_count_.fetch_add(1);
    return false;
  }
  uint64_t current = live_bytes_.load();
  while (true) {
    if (bytes > working_byte_limit_ ||
        current > working_byte_limit_ - bytes) {
      FsvDecodeStopReason reason = FsvDecodeStopReason::kNone;
      stop_reason_.compare_exchange_strong(reason, FsvDecodeStopReason::kBudget);
      reserve_rejection_count_.fetch_add(1);
      return false;
    }
    if (live_bytes_.compare_exchange_weak(current, current + bytes)) {
      allocation_count_.fetch_add(1);
      if (stop_reason_.load() != FsvDecodeStopReason::kNone) {
        Release(bytes);
        reserve_rejection_count_.fetch_add(1);
        return false;
      }
      uint64_t peak = peak_bytes_.load();
      const uint64_t next = current + bytes;
      while (peak < next &&
             !peak_bytes_.compare_exchange_weak(peak, next)) {
      }
      return true;
    }
  }
}

void FsvDecodeControl::Release(uint64_t bytes) {
  uint64_t current = live_bytes_.load();
  while (!live_bytes_.compare_exchange_weak(
      current, current - std::min(current, bytes))) {
  }
  release_count_.fetch_add(1);
}

uint64_t FsvDecodeControl::live_bytes() const { return live_bytes_.load(); }

uint64_t FsvDecodeControl::peak_bytes() const { return peak_bytes_.load(); }

uint64_t FsvDecodeControl::allocation_count() const {
  return allocation_count_.load();
}

uint64_t FsvDecodeControl::release_count() const {
  return release_count_.load();
}

uint64_t FsvDecodeControl::reserve_rejection_count() const {
  return reserve_rejection_count_.load();
}

FsvDecodeStopReason FsvDecodeControl::stop_reason() const {
  return stop_reason_.load();
}

FsvAllocationOutcome FsvDecodeControl::last_allocation_outcome() const {
  return last_allocation_outcome_.load();
}

uint64_t FsvDecodeControl::request_allocation_count() const {
  return request_allocation_count_.load();
}

uint64_t FsvDecodeControl::request_release_count() const {
  return request_release_count_.load();
}

uint64_t FsvDecodeControl::release_mismatch_count() const {
  return release_mismatch_count_.load();
}

uint64_t FsvDecodeControl::owner_count() const { return owner_count_.load(); }

namespace {
size_t NormalizeAlignment(size_t alignment) {
  const size_t minimum = alignof(void*);
  if (alignment < minimum) alignment = minimum;
  if ((alignment & (alignment - 1)) != 0) return 0;
  return alignment;
}

void* SystemAllocate(size_t bytes, size_t alignment) {
  if (alignment <= alignof(std::max_align_t)) return std::malloc(bytes);
  void* pointer = nullptr;
  return posix_memalign(&pointer, alignment, bytes) == 0 ? pointer : nullptr;
}
}  // namespace

basisu::fsv_allocation_result FsvDecodeControl::fsv_allocate(
    size_t bytes, size_t alignment) {
  basisu::fsv_allocation_result result;
  const size_t normalized_bytes = bytes == 0 ? 1 : bytes;
  const size_t normalized_alignment = NormalizeAlignment(alignment);
  if (normalized_alignment == 0) {
    last_allocation_outcome_.store(FsvAllocationOutcome::kHeapFailure);
    result.m_outcome = basisu::fsv_allocation_outcome::kHeapFailure;
    return result;
  }
  if (!TryReserve(normalized_bytes)) {
    const FsvDecodeStopReason reason = stop_reason();
    const FsvAllocationOutcome outcome = reason == FsvDecodeStopReason::kBudget
        ? FsvAllocationOutcome::kBudgetExceeded
        : reason == FsvDecodeStopReason::kHeapFailure
            ? FsvAllocationOutcome::kHeapFailure
            : FsvAllocationOutcome::kStopped;
    last_allocation_outcome_.store(outcome);
    result.m_outcome = outcome == FsvAllocationOutcome::kBudgetExceeded
        ? basisu::fsv_allocation_outcome::kBudgetExceeded
        : outcome == FsvAllocationOutcome::kHeapFailure
            ? basisu::fsv_allocation_outcome::kHeapFailure
            : basisu::fsv_allocation_outcome::kStopped;
    return result;
  }
  void* pointer = heap_ ? heap_->Allocate(normalized_bytes, normalized_alignment)
                        : SystemAllocate(normalized_bytes, normalized_alignment);
  if (!pointer) {
    Release(normalized_bytes);
    FsvDecodeStopReason expected = FsvDecodeStopReason::kNone;
    stop_reason_.compare_exchange_strong(expected, FsvDecodeStopReason::kHeapFailure);
    last_allocation_outcome_.store(FsvAllocationOutcome::kHeapFailure);
    result.m_outcome = basisu::fsv_allocation_outcome::kHeapFailure;
    return result;
  }
  request_allocation_count_.fetch_add(1);
  last_allocation_outcome_.store(FsvAllocationOutcome::kSuccess);
  result.m_p = pointer;
  result.m_bytes = normalized_bytes;
  result.m_alignment = normalized_alignment;
  result.m_outcome = basisu::fsv_allocation_outcome::kSuccess;
  result.m_allocator = this;
  return result;
}

bool FsvDecodeControl::fsv_release(basisu::fsv_allocation_result& allocation,
                                   void* pointer, size_t bytes, size_t alignment) {
  if (!pointer || allocation.m_allocator != this || allocation.m_p != pointer ||
      allocation.m_outcome != basisu::fsv_allocation_outcome::kSuccess) {
    release_mismatch_count_.fetch_add(1);
    return false;
  }
  const size_t normalized_bytes = bytes == 0 ? 1 : bytes;
  const size_t normalized_alignment = NormalizeAlignment(alignment);
  if (allocation.m_bytes != normalized_bytes || allocation.m_alignment != normalized_alignment) {
    release_mismatch_count_.fetch_add(1);
    return false;
  }
  const size_t allocation_bytes = allocation.m_bytes;
  const size_t allocation_alignment = allocation.m_alignment;
  allocation.reset();
  if (heap_) heap_->Release(pointer, allocation_bytes, allocation_alignment);
  else std::free(pointer);
  Release(allocation_bytes);
  request_release_count_.fetch_add(1);
  return true;
}

void FsvDecodeControl::fsv_retain_owner() noexcept { owner_count_.fetch_add(1); }
void FsvDecodeControl::fsv_release_owner() noexcept { owner_count_.fetch_sub(1); }

FsvScopedWorkingReservation::FsvScopedWorkingReservation(
    FsvDecodeControl* control,
    uint64_t bytes)
    : control_(control),
      bytes_(bytes),
      reserved_(control == nullptr || control->TryReserve(bytes)) {}

FsvScopedWorkingReservation::~FsvScopedWorkingReservation() {
  if (control_ != nullptr && reserved_) {
    control_->Release(bytes_);
  }
}

}  // namespace fsv_basisu
