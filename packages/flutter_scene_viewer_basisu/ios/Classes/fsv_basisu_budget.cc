#include "fsv_basisu_budget.h"

#include <cstddef>
#include <cstring>
#include <limits>
#include <set>
#include <utility>

namespace {
constexpr uint8_t kKtx2Identifier[] = {0xAB, 0x4B, 0x54, 0x58,
                                        0x20, 0x32, 0x30, 0xBB,
                                        0x0D, 0x0A, 0x1A, 0x0A};

FsvBasisuDiagnostic Diagnostic(const FsvBasisuImageRequest* request,
                               std::string status,
                               std::string field,
                               std::string message) {
  FsvBasisuDiagnostic diagnostic;
  diagnostic.status = std::move(status);
  diagnostic.message = std::move(message);
  diagnostic.stage = "basisuNativePreflight";
  diagnostic.field = std::move(field);
  if (request != nullptr) {
    diagnostic.texture_index = request->texture_index;
    diagnostic.image_index = request->image_index;
  }
  return diagnostic;
}

bool ReadNumber(const FsvBasisuBudgetNumber& number,
                const char* field,
                uint64_t* value,
                FsvBasisuDiagnostic* diagnostic) {
  if (!number.present || !number.is_integer || number.value < 0 ||
      number.value > kFsvBasisuMaxSafeInteger) {
    *diagnostic = Diagnostic(
        nullptr, "invalidMetadata", field,
        "Native BasisU decode metadata must be a non-negative web-safe integer.");
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
                      FsvBasisuDiagnostic* diagnostic) {
  if (current > limit || increment > limit - current) {
    *diagnostic = Diagnostic(
        nullptr, "budgetExceeded", field,
        "Predicted native BasisU output exceeds the configured decode budget.");
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
                    FsvBasisuDiagnostic* diagnostic) {
  const uint64_t max_safe = static_cast<uint64_t>(kFsvBasisuMaxSafeInteger);
  if (right != 0 && left > max_safe / right) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", field,
        "Predicted BasisU allocation exceeds the web-safe integer range.");
    diagnostic->has_limit = true;
    diagnostic->limit = max_safe;
    return false;
  }
  *result = left * right;
  if (*result > static_cast<uint64_t>(std::numeric_limits<size_t>::max())) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", field,
        "Predicted BasisU allocation exceeds the native size_t range.");
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
                FsvBasisuDiagnostic* diagnostic) {
  const uint64_t max_safe = static_cast<uint64_t>(kFsvBasisuMaxSafeInteger);
  if (left > max_safe || right > max_safe - left) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", field,
        "Predicted BasisU allocation exceeds the web-safe integer range.");
    diagnostic->has_limit = true;
    diagnostic->limit = max_safe;
    return false;
  }
  *result = left + right;
  return true;
}

