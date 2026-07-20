#include "fsv_basisu_budget.h"

#include <cstddef>
#include <cstring>
#include <limits>
#include <set>
#include <algorithm>
#include <utility>

namespace {
constexpr uint8_t kKtx2Identifier[] = {0xAB, 0x4B, 0x54, 0x58,
                                        0x20, 0x32, 0x30, 0xBB,
                                        0x0D, 0x0A, 0x1A, 0x0A};
constexpr uint32_t kKtx2SupercompressionNone = 0;
constexpr uint32_t kKtx2SupercompressionBasisLz = 1;
constexpr uint32_t kKtx2SupercompressionZstandard = 2;
constexpr uint64_t kPlatformMessageByteLimit =
    static_cast<uint64_t>(std::numeric_limits<int32_t>::max());

FsvBasisuDiagnostic Diagnostic(const FsvBasisuImageRequest* request,
                               std::string_view status,
                               std::string_view field,
                               std::string_view message,
                               fsv_basisu::FsvDecodeControl* control) {
  FsvBasisuDiagnostic diagnostic(control);
  diagnostic.status.assign(status.data(), status.size());
  diagnostic.message.assign(message.data(), message.size());
  diagnostic.stage = "basisuNativePreflight";
  diagnostic.field.assign(field.data(), field.size());
  if (request != nullptr) {
    diagnostic.texture_index = request->texture_index;
    diagnostic.image_index = request->image_index;
  }
  return diagnostic;
}

bool ReadNumber(const FsvBasisuBudgetNumber& number,
                const char* field,
                uint64_t* value,
                FsvBasisuDiagnostic* diagnostic,
                fsv_basisu::FsvDecodeControl* control) {
  if (!number.present || !number.is_integer || number.value < 0 ||
      number.value > kFsvBasisuMaxSafeInteger) {
    *diagnostic = Diagnostic(
        nullptr, "invalidMetadata", field,
        "Native BasisU decode metadata must be a non-negative web-safe integer.",
        control);
    diagnostic->has_limit = true;
    diagnostic->limit = static_cast<uint64_t>(kFsvBasisuMaxSafeInteger);
    if (number.present && number.is_integer && number.value >= 0) {
      diagnostic->has_actual = true;
      diagnostic->actual = static_cast<uint64_t>(number.value);
    }
    return false;
  }
  *value = static_cast<uint64_t>(number.value);
  return true;
}

bool CheckedBudgetAdd(uint64_t current,
                      uint64_t increment,
                      uint64_t limit,
                      const char* field,
                      uint64_t* result,
                      FsvBasisuDiagnostic* diagnostic,
                      fsv_basisu::FsvDecodeControl* control) {
  if (current > limit || increment > limit - current) {
    *diagnostic = Diagnostic(
        nullptr, "budgetExceeded", field,
        "Predicted native BasisU output exceeds the configured decode budget.",
        control);
    diagnostic->has_limit = true;
    diagnostic->limit = limit;
    diagnostic->has_actual = true;
    diagnostic->actual = current > limit ? current : current + increment;
    return false;
  }
  *result = current + increment;
  return true;
}

bool CheckedProduct(uint64_t left,
                    uint64_t right,
                    const FsvBasisuImageRequest& request,
                    const char* field,
                    uint64_t* result,
                    FsvBasisuDiagnostic* diagnostic,
                    fsv_basisu::FsvDecodeControl* control) {
  const uint64_t max_safe = static_cast<uint64_t>(kFsvBasisuMaxSafeInteger);
  if (right != 0 && left > max_safe / right) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", field,
        "Predicted BasisU allocation exceeds the web-safe integer range.",
        control);
    diagnostic->has_limit = true;
    diagnostic->limit = max_safe;
    return false;
  }
  *result = left * right;
  if (*result > static_cast<uint64_t>(std::numeric_limits<size_t>::max())) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", field,
        "Predicted BasisU allocation exceeds the native size_t range.",
        control);
    diagnostic->has_limit = true;
    diagnostic->limit =
        static_cast<uint64_t>(std::numeric_limits<size_t>::max());
    diagnostic->has_actual = true;
    diagnostic->actual = *result;
    return false;
  }
  return true;
}

bool CheckedSum(uint64_t left,
                uint64_t right,
                const FsvBasisuImageRequest& request,
                const char* field,
                uint64_t* result,
                FsvBasisuDiagnostic* diagnostic,
                fsv_basisu::FsvDecodeControl* control) {
  const uint64_t max_safe = static_cast<uint64_t>(kFsvBasisuMaxSafeInteger);
  if (left > max_safe || right > max_safe - left) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", field,
        "Predicted BasisU allocation exceeds the web-safe integer range.",
        control);
    diagnostic->has_limit = true;
    diagnostic->limit = max_safe;
    return false;
  }
  *result = left + right;
  return true;
}

