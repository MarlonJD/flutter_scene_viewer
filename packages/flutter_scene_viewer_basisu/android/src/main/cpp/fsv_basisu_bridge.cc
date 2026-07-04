#include "fsv_basisu_bridge.h"

#include <algorithm>
#include <cstddef>
#include <cstring>
#include <exception>
#include <limits>
#include <mutex>
#include <utility>

#if __has_include("basisu_transcoder.h")
#include "basisu_transcoder.h"
#elif __has_include("../../third_party/basis_universal/transcoder/basisu_transcoder.h")
#include "../../third_party/basis_universal/transcoder/basisu_transcoder.h"
#else
#error "basisu_transcoder.h not found"
#endif

namespace {
constexpr uint64_t kMaxDecodedPixels = 8192ULL * 8192ULL;
constexpr uint8_t kPngSignature[] = {0x89, 0x50, 0x4E, 0x47,
                                     0x0D, 0x0A, 0x1A, 0x0A};

std::once_flag g_basisu_init_once;

void EnsureBasisuInitialized() {
  std::call_once(g_basisu_init_once, []() { basist::basisu_transcoder_init(); });
}

void AddDiagnostic(FsvBasisuTranscodeResult& result,
                   const FsvBasisuImageRequest& request, std::string status,
                   std::string message) {
  result.diagnostics.push_back(FsvBasisuDiagnostic{
      std::move(status),
      std::move(message),
      request.texture_index,
      request.image_index,
  });
}

void AppendBigEndian32(std::vector<uint8_t>& bytes, uint32_t value) {
  bytes.push_back(static_cast<uint8_t>((value >> 24) & 0xFF));
  bytes.push_back(static_cast<uint8_t>((value >> 16) & 0xFF));
  bytes.push_back(static_cast<uint8_t>((value >> 8) & 0xFF));
  bytes.push_back(static_cast<uint8_t>(value & 0xFF));
}

uint32_t Crc32(const uint8_t* data, size_t size) {
  uint32_t crc = 0xFFFFFFFFU;
  for (size_t index = 0; index < size; index += 1) {
    crc ^= data[index];
    for (int bit = 0; bit < 8; bit += 1) {
      crc = (crc >> 1) ^ (0xEDB88320U & (0U - (crc & 1U)));
    }
  }
  return crc ^ 0xFFFFFFFFU;
}

uint32_t Adler32(const uint8_t* data, size_t size) {
  constexpr uint32_t kModAdler = 65521U;
  uint32_t a = 1U;
  uint32_t b = 0U;
  for (size_t index = 0; index < size; index += 1) {
    a = (a + data[index]) % kModAdler;
    b = (b + a) % kModAdler;
  }
  return (b << 16) | a;
}

void AppendChunk(std::vector<uint8_t>& png, const char type[4],
                 const std::vector<uint8_t>& data) {
  AppendBigEndian32(png, static_cast<uint32_t>(data.size()));
  const size_t type_offset = png.size();
  png.insert(png.end(), type, type + 4);
  png.insert(png.end(), data.begin(), data.end());
  AppendBigEndian32(png, Crc32(png.data() + type_offset,
                               png.size() - type_offset));
}

std::vector<uint8_t> DeflateStoredBlocks(const std::vector<uint8_t>& data) {
  std::vector<uint8_t> zlib;
  zlib.reserve(data.size() + (data.size() / 65535U + 1U) * 5U + 6U);
  zlib.push_back(0x78);
  zlib.push_back(0x01);

  size_t offset = 0;
  while (offset < data.size() || data.empty()) {
    const size_t remaining = data.size() - offset;
    const uint16_t block_size =
        static_cast<uint16_t>(std::min<size_t>(remaining, 65535U));
    const bool final_block = offset + block_size >= data.size();
    zlib.push_back(final_block ? 0x01 : 0x00);
    zlib.push_back(static_cast<uint8_t>(block_size & 0xFF));
    zlib.push_back(static_cast<uint8_t>((block_size >> 8) & 0xFF));
    const uint16_t nlen = static_cast<uint16_t>(~block_size);
    zlib.push_back(static_cast<uint8_t>(nlen & 0xFF));
    zlib.push_back(static_cast<uint8_t>((nlen >> 8) & 0xFF));
    zlib.insert(zlib.end(), data.begin() + static_cast<ptrdiff_t>(offset),
                data.begin() + static_cast<ptrdiff_t>(offset + block_size));
    offset += block_size;
    if (data.empty()) {
      break;
    }
  }

  AppendBigEndian32(zlib, Adler32(data.data(), data.size()));
  return zlib;
}

std::vector<uint8_t> EncodePngRgba(const uint8_t* rgba, uint32_t width,
                                   uint32_t height) {
  const uint64_t row_stride = static_cast<uint64_t>(width) * 4ULL;
  const uint64_t scanline_stride = row_stride + 1ULL;
  const uint64_t raw_size = scanline_stride * height;
  if (raw_size > static_cast<uint64_t>(std::numeric_limits<size_t>::max())) {
    return {};
  }

  std::vector<uint8_t> raw(static_cast<size_t>(raw_size));
  for (uint32_t y = 0; y < height; y += 1) {
    const size_t destination = static_cast<size_t>(y * scanline_stride);
    const size_t source = static_cast<size_t>(y * row_stride);
    raw[destination] = 0;
    std::memcpy(raw.data() + destination + 1, rgba + source,
                static_cast<size_t>(row_stride));
  }

  std::vector<uint8_t> png;
  png.insert(png.end(), kPngSignature,
             kPngSignature + sizeof(kPngSignature));

  std::vector<uint8_t> ihdr;
  ihdr.reserve(13);
  AppendBigEndian32(ihdr, width);
  AppendBigEndian32(ihdr, height);
  ihdr.push_back(8);
  ihdr.push_back(6);
  ihdr.push_back(0);
  ihdr.push_back(0);
  ihdr.push_back(0);
  AppendChunk(png, "IHDR", ihdr);

  AppendChunk(png, "IDAT", DeflateStoredBlocks(raw));
  AppendChunk(png, "IEND", {});
  return png;
}

bool IsKtx2Request(const FsvBasisuImageRequest& request) {
  return request.mime_type.empty() || request.mime_type == "image/ktx2";
}
}  // namespace

