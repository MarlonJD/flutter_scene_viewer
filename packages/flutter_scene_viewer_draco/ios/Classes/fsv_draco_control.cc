#include "fsv_draco_control.h"

#include <algorithm>
#include <cstddef>
#include <cstdlib>
#include <new>

namespace fsv_draco {

namespace {

FsvDecodeAllocationOutcome OutcomeForStopReason(FsvDecodeStopReason reason) {
  switch (reason) {
    case FsvDecodeStopReason::kCallerCancelled:
    case FsvDecodeStopReason::kDeadline:
      return FsvDecodeAllocationOutcome::kStopped;
    case FsvDecodeStopReason::kBudget:
      return FsvDecodeAllocationOutcome::kBudgetExceeded;
    case FsvDecodeStopReason::kAllocationFailure:
    case FsvDecodeStopReason::kNone:
      return FsvDecodeAllocationOutcome::kHeapFailure;
  }
  return FsvDecodeAllocationOutcome::kHeapFailure;
}

}  // namespace

FsvDecodeControl::FsvDecodeControl(uint64_t working_byte_limit,
                                   FsvDecodeHeap* heap)
    : working_byte_limit_(working_byte_limit), heap_(heap) {}

FsvDecodeControl::~FsvDecodeControl() {
  if (owner_count_.load() != 0 || live_bytes_.load() != 0) {
    std::abort();
  }
}

bool FsvDecodeControl::Cancel() {
  FsvDecodeStopReason reason = FsvDecodeStopReason::kNone;
  return stop_reason_.compare_exchange_strong(
      reason, FsvDecodeStopReason::kCallerCancelled);
}

bool FsvDecodeControl::Deadline() {
  FsvDecodeStopReason reason = FsvDecodeStopReason::kNone;
  return stop_reason_.compare_exchange_strong(reason,
                                              FsvDecodeStopReason::kDeadline);
}

bool FsvDecodeControl::AllocationFailure() {
  FsvDecodeStopReason reason = FsvDecodeStopReason::kNone;
  return stop_reason_.compare_exchange_strong(
      reason, FsvDecodeStopReason::kAllocationFailure);
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

FsvDecodeAllocationResult FsvDecodeControl::AllocateMemory(
    size_t bytes,
    size_t alignment) noexcept {
  const size_t allocation_bytes = std::max<size_t>(bytes, 1);
  if (!TryReserve(allocation_bytes)) {
    return {nullptr, allocation_bytes, alignment,
            OutcomeForStopReason(stop_reason_.load())};
  }
  void* allocation = nullptr;
  if (heap_ != nullptr) {
    allocation = heap_->Allocate(allocation_bytes, alignment);
  } else {
#if defined(__cpp_aligned_new)
    if (alignment > __STDCPP_DEFAULT_NEW_ALIGNMENT__) {
      allocation =
          ::operator new(allocation_bytes, std::align_val_t(alignment),
                         std::nothrow);
    } else {
#endif
      allocation = ::operator new(allocation_bytes, std::nothrow);
#if defined(__cpp_aligned_new)
    }
#endif
  }
  if (allocation == nullptr) {
    Release(allocation_bytes);
    FsvDecodeStopReason reason = FsvDecodeStopReason::kNone;
    if (stop_reason_.compare_exchange_strong(
            reason, FsvDecodeStopReason::kAllocationFailure)) {
      return {nullptr, allocation_bytes, alignment,
              FsvDecodeAllocationOutcome::kHeapFailure};
    }
    return {nullptr, allocation_bytes, alignment, OutcomeForStopReason(reason)};
  }
  return {allocation, allocation_bytes, alignment,
          FsvDecodeAllocationOutcome::kSuccess};
}

bool FsvDecodeControl::ReleaseMemory(
    FsvDecodeAllocationResult* allocation_record,
    void* allocation,
    size_t bytes,
    size_t alignment) noexcept {
  const size_t allocation_bytes = std::max<size_t>(bytes, 1);
  if (allocation_record == nullptr ||
      allocation_record->outcome != FsvDecodeAllocationOutcome::kSuccess ||
      allocation_record->allocation != allocation ||
      allocation_record->bytes != allocation_bytes ||
      allocation_record->alignment != alignment) {
    release_mismatch_count_.fetch_add(1);
    return false;
  }
  *allocation_record = FsvDecodeAllocationResult();
  ReleaseMemoryUnchecked(allocation, allocation_bytes, alignment);
  return true;
}

void FsvDecodeControl::ReleaseMemoryUnchecked(void* allocation,
                                              size_t bytes,
                                              size_t alignment) noexcept {
  if (allocation == nullptr) {
    return;
  }
  if (heap_ != nullptr) {
    heap_->Release(allocation, std::max<size_t>(bytes, 1), alignment);
    Release(std::max<size_t>(bytes, 1));
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
  Release(std::max<size_t>(bytes, 1));
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

uint64_t FsvDecodeControl::release_mismatch_count() const {
  return release_mismatch_count_.load();
}

void FsvDecodeControl::RecordReleaseMismatch() noexcept {
  release_mismatch_count_.fetch_add(1);
}

FsvDecodeStopReason FsvDecodeControl::stop_reason() const {
  return stop_reason_.load();
}

void FsvDecodeControl::AcquireOwner() noexcept { owner_count_.fetch_add(1); }

void FsvDecodeControl::ReleaseOwner() noexcept { owner_count_.fetch_sub(1); }

uint64_t FsvDecodeControl::owner_count() const { return owner_count_.load(); }

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

}  // namespace fsv_draco