uint32_t ReadLittleEndian32(const FsvBasisuByteVector& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

uint64_t ReadLittleEndian64(const FsvBasisuByteVector& bytes, size_t offset) {
  return static_cast<uint64_t>(ReadLittleEndian32(bytes, offset)) |
         (static_cast<uint64_t>(ReadLittleEndian32(bytes, offset + 4)) << 32);
}

bool ReadLayout(const FsvBasisuImageRequest& request,
                FsvBasisuImageLayout* layout,
                FsvBasisuDiagnostic* diagnostic,
                fsv_basisu::FsvDecodeControl* control) {
  // This is bounded dimension/layout/output-envelope preflight only. Full
  // KTX2 container validity remains owned by the pinned transcoder's init().
  if (!request.metadata_valid) {
    const std::string_view metadata_field = request.metadata_field.empty()
                                                ? std::string_view("basisuImages")
                                                : std::string_view(
                                                      request.metadata_field.data(),
                                                      request.metadata_field.size());
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", metadata_field,
        "BasisU native request metadata has an invalid platform-channel type.",
        control);
    return false;
  }
  if (request.mime_type != "image/ktx2") {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "mimeType",
        "BasisU native decode requires an image/ktx2 payload.", control);
    return false;
  }
  if (request.bytes.size() < 80) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2Header",
        "KTX2 payload is too short for the 80-byte KTX2 fixed header.",
        control);
    diagnostic->has_limit = true;
    diagnostic->limit = 80;
    diagnostic->has_actual = true;
    diagnostic->actual = request.bytes.size();
    return false;
  }
  if (request.bytes.size() > std::numeric_limits<uint32_t>::max()) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2Bytes",
        "KTX2 payload exceeds the uint32 decoder input range.", control);
    diagnostic->has_limit = true;
    diagnostic->limit = std::numeric_limits<uint32_t>::max();
    diagnostic->has_actual = true;
    diagnostic->actual = request.bytes.size();
    return false;
  }
  if (std::memcmp(request.bytes.data(), kKtx2Identifier,
                  sizeof(kKtx2Identifier)) != 0) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2Identifier",
        "KTX2 payload has an invalid 12-byte identifier.", control);
    return false;
  }

  const uint32_t width = ReadLittleEndian32(request.bytes, 20);
  const uint32_t height = ReadLittleEndian32(request.bytes, 24);
  const uint32_t depth = ReadLittleEndian32(request.bytes, 28);
  const uint32_t layer_count = ReadLittleEndian32(request.bytes, 32);
  const uint32_t face_count = ReadLittleEndian32(request.bytes, 36);
  const uint32_t level_count = ReadLittleEndian32(request.bytes, 40);
  const uint32_t supercompression_scheme =
      ReadLittleEndian32(request.bytes, 44);
  const uint64_t effective_level_count = level_count == 0 ? 1 : level_count;
  const uint64_t max_safe =
      static_cast<uint64_t>(kFsvBasisuMaxSafeInteger);
  if (effective_level_count > (max_safe - 80U) / 24U) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2LevelIndex",
        "KTX2 Level Index length exceeds the web-safe integer range.",
        control);
    diagnostic->has_limit = true;
    diagnostic->limit = (max_safe - 80U) / 24U;
    diagnostic->has_actual = true;
    diagnostic->actual = effective_level_count;
    return false;
  }
  const uint64_t required_level_index_bytes =
      80U + 24U * effective_level_count;
  if (required_level_index_bytes > request.bytes.size()) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2LevelIndex",
        "KTX2 payload is truncated before its declared Level Index ends.",
        control);
    diagnostic->has_limit = true;
    diagnostic->limit = required_level_index_bytes;
    diagnostic->has_actual = true;
    diagnostic->actual = request.bytes.size();
    return false;
  }
  if (width == 0 || height == 0 || depth != 0 || layer_count != 0 ||
      face_count != 1) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2Layout",
        "BasisU native decode only supports non-array, non-cubemap 2D KTX2 images.",
        control);
    return false;
  }
  uint32_t max_dimension = std::max(width, height);
  uint64_t max_level_count = 1;
  while (max_dimension > 1) {
    max_dimension >>= 1;
    max_level_count += 1;
  }
  if (effective_level_count > max_level_count) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2MipLevels",
        "KTX2 levelCount exceeds the canonical 2D mip pyramid.", control);
    diagnostic->has_limit = true;
    diagnostic->limit = max_level_count;
    diagnostic->has_actual = true;
    diagnostic->actual = effective_level_count;
    return false;
  }

  struct ByteRange {
    uint64_t begin;
    uint64_t end;
  };
  FsvBasisuVector<ByteRange> ranges{FsvBasisuAllocator<ByteRange>(control)};
  ranges.reserve(static_cast<size_t>(effective_level_count));
  FsvBasisuVector<FsvBasisuMipLevelLayout> levels{
      FsvBasisuAllocator<FsvBasisuMipLevelLayout>(control)};
  levels.reserve(static_cast<size_t>(effective_level_count));
  uint64_t total_pixels = 0;
  uint64_t total_rgba_bytes = 0;
  uint64_t max_level_uncompressed_bytes = 0;
  for (uint64_t level = 0; level < effective_level_count; level += 1) {
    const size_t entry = 80U + static_cast<size_t>(level) * 24U;
    const uint64_t byte_offset = ReadLittleEndian64(request.bytes, entry);
    const uint64_t byte_length = ReadLittleEndian64(request.bytes, entry + 8U);
    const uint64_t uncompressed_length =
        ReadLittleEndian64(request.bytes, entry + 16U);
    if (byte_offset > max_safe || byte_length == 0 ||
        byte_length > max_safe ||
        byte_offset < required_level_index_bytes ||
        byte_offset > request.bytes.size() ||
        byte_length > request.bytes.size() - byte_offset) {
      *diagnostic = Diagnostic(
          &request, "invalidMetadata", "ktx2LevelIndex",
          "KTX2 Level Index entry is outside the supported payload range.",
          control);
      diagnostic->has_limit = true;
      diagnostic->limit = request.bytes.size();
      diagnostic->has_actual = true;
      diagnostic->actual = byte_offset > request.bytes.size()
                               ? byte_offset
                               : byte_offset + byte_length;
      return false;
    }
    const bool invalid_uncompressed_length =
        uncompressed_length > max_safe ||
        (supercompression_scheme == kKtx2SupercompressionZstandard &&
         uncompressed_length == 0) ||
        (supercompression_scheme == kKtx2SupercompressionBasisLz &&
         uncompressed_length != 0) ||
        (supercompression_scheme == kKtx2SupercompressionNone &&
         uncompressed_length != byte_length);
    if (invalid_uncompressed_length) {
      *diagnostic = Diagnostic(
          &request, "invalidMetadata", "ktx2UncompressedByteLength",
          "KTX2 Level Index uncompressedByteLength is invalid for its supercompression scheme.",
          control);
      diagnostic->has_limit = true;
      diagnostic->limit = max_safe;
      diagnostic->has_actual = true;
      diagnostic->actual = uncompressed_length;
      return false;
    }
    const uint32_t level_width =
        static_cast<uint32_t>(std::max<uint64_t>(1U, width >> level));
    const uint32_t level_height =
        static_cast<uint32_t>(std::max<uint64_t>(1U, height >> level));
    uint64_t level_pixels = 0;
    uint64_t level_rgba_bytes = 0;
    if (!CheckedProduct(level_width, level_height, request, "texturePixels",
                        &level_pixels, diagnostic, control) ||
        level_pixels > std::numeric_limits<uint32_t>::max() ||
        !CheckedProduct(level_pixels, 4U, request, "rgbaBytes",
                        &level_rgba_bytes, diagnostic, control)) {
      return false;
    }
    if (level_rgba_bytes > kPlatformMessageByteLimit) {
      *diagnostic = Diagnostic(
          &request, "invalidMetadata", "platformMessageBytes",
          "Decoded BasisU mip level exceeds the signed 32-bit platform-message byte limit.",
          control);
      diagnostic->has_limit = true;
      diagnostic->limit = kPlatformMessageByteLimit;
      diagnostic->has_actual = true;
      diagnostic->actual = level_rgba_bytes;
      return false;
    }
    if (!CheckedSum(total_pixels, level_pixels, request, "texturePixels",
                    &total_pixels, diagnostic, control) ||
        !CheckedSum(total_rgba_bytes, level_rgba_bytes, request, "rgbaBytes",
                    &total_rgba_bytes, diagnostic, control)) {
      return false;
    }
    if (supercompression_scheme == kKtx2SupercompressionZstandard) {
      max_level_uncompressed_bytes =
          std::max(max_level_uncompressed_bytes, uncompressed_length);
    }
    levels.push_back(FsvBasisuMipLevelLayout{
        static_cast<uint32_t>(level), level_width, level_height, byte_offset,
        byte_length, uncompressed_length, level_pixels, level_rgba_bytes});
    ranges.push_back(ByteRange{byte_offset, byte_offset + byte_length});
  }
  std::sort(ranges.begin(), ranges.end(),
            [](const ByteRange& left, const ByteRange& right) {
              return left.begin < right.begin;
            });
  for (size_t index = 1; index < ranges.size(); index += 1) {
    if (ranges[index - 1].end != ranges[index].begin) {
      *diagnostic = Diagnostic(
          &request, "invalidMetadata", "ktx2LevelIndex",
          "KTX2 authored level payloads overlap or leave an unsupported gap.",
          control);
      return false;
    }
  }
  if (ranges.empty() || ranges.back().end != request.bytes.size()) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2LevelIndex",
        "KTX2 authored levels do not cover the complete payload tail.",
        control);
    return false;
  }
  layout->width = width;
  layout->height = height;
  layout->pixel_count = total_pixels;
  layout->rgba_bytes = total_rgba_bytes;
  layout->max_level_uncompressed_bytes = max_level_uncompressed_bytes;
  layout->levels = std::move(levels);
  return true;
}
}  // namespace