bool FsvBasisuTranscoderLinked() {
  return true;
}

bool FsvBasisuImageTranscodeAvailable() {
  return true;
}

FsvBasisuTranscodeResult FsvBasisuTranscodeImages(
    const std::vector<FsvBasisuImageRequest>& requests) {
  FsvBasisuTranscodeResult result;
  for (const FsvBasisuImageRequest& request : requests) {
    if (!IsKtx2Request(request)) {
      AddDiagnostic(result, request, "unsupportedImageMimeType",
                    "BasisU transcoder only supports image/ktx2 payloads.");
      continue;
    }
    if (request.bytes.empty()) {
      AddDiagnostic(result, request, "decodeFailed",
                    "BasisU transcoder received an empty KTX2 payload.");
      continue;
    }

    try {
      EnsureBasisuInitialized();

      basist::ktx2_transcoder transcoder;
      if (!transcoder.init(request.bytes.data(),
                           static_cast<uint32_t>(request.bytes.size()))) {
        AddDiagnostic(result, request, "decodeFailed",
                      "BasisU transcoder failed to parse the KTX2 payload.");
        continue;
      }
      if (transcoder.get_faces() != 1 || transcoder.get_layers() > 1) {
        AddDiagnostic(result, request, "unsupportedKtx2Layout",
                      "BasisU transcoder only supports 2D KTX2 images for "
                      "glTF texture rewrite.");
        continue;
      }
      if (!transcoder.start_transcoding()) {
        AddDiagnostic(result, request, "decodeFailed",
                      "BasisU transcoder failed to start KTX2 transcoding.");
        continue;
      }

      basist::ktx2_image_level_info level_info;
      if (!transcoder.get_image_level_info(level_info, 0, 0, 0)) {
        AddDiagnostic(result, request, "decodeFailed",
                      "BasisU transcoder failed to read KTX2 level info.");
        continue;
      }
      const uint64_t pixel_count =
          static_cast<uint64_t>(level_info.m_orig_width) *
          static_cast<uint64_t>(level_info.m_orig_height);
      if (pixel_count == 0 || pixel_count > kMaxDecodedPixels ||
          pixel_count >
              static_cast<uint64_t>(std::numeric_limits<uint32_t>::max())) {
        AddDiagnostic(result, request, "unsupportedTextureSize",
                      "BasisU transcoder refused an oversized KTX2 texture.");
        continue;
      }

      std::vector<uint32_t> pixels(static_cast<size_t>(pixel_count));
      if (!transcoder.transcode_image_level(
              0, 0, 0, pixels.data(), static_cast<uint32_t>(pixels.size()),
              basist::transcoder_texture_format::cTFRGBA32)) {
        AddDiagnostic(result, request, "decodeFailed",
                      "BasisU transcoder failed to decode KTX2 level 0.");
        continue;
      }

      std::vector<uint8_t> png = EncodePngRgba(
          reinterpret_cast<const uint8_t*>(pixels.data()),
          level_info.m_orig_width, level_info.m_orig_height);
      if (png.empty()) {
        AddDiagnostic(result, request, "decodeFailed",
                      "BasisU transcoder failed to encode decoded pixels as "
                      "PNG.");
        continue;
      }

      result.decoded_images.push_back(FsvBasisuDecodedImage{
          request.image_index,
          "image/png",
          std::move(png),
      });
    } catch (const std::exception& error) {
      AddDiagnostic(result, request, "decodeFailed",
                    std::string("BasisU transcoder failed: ") + error.what());
    } catch (...) {
      AddDiagnostic(result, request, "decodeFailed",
                    "BasisU transcoder failed with an unknown native error.");
    }
  }
  return result;
}
