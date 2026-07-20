#ifndef FSV_BASISU_BUDGET_H_
#define FSV_BASISU_BUDGET_H_

#include <cstdint>
#include <string_view>

#include "fsv_basisu_owned.h"

constexpr int64_t kFsvBasisuMaxSafeInteger = INT64_C(9007199254740991);

struct FsvBasisuBudgetNumber {
  bool present = false;
  bool is_integer = false;
  int64_t value = 0;

  static FsvBasisuBudgetNumber Integer(int64_t value) {
    FsvBasisuBudgetNumber number;
    number.present = true;
    number.is_integer = true;
    number.value = value;
    return number;
  }

  static FsvBasisuBudgetNumber Invalid() {
    FsvBasisuBudgetNumber number;
    number.present = true;
    return number;
  }
};

struct FsvBasisuDecodeBudgetMetadata {
  FsvBasisuBudgetNumber max_total_decoded_bytes;
  FsvBasisuBudgetNumber max_texture_pixels;
  FsvBasisuBudgetNumber max_native_output_bytes;
  FsvBasisuBudgetNumber max_native_working_bytes;
};

struct FsvBasisuDecodeBudgetState {
  FsvBasisuBudgetNumber total_decoded_bytes;
  FsvBasisuBudgetNumber texture_pixels;
  FsvBasisuBudgetNumber native_output_bytes;
};

enum class FsvBasisuUsageRole {
  kStructuralOnly,
  kColor,
  kNonColor,
  kAmbiguous,
};

bool FsvBasisuUsageRoleFromString(std::string_view value,
                                  FsvBasisuUsageRole* role);

enum class FsvBasisuChannelLayout {
  kStructuralOnly,
  kR,
  kRg,
  kRgb,
  kRgba,
};

bool FsvBasisuChannelLayoutFromString(std::string_view value,
                                      FsvBasisuChannelLayout* layout);

struct FsvBasisuImageRequest {
  explicit FsvBasisuImageRequest(
      fsv_basisu::FsvDecodeControl* control = nullptr)
      : metadata_field(FsvBasisuAllocator<char>(control)),
        mime_type(FsvBasisuAllocator<char>(control)),
        bytes(FsvBasisuAllocator<uint8_t>(control)),
        control_(control) {}

  int texture_index = -1;
  int image_index = -1;
  bool metadata_valid = true;
  FsvBasisuString metadata_field;
  FsvBasisuUsageRole usage_role = FsvBasisuUsageRole::kStructuralOnly;
  FsvBasisuChannelLayout channel_layout =
      FsvBasisuChannelLayout::kStructuralOnly;
  FsvBasisuString mime_type;
  FsvBasisuByteVector bytes;

  fsv_basisu::FsvDecodeControl* control() const { return control_; }

 private:
  fsv_basisu::FsvDecodeControl* control_ = nullptr;
};

struct FsvBasisuDiagnostic {
  explicit FsvBasisuDiagnostic(
      fsv_basisu::FsvDecodeControl* control = nullptr)
      : status(FsvBasisuAllocator<char>(control)),
        message(FsvBasisuAllocator<char>(control)),
        stage(FsvBasisuAllocator<char>(control)),
        field(FsvBasisuAllocator<char>(control)),
        control_(control) {}

  FsvBasisuString status;
  FsvBasisuString message;
  int texture_index = -1;
  int image_index = -1;
  FsvBasisuString stage;
  FsvBasisuString field;
  bool has_limit = false;
  uint64_t limit = 0;
  bool has_actual = false;
  uint64_t actual = 0;

  fsv_basisu::FsvDecodeControl* control() const { return control_; }

 private:
  fsv_basisu::FsvDecodeControl* control_ = nullptr;
};

struct FsvBasisuMipLevelLayout {
  uint32_t level = 0;
  uint32_t width = 0;
  uint32_t height = 0;
  uint64_t byte_offset = 0;
  uint64_t byte_length = 0;
  uint64_t uncompressed_byte_length = 0;
  uint64_t pixel_count = 0;
  uint64_t rgba_bytes = 0;
};

struct FsvBasisuImageLayout {
  explicit FsvBasisuImageLayout(
      fsv_basisu::FsvDecodeControl* control = nullptr)
      : levels(FsvBasisuAllocator<FsvBasisuMipLevelLayout>(control)),
        control_(control) {}

  uint32_t width = 0;
  uint32_t height = 0;
  uint64_t pixel_count = 0;
  uint64_t rgba_bytes = 0;
  uint64_t raw_scanline_bytes = 0;
  uint64_t zlib_bytes = 0;
  uint64_t png_bytes = 0;
  uint64_t max_level_uncompressed_bytes = 0;
  FsvBasisuVector<FsvBasisuMipLevelLayout> levels;

  fsv_basisu::FsvDecodeControl* control() const { return control_; }

 private:
  fsv_basisu::FsvDecodeControl* control_ = nullptr;
};

struct FsvBasisuPreflightResult {
  explicit FsvBasisuPreflightResult(
      fsv_basisu::FsvDecodeControl* control = nullptr)
      : layouts(FsvBasisuAllocator<FsvBasisuImageLayout>(control)),
        diagnostics(FsvBasisuAllocator<FsvBasisuDiagnostic>(control)),
        control_(control) {}

  bool ok = false;
  uint64_t total_decoded_bytes = 0;
  uint64_t texture_pixels = 0;
  uint64_t native_output_bytes = 0;
  uint64_t retained_rgba_bytes = 0;
  uint64_t max_level_uncompressed_bytes = 0;
  uint64_t native_working_bytes = 0;
  FsvBasisuVector<FsvBasisuImageLayout> layouts;
  FsvBasisuVector<FsvBasisuDiagnostic> diagnostics;

  fsv_basisu::FsvDecodeControl* control() const { return control_; }

 private:
  fsv_basisu::FsvDecodeControl* control_ = nullptr;
};

using FsvBasisuImageRequests = FsvBasisuVector<FsvBasisuImageRequest>;

FsvBasisuPreflightResult FsvBasisuPreflightRequests(
    const FsvBasisuImageRequests& requests,
    const FsvBasisuDecodeBudgetMetadata& budget,
    const FsvBasisuDecodeBudgetState& state,
    fsv_basisu::FsvDecodeControl* control = nullptr);

#endif  // FSV_BASISU_BUDGET_H_
