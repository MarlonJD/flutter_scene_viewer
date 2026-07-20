#ifndef FSV_DRACO_PLATFORM_SERIALIZATION_H_
#define FSV_DRACO_PLATFORM_SERIALIZATION_H_

#include <cstdint>

#include "fsv_draco_control.h"

enum class FsvDracoPlatformCopyOutcome {
  kSuccess,
  kStopped,
  kSizeRejected,
  kAllocationFailed,
  kCopyFailed,
};

struct FsvDracoPlatformCopyCallbacks {
  void* context = nullptr;
  bool (*allocate)(void* context, uint64_t bytes,
                   void** destination) noexcept = nullptr;
  bool (*copy)(void* context, void* destination, const uint8_t* source,
               uint64_t bytes) noexcept = nullptr;
  void (*release)(void* context, void* destination) noexcept = nullptr;
};

// Copies one request-owned native payload into managed platform storage. The
// managed allocation is deliberately outside maxNativeWorkingBytes. The native
// result remains owned and charged by |control| for the entire callback.
inline FsvDracoPlatformCopyOutcome FsvDracoCopyBytesToPlatform(
    const uint8_t* source,
    uint64_t bytes,
    uint64_t signed_platform_max,
    fsv_draco::FsvDecodeControl* control,
    const FsvDracoPlatformCopyCallbacks& callbacks,
    void** destination) noexcept {
  if (destination == nullptr) {
    return FsvDracoPlatformCopyOutcome::kAllocationFailed;
  }
  *destination = nullptr;
  if (control != nullptr && control->IsCancelled()) {
    return FsvDracoPlatformCopyOutcome::kStopped;
  }
  if (bytes > signed_platform_max || (bytes != 0 && source == nullptr)) {
    return FsvDracoPlatformCopyOutcome::kSizeRejected;
  }
  if (callbacks.allocate == nullptr || callbacks.copy == nullptr ||
      callbacks.release == nullptr) {
    return FsvDracoPlatformCopyOutcome::kAllocationFailed;
  }
  void* managed = nullptr;
  if (!callbacks.allocate(callbacks.context, bytes, &managed) ||
      managed == nullptr) {
    return FsvDracoPlatformCopyOutcome::kAllocationFailed;
  }
  if (control != nullptr && control->IsCancelled()) {
    callbacks.release(callbacks.context, managed);
    return FsvDracoPlatformCopyOutcome::kStopped;
  }
  if (!callbacks.copy(callbacks.context, managed, source, bytes)) {
    callbacks.release(callbacks.context, managed);
    return FsvDracoPlatformCopyOutcome::kCopyFailed;
  }
  if (control != nullptr && control->IsCancelled()) {
    callbacks.release(callbacks.context, managed);
    return FsvDracoPlatformCopyOutcome::kStopped;
  }
  *destination = managed;
  return FsvDracoPlatformCopyOutcome::kSuccess;
}

#endif  // FSV_DRACO_PLATFORM_SERIALIZATION_H_