bool FsvBasisuUsageRoleFromString(std::string_view value,
                                  FsvBasisuUsageRole* role) {
  if (role == nullptr) {
    return false;
  }
  if (value == "structuralOnly") {
    *role = FsvBasisuUsageRole::kStructuralOnly;
    return true;
  }
  if (value == "color") {
    *role = FsvBasisuUsageRole::kColor;
    return true;
  }
  if (value == "nonColor") {
    *role = FsvBasisuUsageRole::kNonColor;
    return true;
  }
  if (value == "ambiguous") {
    *role = FsvBasisuUsageRole::kAmbiguous;
    return true;
  }
  return false;
}

bool FsvBasisuChannelLayoutFromString(std::string_view value,
                                      FsvBasisuChannelLayout* layout) {
  if (layout == nullptr) {
    return false;
  }
  if (value == "structuralOnly") {
    *layout = FsvBasisuChannelLayout::kStructuralOnly;
    return true;
  }
  if (value == "r") {
    *layout = FsvBasisuChannelLayout::kR;
    return true;
  }
  if (value == "rg") {
    *layout = FsvBasisuChannelLayout::kRg;
    return true;
  }
  if (value == "rgb") {
    *layout = FsvBasisuChannelLayout::kRgb;
    return true;
  }
  if (value == "rgba") {
    *layout = FsvBasisuChannelLayout::kRgba;
    return true;
  }
  return false;
}