uint32_t ReadLittleEndian32(const std::vector<uint8_t>& bytes, size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

bool ReadLayout(const FsvBasisuImageRequest& request,
                FsvBasisuImageLayout* layout,
                FsvBasisuDiagnostic* diagnostic) {
  // This is bounded dimension/layout/output-envelope preflight only. Full
  // KTX2 container validity remains owned by the pinned transcoder's init().
  if (!request.metadata_valid) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata",
        request.metadata_field.empty() ? "basisuImages"
                                       : request.metadata_field,
        "BasisU native request metadata has an invalid platform-channel type.");
    return false;
  }
  if (request.mime_type != "image/ktx2") {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "mimeType",
        "BasisU native decode requires an image/ktx2 payload.");
    return false;
  }
  if (request.bytes.size() < 80) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2Header",
        "KTX2 payload is too short for the 80-byte KTX2 fixed header.");
    diagnostic->has_limit = true;
    diagnostic->limit = 80;
    diagnostic->has_actual = true;
    diagnostic->actual = request.bytes.size();
    return false;
  }
  if (request.bytes.size() > std::numeric_limits<uint32_t>::max()) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2Bytes",
        "KTX2 payload exceeds the uint32 decoder input range.");
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
        "KTX2 payload has an invalid 12-byte identifier.");
    return false;
  }

  const uint32_t width = ReadLittleEndian32(request.bytes, 20);
  const uint32_t height = ReadLittleEndian32(request.bytes, 24);
  const uint32_t depth = ReadLittleEndian32(request.bytes, 28);
  const uint32_t layer_count = ReadLittleEndian32(request.bytes, 32);
  const uint32_t face_count = ReadLittleEndian32(request.bytes, 36);
  const uint32_t level_count = ReadLittleEndian32(request.bytes, 40);
  const uint64_t effective_level_count = level_count == 0 ? 1 : level_count;
  const uint64_t max_safe =
      static_cast<uint64_t>(kFsvBasisuMaxSafeInteger);
  if (effective_level_count > (max_safe - 80U) / 24U) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2LevelIndex",
        "KTX2 Level Index length exceeds the web-safe integer range.");
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
        "KTX2 payload is truncated before its declared Level Index ends.");
    diagnostic->has_limit = true;
    diagnostic->limit = required_level_index_bytes;
    diagnostic->has_actual = true;
    diagnostic->actual = request.bytes.size();
    return false;
  }
  if (effective_level_count > 1) {
    *diagnostic = Diagnostic(
        &request, "unsupportedKtx2Layout", "ktx2MipLevels",
        "BasisU GLB rewrite cannot preserve authored KTX2 mip pyramids.");
    diagnostic->has_limit = true;
    diagnostic->limit = 1;
    diagnostic->has_actual = true;
    diagnostic->actual = effective_level_count;
    return false;
  }
  if (width == 0 || height == 0 || depth != 0 || layer_count != 0 ||
      face_count != 1) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "ktx2Layout",
        "BasisU native decode only supports non-array, non-cubemap 2D KTX2 level-0 images.");
    return false;
  }

  uint64_t pixel_count = 0;
  uint64_t rgba_bytes = 0;
  uint64_t row_bytes = 0;
  uint64_t scanline_stride = 0;
  uint64_t raw_bytes = 0;
  uint64_t block_overhead = 0;
  uint64_t zlib_bytes = 0;
  uint64_t png_bytes = 0;
  if (!CheckedProduct(width, height, request, "texturePixels", &pixel_count,
                      diagnostic) ||
      pixel_count > std::numeric_limits<uint32_t>::max()) {
    if (diagnostic->field.empty()) {
      *diagnostic = Diagnostic(
          &request, "invalidMetadata", "texturePixels",
          "BasisU RGBA32 transcode pixel count exceeds the uint32 decoder range.");
      diagnostic->has_limit = true;
      diagnostic->limit = std::numeric_limits<uint32_t>::max();
      diagnostic->has_actual = true;
      diagnostic->actual = pixel_count;
    }
    return false;
  }
  if (!CheckedProduct(pixel_count, 4, request, "rgbaBytes", &rgba_bytes,
                      diagnostic) ||
      !CheckedProduct(width, 4, request, "pngRowBytes", &row_bytes,
                      diagnostic) ||
      !CheckedSum(row_bytes, 1, request, "pngScanlineStride",
                  &scanline_stride, diagnostic) ||
      !CheckedProduct(scanline_stride, height, request, "pngRawBytes",
                      &raw_bytes, diagnostic)) {
    return false;
  }
  const uint64_t block_count = raw_bytes / 65535U +
                               (raw_bytes % 65535U == 0 ? 0U : 1U);
  if (!CheckedProduct(block_count, 5, request, "pngDeflateOverhead",
                      &block_overhead, diagnostic) ||
      !CheckedSum(raw_bytes, block_overhead, request, "pngZlibBytes",
                  &zlib_bytes, diagnostic) ||
      !CheckedSum(zlib_bytes, 6, request, "pngZlibBytes", &zlib_bytes,
                  diagnostic) ||
      !CheckedSum(zlib_bytes, 57, request, "pngBytes", &png_bytes,
                  diagnostic)) {
    return false;
  }
  if (zlib_bytes > std::numeric_limits<uint32_t>::max() ||
      png_bytes > std::numeric_limits<uint32_t>::max() ||
      png_bytes > static_cast<uint64_t>(std::numeric_limits<int32_t>::max()) ||
      png_bytes > static_cast<uint64_t>(std::numeric_limits<size_t>::max())) {
    *diagnostic = Diagnostic(
        &request, "invalidMetadata", "pngBytes",
        "Predicted PNG output exceeds native PNG length ranges.");
    diagnostic->has_limit = true;
    diagnostic->limit = std::numeric_limits<int32_t>::max();
    diagnostic->has_actual = true;
    diagnostic->actual = png_bytes;
    return false;
  }

  layout->width = width;
  layout->height = height;
  layout->pixel_count = pixel_count;
  layout->rgba_bytes = rgba_bytes;
  layout->raw_scanline_bytes = raw_bytes;
  layout->zlib_bytes = zlib_bytes;
  layout->png_bytes = png_bytes;
  return true;
}
}  // namespace

