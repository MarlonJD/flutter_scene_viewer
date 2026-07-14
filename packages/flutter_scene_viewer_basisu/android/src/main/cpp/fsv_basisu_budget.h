#ifndef FSV_BASISU_BUDGET_H_
#define FSV_BASISU_BUDGET_H_

#include <cstdint>
#include <string>
#include <vector>

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

bool FsvBasisuUsageRoleFromString(const std::string& value,
                                  FsvBasisuUsageRole* role);

enum class FsvBasisuChannelLayout {
  kStructuralOnly,
  kR,
  kRg,
  kRgb,
  kRgba,
};

bool FsvBasisuChannelLayoutFromString(const std::string& value,
                                      FsvBasisuChannelLayout* layout);

struct FsvBasisuImageRequest {
  int texture_index = -1;
  int image_index = -1;
  bool metadata_valid = true;
  std::string metadata_field;
  FsvBasisuUsageRole usage_role = FsvBasisuUsageRole::kStructuralOnly;
  FsvBasisuChannelLayout channel_layout =
      FsvBasisuChannelLayout::kStructuralOnly;
  std::string mime_type;
  std::vector<uint8_t> bytes;
};

struct FsvBasisuDiagnostic {
  std::string status;
  std::string message;
  int texture_index = -1;
  int image_index = -1;
  std::string stage;
  std::string field;
  bool has_limit = false;
  uint64_t limit = 0;
  bool has_actual = false;
  uint64_t actual = 0;
};

struct FsvBasisuImageLayout {
  uint32_t width = 0;
  uint32_t height = 0;
  uint64_t pixel_count = 0;
  uint64_t rgba_bytes = 0;
  uint64_t raw_scanline_bytes = 0;
  uint64_t zlib_bytes = 0;
  uint64_t png_bytes = 0;
};

struct FsvBasisuPreflightResult {
  bool ok = false;
  uint64_t total_decoded_bytes = 0;
  uint64_t texture_pixels = 0;
  uint64_t native_output_bytes = 0;
  std::vector<FsvBasisuImageLayout> layouts;
  std::vector<FsvBasisuDiagnostic> diagnostics;
};

FsvBasisuPreflightResult FsvBasisuPreflightRequests(
    const std::vector<FsvBasisuImageRequest>& requests,
    const FsvBasisuDecodeBudgetMetadata& budget,
    const FsvBasisuDecodeBudgetState& state);

#endif  // FSV_BASISU_BUDGET_H_
