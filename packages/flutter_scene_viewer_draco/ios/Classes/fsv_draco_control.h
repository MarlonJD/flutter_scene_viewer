#ifndef FSV_DRACO_CONTROL_H_
#define FSV_DRACO_CONTROL_H_

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <exception>
#include <new>

namespace fsv_draco {

class FsvDecodeStopped final : public std::exception {};
class FsvDecodeBudgetExceeded final : public std::bad_alloc {};

enum class FsvDecodeStopReason {
  kNone,
  kCallerCancelled,
  kDeadline,
  kBudget,
  kAllocationFailure,
};

enum class FsvDecodeAllocationOutcome {
  kSuccess,
  kStopped,
  kBudgetExceeded,
  kHeapFailure,
};

struct FsvDecodeAllocationResult {
  void* allocation = nullptr;
  size_t bytes = 0;
  size_t alignment = 0;
  FsvDecodeAllocationOutcome outcome = FsvDecodeAllocationOutcome::kHeapFailure;
};

class FsvDecodeHeap {
 public:
  virtual ~FsvDecodeHeap() = default;
  virtual void* Allocate(size_t bytes, size_t alignment) noexcept = 0;
  virtual void Release(void* allocation, size_t bytes,
                       size_t alignment) noexcept = 0;
};

class FsvDecodeControl {
 public:
  explicit FsvDecodeControl(uint64_t working_byte_limit,
                            FsvDecodeHeap* heap = nullptr);
  ~FsvDecodeControl();

  FsvDecodeControl(const FsvDecodeControl&) = delete;
  FsvDecodeControl& operator=(const FsvDecodeControl&) = delete;

  bool Cancel();
  bool Deadline();
  bool AllocationFailure();
  bool IsCancelled() const;
  bool TryReserve(uint64_t bytes);
  void Release(uint64_t bytes);
  FsvDecodeAllocationResult AllocateMemory(size_t bytes,
                                           size_t alignment) noexcept;
  bool ReleaseMemory(FsvDecodeAllocationResult* allocation_record,
                     void* allocation,
                     size_t bytes,
                     size_t alignment) noexcept;
  uint64_t live_bytes() const;
  uint64_t peak_bytes() const;
  uint64_t allocation_count() const;
  uint64_t release_count() const;
  uint64_t reserve_rejection_count() const;
  uint64_t release_mismatch_count() const;
  void RecordReleaseMismatch() noexcept;
  FsvDecodeStopReason stop_reason() const;
  void AcquireOwner() noexcept;
  void ReleaseOwner() noexcept;
  uint64_t owner_count() const;

 private:
  const uint64_t working_byte_limit_;
  FsvDecodeHeap* const heap_;
  std::atomic<uint64_t> live_bytes_{0};
  std::atomic<uint64_t> peak_bytes_{0};
  std::atomic<uint64_t> allocation_count_{0};
  std::atomic<uint64_t> release_count_{0};
  std::atomic<uint64_t> reserve_rejection_count_{0};
  std::atomic<uint64_t> release_mismatch_count_{0};
  std::atomic<uint64_t> owner_count_{0};
  std::atomic<FsvDecodeStopReason> stop_reason_{FsvDecodeStopReason::kNone};

  void ReleaseMemoryUnchecked(void* allocation, size_t bytes,
                              size_t alignment) noexcept;
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

}  // namespace fsv_draco

#endif  // FSV_DRACO_CONTROL_H_