bool FsvBasisuUsageRoleFromString(const std::string& value,
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

bool FsvBasisuChannelLayoutFromString(const std::string& value,
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
    const std::vector<FsvBasisuImageRequest>& requests,
    const FsvBasisuDecodeBudgetMetadata& budget,
    const FsvBasisuDecodeBudgetState& state) {
  FsvBasisuPreflightResult result;
  uint64_t max_total_decoded_bytes = 0;
  uint64_t max_texture_pixels = 0;
  uint64_t max_native_output_bytes = 0;
  uint64_t total_decoded_bytes = 0;
  uint64_t texture_pixels = 0;
  uint64_t native_output_bytes = 0;
  FsvBasisuDiagnostic diagnostic;
#define FSV_READ(number, field, target)                     \
  if (!ReadNumber(number, field, &target, &diagnostic)) {   \
    result.diagnostics.push_back(std::move(diagnostic));    \
    return result;                                          \
  }
  FSV_READ(budget.max_total_decoded_bytes, "maxTotalDecodedBytes",
           max_total_decoded_bytes)
  FSV_READ(budget.max_texture_pixels, "maxTexturePixels",
           max_texture_pixels)
  FSV_READ(budget.max_native_output_bytes, "maxNativeOutputBytes",
           max_native_output_bytes)
  FSV_READ(state.total_decoded_bytes, "totalDecodedBytes",
           total_decoded_bytes)
  FSV_READ(state.texture_pixels, "texturePixels", texture_pixels)
  FSV_READ(state.native_output_bytes, "nativeOutputBytes",
           native_output_bytes)
#undef FSV_READ

  uint64_t ignored = 0;
  if (!CheckedBudgetAdd(total_decoded_bytes, 0, max_total_decoded_bytes,
                        "totalDecodedBytes", &ignored, &diagnostic) ||
      !CheckedBudgetAdd(texture_pixels, 0, max_texture_pixels,
                        "texturePixels", &ignored, &diagnostic) ||
      !CheckedBudgetAdd(native_output_bytes, 0, max_native_output_bytes,
                        "nativeOutputBytes", &ignored, &diagnostic)) {
    result.diagnostics.push_back(std::move(diagnostic));
    return result;
  }
  if (native_output_bytes > total_decoded_bytes) {
    result.diagnostics.push_back(Diagnostic(
        nullptr, "invalidMetadata", "nativeOutputBytes",
        "Native output accounting exceeds total decoded-byte accounting."));
    return result;
  }
  if (requests.empty()) {
    result.diagnostics.push_back(Diagnostic(
        nullptr, "invalidMetadata", "basisuImages",
        "Native BasisU decode requires at least one image request."));
    return result;
  }

  std::set<int> image_targets;
  std::vector<FsvBasisuImageLayout> layouts;
  layouts.reserve(requests.size());
  for (const FsvBasisuImageRequest& request : requests) {
    if (!request.metadata_valid) {
      FsvBasisuImageLayout layout;
      if (!ReadLayout(request, &layout, &diagnostic)) {
        result.diagnostics.push_back(std::move(diagnostic));
        return result;
      }
    }
    if (request.image_index < 0 ||
        !image_targets.insert(request.image_index).second) {
      result.diagnostics.push_back(Diagnostic(
          &request, "invalidMetadata", "imageIndex",
          "Native BasisU image targets must be non-negative and unique."));
      return result;
    }
    FsvBasisuImageLayout layout;
    if (!ReadLayout(request, &layout, &diagnostic)) {
      result.diagnostics.push_back(std::move(diagnostic));
      return result;
    }
    if (!CheckedBudgetAdd(texture_pixels, layout.pixel_count,
                          max_texture_pixels, "texturePixels",
                          &texture_pixels, &diagnostic) ||
        !CheckedBudgetAdd(native_output_bytes, layout.png_bytes,
                          max_native_output_bytes, "nativeOutputBytes",
                          &native_output_bytes, &diagnostic) ||
        !CheckedBudgetAdd(total_decoded_bytes, layout.png_bytes,
                          max_total_decoded_bytes, "totalDecodedBytes",
                          &total_decoded_bytes, &diagnostic)) {
      diagnostic.texture_index = request.texture_index;
      diagnostic.image_index = request.image_index;
      result.diagnostics.push_back(std::move(diagnostic));
      return result;
    }
    layouts.push_back(layout);
  }

  result.ok = true;
  result.total_decoded_bytes = total_decoded_bytes;
  result.texture_pixels = texture_pixels;
  result.native_output_bytes = native_output_bytes;
  result.layouts = std::move(layouts);
  return result;
}