FsvBasisuPreflightResult FsvBasisuPreflightRequests(
    const FsvBasisuImageRequests& requests,
    const FsvBasisuDecodeBudgetMetadata& budget,
    const FsvBasisuDecodeBudgetState& state,
    fsv_basisu::FsvDecodeControl* control) {
  FsvBasisuPreflightResult result(control);
  uint64_t max_total_decoded_bytes = 0;
  uint64_t max_texture_pixels = 0;
  uint64_t max_native_output_bytes = 0;
  uint64_t max_native_working_bytes = 0;
  uint64_t total_decoded_bytes = 0;
  uint64_t texture_pixels = 0;
  uint64_t native_output_bytes = 0;
  FsvBasisuDiagnostic diagnostic(control);
#define FSV_READ(number, field, target)                     \
  if (!ReadNumber(number, field, &target, &diagnostic, control)) { \
    result.diagnostics.push_back(std::move(diagnostic));    \
    return result;                                          \
  }
  FSV_READ(budget.max_total_decoded_bytes, "maxTotalDecodedBytes",
           max_total_decoded_bytes)
  FSV_READ(budget.max_texture_pixels, "maxTexturePixels",
           max_texture_pixels)
  FSV_READ(budget.max_native_output_bytes, "maxNativeOutputBytes",
           max_native_output_bytes)
  if (budget.max_native_working_bytes.present) {
    FSV_READ(budget.max_native_working_bytes, "maxNativeWorkingBytes",
             max_native_working_bytes)
  } else {
    max_native_working_bytes = max_native_output_bytes;
  }
  FSV_READ(state.total_decoded_bytes, "totalDecodedBytes",
           total_decoded_bytes)
  FSV_READ(state.texture_pixels, "texturePixels", texture_pixels)
  FSV_READ(state.native_output_bytes, "nativeOutputBytes",
           native_output_bytes)
#undef FSV_READ

  uint64_t ignored = 0;
  if (!CheckedBudgetAdd(total_decoded_bytes, 0, max_total_decoded_bytes,
                        "totalDecodedBytes", &ignored, &diagnostic, control) ||
      !CheckedBudgetAdd(texture_pixels, 0, max_texture_pixels,
                        "texturePixels", &ignored, &diagnostic, control) ||
      !CheckedBudgetAdd(native_output_bytes, 0, max_native_output_bytes,
                        "nativeOutputBytes", &ignored, &diagnostic, control)) {
    result.diagnostics.push_back(std::move(diagnostic));
    return result;
  }
  if (native_output_bytes > total_decoded_bytes) {
    result.diagnostics.push_back(Diagnostic(
        nullptr, "invalidMetadata", "nativeOutputBytes",
        "Native output accounting exceeds total decoded-byte accounting.",
        control));
    return result;
  }
  if (requests.empty()) {
    result.diagnostics.push_back(Diagnostic(
        nullptr, "invalidMetadata", "basisuImages",
        "Native BasisU decode requires at least one image request.", control));
    return result;
  }

  std::set<int, std::less<>, FsvBasisuAllocator<int>> image_targets{
      std::less<>(), FsvBasisuAllocator<int>(control)};
  FsvBasisuVector<FsvBasisuImageLayout> layouts{
      FsvBasisuAllocator<FsvBasisuImageLayout>(control)};
  layouts.reserve(requests.size());
  uint64_t retained_rgba_bytes = 0;
  uint64_t max_level_uncompressed_bytes = 0;
  uint64_t native_working_bytes = 0;
  for (const FsvBasisuImageRequest& request : requests) {
    if (!request.metadata_valid) {
      FsvBasisuImageLayout layout(control);
      if (!ReadLayout(request, &layout, &diagnostic, control)) {
        result.diagnostics.push_back(std::move(diagnostic));
        return result;
      }
    }
    if (request.image_index < 0 ||
        !image_targets.insert(request.image_index).second) {
      result.diagnostics.push_back(Diagnostic(
          &request, "invalidMetadata", "imageIndex",
          "Native BasisU image targets must be non-negative and unique.",
          control));
      return result;
    }
    FsvBasisuImageLayout layout(control);
    if (!ReadLayout(request, &layout, &diagnostic, control)) {
      result.diagnostics.push_back(std::move(diagnostic));
      return result;
    }
    if (!CheckedBudgetAdd(texture_pixels, layout.pixel_count,
                          max_texture_pixels, "texturePixels",
                          &texture_pixels, &diagnostic, control) ||
        !CheckedBudgetAdd(native_output_bytes, layout.rgba_bytes,
                          max_native_output_bytes, "nativeOutputBytes",
                          &native_output_bytes, &diagnostic, control) ||
        !CheckedBudgetAdd(total_decoded_bytes, layout.rgba_bytes,
                          max_total_decoded_bytes, "totalDecodedBytes",
                          &total_decoded_bytes, &diagnostic, control)) {
      diagnostic.texture_index = request.texture_index;
      diagnostic.image_index = request.image_index;
      result.diagnostics.push_back(std::move(diagnostic));
      return result;
    }
    if (!CheckedSum(retained_rgba_bytes, layout.rgba_bytes, request,
                    "nativeWorkingBytes", &retained_rgba_bytes,
                    &diagnostic, control)) {
      result.diagnostics.push_back(std::move(diagnostic));
      return result;
    }
    max_level_uncompressed_bytes = std::max(
        max_level_uncompressed_bytes, layout.max_level_uncompressed_bytes);
    if (!CheckedSum(retained_rgba_bytes, max_level_uncompressed_bytes,
                    request, "nativeWorkingBytes", &native_working_bytes,
                    &diagnostic, control)) {
      result.diagnostics.push_back(std::move(diagnostic));
      return result;
    }
    if (native_working_bytes > max_native_working_bytes) {
      diagnostic = Diagnostic(
          &request, "budgetExceeded", "nativeWorkingBytes",
          "Predicted aggregate retained BasisU output and level working bytes exceed their limit.",
          control);
      diagnostic.has_limit = true;
      diagnostic.limit = max_native_working_bytes;
      diagnostic.has_actual = true;
      diagnostic.actual = native_working_bytes;
      result.diagnostics.push_back(std::move(diagnostic));
      return result;
    }
    layouts.push_back(std::move(layout));
  }

  result.ok = true;
  result.total_decoded_bytes = total_decoded_bytes;
  result.texture_pixels = texture_pixels;
  result.native_output_bytes = native_output_bytes;
  result.retained_rgba_bytes = retained_rgba_bytes;
  result.max_level_uncompressed_bytes = max_level_uncompressed_bytes;
  result.native_working_bytes = native_working_bytes;
  result.layouts = std::move(layouts);
  return result;
}
