#include <atomic>
#include <cstddef>
#include <cstdint>
#include <thread>

#include "fsv_draco_control.h"

namespace {

class BlockingFailHeap final : public fsv_draco::FsvDecodeHeap {
 public:
  void* Allocate(size_t bytes, size_t alignment) noexcept override {
    static_cast<void>(bytes);
    static_cast<void>(alignment);
    entered_.store(true);
    while (!may_return_.load()) {
      std::this_thread::yield();
    }
    return nullptr;
  }

  void Release(void* allocation, size_t bytes,
               size_t alignment) noexcept override {
    static_cast<void>(allocation);
    static_cast<void>(bytes);
    static_cast<void>(alignment);
  }

  void WaitUntilEntered() const {
    while (!entered_.load()) {
      std::this_thread::yield();
    }
  }

  void AllowReturn() { may_return_.store(true); }

 private:
  std::atomic<bool> entered_{false};
  std::atomic<bool> may_return_{false};
};

bool StopWins(bool deadline) {
  BlockingFailHeap heap;
  fsv_draco::FsvDecodeControl control(8, &heap);
  fsv_draco::FsvDecodeAllocationResult result;
  std::thread allocation([&] {
    result = control.AllocateMemory(8, alignof(std::max_align_t));
  });
  heap.WaitUntilEntered();
  const bool stop_won = deadline ? control.Deadline() : control.Cancel();
  heap.AllowReturn();
  allocation.join();
  const auto expected_reason = deadline
                                   ? fsv_draco::FsvDecodeStopReason::kDeadline
                                   : fsv_draco::FsvDecodeStopReason::kCallerCancelled;
  return stop_won && result.allocation == nullptr &&
         result.outcome == fsv_draco::FsvDecodeAllocationOutcome::kStopped &&
         control.stop_reason() == expected_reason && control.live_bytes() == 0 &&
         control.allocation_count() == 1 && control.release_count() == 1;
}

bool HeapFailureWins() {
  BlockingFailHeap heap;
  fsv_draco::FsvDecodeControl control(8, &heap);
  fsv_draco::FsvDecodeAllocationResult result;
  std::thread allocation([&] {
    result = control.AllocateMemory(8, alignof(std::max_align_t));
  });
  heap.WaitUntilEntered();
  heap.AllowReturn();
  allocation.join();
  return result.allocation == nullptr &&
         result.outcome ==
             fsv_draco::FsvDecodeAllocationOutcome::kHeapFailure &&
         !control.Cancel() &&
         control.stop_reason() ==
             fsv_draco::FsvDecodeStopReason::kAllocationFailure &&
         control.live_bytes() == 0 && control.allocation_count() == 1 &&
         control.release_count() == 1;
}

bool BudgetWins() {
  fsv_draco::FsvDecodeControl control(7);
  const fsv_draco::FsvDecodeAllocationResult result =
      control.AllocateMemory(8, alignof(std::max_align_t));
  return result.allocation == nullptr &&
         result.outcome ==
             fsv_draco::FsvDecodeAllocationOutcome::kBudgetExceeded &&
         control.stop_reason() == fsv_draco::FsvDecodeStopReason::kBudget &&
         control.live_bytes() == 0;
}

}  // namespace

int main() {
  if (!StopWins(false)) return 1;
  if (!StopWins(true)) return 2;
  if (!HeapFailureWins()) return 3;
  if (!BudgetWins()) return 4;
  return 0;
}
