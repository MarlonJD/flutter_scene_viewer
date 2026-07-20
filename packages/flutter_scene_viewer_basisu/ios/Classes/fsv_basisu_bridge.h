#ifndef FSV_BASISU_BRIDGE_H_
#define FSV_BASISU_BRIDGE_H_

#include <string>
#include <utility>
#include <vector>

#include "fsv_basisu_budget.h"
#include "fsv_basisu_control.h"

struct FsvBasisuDecodedMipLevel {
  explicit FsvBasisuDecodedMipLevel(
      fsv_basisu::FsvDecodeControl* control = nullptr)
      : rgba_bytes(FsvBasisuAllocator<uint8_t>(control)), control_(control) {}
  FsvBasisuDecodedMipLevel(uint32_t level_value, uint32_t width_value,
                           uint32_t height_value,
                           FsvBasisuByteVector bytes_value,
                           fsv_basisu::FsvDecodeControl* control)
      : level(level_value),
        width(width_value),
        height(height_value),
        rgba_bytes(std::move(bytes_value)),
        control_(control) {}

  uint32_t level = 0;
  uint32_t width = 0;
  uint32_t height = 0;
  FsvBasisuByteVector rgba_bytes;

  fsv_basisu::FsvDecodeControl* control() const { return control_; }

 private:
  fsv_basisu::FsvDecodeControl* control_ = nullptr;
};

struct FsvBasisuDecodedImage {
  explicit FsvBasisuDecodedImage(
      fsv_basisu::FsvDecodeControl* control = nullptr)
      : content_role(FsvBasisuAllocator<char>(control)),
        levels(FsvBasisuAllocator<FsvBasisuDecodedMipLevel>(control)),
        control_(control) {}

  int image_index = -1;
  FsvBasisuString content_role;
  FsvBasisuVector<FsvBasisuDecodedMipLevel> levels;

  fsv_basisu::FsvDecodeControl* control() const { return control_; }

 private:
  fsv_basisu::FsvDecodeControl* control_ = nullptr;
};

enum class FsvBasisuTerminalOutcomeKind {
  kNone,
  kCallerCancelled,
  kDeadline,
  kBudgetExceeded,
  kAllocationFailed,
};

struct FsvBasisuTranscodeResult {
  explicit FsvBasisuTranscodeResult(
      fsv_basisu::FsvDecodeControl* control = nullptr)
      : decoded_images(FsvBasisuAllocator<FsvBasisuDecodedImage>(control)),
        diagnostics(FsvBasisuAllocator<FsvBasisuDiagnostic>(control)),
        control_(control) {}

  void Reset() {
    decoded_images.clear();
    diagnostics.clear();
    terminal_outcome = FsvBasisuTerminalOutcomeKind::kNone;
  }

  fsv_basisu::FsvDecodeControl* control() const { return control_; }

  FsvBasisuVector<FsvBasisuDecodedImage> decoded_images;
  FsvBasisuVector<FsvBasisuDiagnostic> diagnostics;
  FsvBasisuTerminalOutcomeKind terminal_outcome =
      FsvBasisuTerminalOutcomeKind::kNone;

 private:
  fsv_basisu::FsvDecodeControl* control_ = nullptr;
};

struct FsvBasisuTranscodeTestingHooks {
  bool fail_next_codec_allocation = false;
  int cancel_before_level = -1;
  int cancel_before_request_index = -1;
};

void FsvBasisuRecordTerminalOutcome(
    FsvBasisuTranscodeResult* result,
    fsv_basisu::FsvDecodeControl* control) noexcept;

bool FsvBasisuTranscoderLinked();
bool FsvBasisuImageTranscodeAvailable();
FsvBasisuTranscodeResult FsvBasisuTranscodeImages(
    const FsvBasisuImageRequests& requests,
    const FsvBasisuDecodeBudgetMetadata& budget,
    const FsvBasisuDecodeBudgetState& state,
    fsv_basisu::FsvDecodeControl* control = nullptr,
    FsvBasisuTranscodeTestingHooks* testing_hooks = nullptr);

#endif  // FSV_BASISU_BRIDGE_H_
