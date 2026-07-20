#ifndef FSV_BASISU_PLATFORM_SERIALIZATION_H_
#define FSV_BASISU_PLATFORM_SERIALIZATION_H_

#include <cstdint>

#include "fsv_basisu_control.h"

enum class FsvBasisuPlatformCopyOutcome {
  kSuccess,
  kStopped,
  kSizeRejected,
  kAllocationFailed,
  kCopyFailed,
};

struct FsvBasisuPlatformCopyCallbacks {
  void* context = nullptr;
  bool (*allocate)(void* context, uint64_t bytes,
                   void** destination) noexcept = nullptr;
  bool (*copy)(void* context, void* destination, const uint8_t* source,
               uint64_t bytes) noexcept = nullptr;
  void (*release)(void* context, void* destination) noexcept = nullptr;
};

// Managed platform storage is outside maxNativeWorkingBytes. Native source
// storage remains request-owned and charged for the entire managed copy.
inline FsvBasisuPlatformCopyOutcome FsvBasisuCopyBytesToPlatform(
    const uint8_t* source,
    uint64_t bytes,
    uint64_t signed_platform_max,
    fsv_basisu::FsvDecodeControl* control,
    const FsvBasisuPlatformCopyCallbacks& callbacks,
    void** destination) noexcept {
  if (destination == nullptr) {
    return FsvBasisuPlatformCopyOutcome::kAllocationFailed;
  }
  *destination = nullptr;
  if (control != nullptr && control->IsCancelled()) {
    return FsvBasisuPlatformCopyOutcome::kStopped;
  }
  if (bytes > signed_platform_max || (bytes != 0 && source == nullptr)) {
    return FsvBasisuPlatformCopyOutcome::kSizeRejected;
  }
  if (callbacks.allocate == nullptr || callbacks.copy == nullptr ||
      callbacks.release == nullptr) {
    return FsvBasisuPlatformCopyOutcome::kAllocationFailed;
  }
  void* managed = nullptr;
  if (!callbacks.allocate(callbacks.context, bytes, &managed) ||
      managed == nullptr) {
    return FsvBasisuPlatformCopyOutcome::kAllocationFailed;
  }
  if (control != nullptr && control->IsCancelled()) {
    callbacks.release(callbacks.context, managed);
    return FsvBasisuPlatformCopyOutcome::kStopped;
  }
  if (!callbacks.copy(callbacks.context, managed, source, bytes)) {
    callbacks.release(callbacks.context, managed);
    return FsvBasisuPlatformCopyOutcome::kCopyFailed;
  }
  if (control != nullptr && control->IsCancelled()) {
    callbacks.release(callbacks.context, managed);
    return FsvBasisuPlatformCopyOutcome::kStopped;
  }
  *destination = managed;
  return FsvBasisuPlatformCopyOutcome::kSuccess;
}

#endif  // FSV_BASISU_PLATFORM_SERIALIZATION_H_
