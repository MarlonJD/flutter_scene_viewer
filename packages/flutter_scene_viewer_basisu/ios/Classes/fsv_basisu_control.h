#ifndef FSV_BASISU_CONTROL_H_
#define FSV_BASISU_CONTROL_H_

#include <atomic>
#include <cassert>
#include <cstdint>
#include <cstddef>
#include <mutex>

#include "basisu_containers.h"

namespace fsv_basisu {

enum class FsvDecodeStopReason {
  kNone,
  kCallerCancelled,
  kDeadline,
  kBudget,
  kHeapFailure,
};

enum class FsvAllocationOutcome {
  kSuccess,
  kStopped,
  kBudgetExceeded,
  kHeapFailure,
};

class FsvAllocationHeap {
 public:
  virtual ~FsvAllocationHeap() = default;
  virtual void* Allocate(size_t bytes, size_t alignment) noexcept = 0;
  virtual void Release(void* pointer, size_t bytes, size_t alignment) noexcept = 0;
};

class FsvDecodeControl final : public basisu::fsv_vector_allocator {
 public:
  explicit FsvDecodeControl(uint64_t working_byte_limit,
                            FsvAllocationHeap* heap = nullptr);
  ~FsvDecodeControl() override;

  bool Cancel();
  bool Deadline();
  bool IsCancelled() const;
  bool TryReserve(uint64_t bytes);
  void Release(uint64_t bytes);
  uint64_t live_bytes() const;
  uint64_t peak_bytes() const;
  uint64_t allocation_count() const;
  uint64_t release_count() const;
  uint64_t reserve_rejection_count() const;
  FsvDecodeStopReason stop_reason() const;
  FsvAllocationOutcome last_allocation_outcome() const;
  uint64_t request_allocation_count() const;
  uint64_t request_release_count() const;
  uint64_t release_mismatch_count() const;
  uint64_t owner_count() const;

  basisu::fsv_allocation_result fsv_allocate(size_t bytes,
                                              size_t alignment) override;
  bool fsv_release(basisu::fsv_allocation_result& allocation, void* pointer,
                   size_t bytes, size_t alignment) override;
  void fsv_retain_owner() noexcept override;
  void fsv_release_owner() noexcept override;

 private:
  const uint64_t working_byte_limit_;
  FsvAllocationHeap* const heap_;
  std::atomic<uint64_t> live_bytes_{0};
  std::atomic<uint64_t> peak_bytes_{0};
  std::atomic<uint64_t> allocation_count_{0};
  std::atomic<uint64_t> release_count_{0};
  std::atomic<uint64_t> reserve_rejection_count_{0};
  std::atomic<FsvDecodeStopReason> stop_reason_{FsvDecodeStopReason::kNone};
  std::atomic<FsvAllocationOutcome> last_allocation_outcome_{
      FsvAllocationOutcome::kSuccess};
  std::atomic<uint64_t> request_allocation_count_{0};
  std::atomic<uint64_t> request_release_count_{0};
  std::atomic<uint64_t> release_mismatch_count_{0};
  std::atomic<uint64_t> owner_count_{0};
};

class FsvScopedWorkingReservation {
 public:
  FsvScopedWorkingReservation(FsvDecodeControl* control, uint64_t bytes);
  ~FsvScopedWorkingReservation();

  FsvScopedWorkingReservation(const FsvScopedWorkingReservation&) = delete;
  FsvScopedWorkingReservation& operator=(
      const FsvScopedWorkingReservation&) = delete;

  bool ok() const { return reserved_; }

 private:
  FsvDecodeControl* control_;
  uint64_t bytes_;
  bool reserved_;
};

}  // namespace fsv_basisu

#endif  // FSV_BASISU_CONTROL_H_
