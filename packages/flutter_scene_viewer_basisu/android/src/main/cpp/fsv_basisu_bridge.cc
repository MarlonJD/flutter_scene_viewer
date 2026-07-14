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
constexpr uint8_t kPngSignature[] = {0x89, 0x50, 0x4E, 0x47,
                                     0x0D, 0x0A, 0x1A, 0x0A};

std::once_flag g_basisu_init_once;

void EnsureBasisuInitialized() {
  std::call_once(g_basisu_init_once, []() { basist::basisu_transcoder_init(); });
}

void AddDiagnostic(FsvBasisuTranscodeResult& result,
                   const FsvBasisuImageRequest& request, std::string status,
                   std::string message, std::string stage,
                   std::string field) {
  result.decoded_images.clear();
  result.diagnostics.clear();
  FsvBasisuDiagnostic diagnostic;
  diagnostic.status = std::move(status);
  diagnostic.message = std::move(message);
  diagnostic.texture_index = request.texture_index;
  diagnostic.image_index = request.image_index;
  diagnostic.stage = std::move(stage);
  diagnostic.field = std::move(field);
  result.diagnostics.push_back(std::move(diagnostic));
}

uint16_t ReadLittleEndian16(const std::vector<uint8_t>& bytes,
                            size_t offset) {
  return static_cast<uint16_t>(bytes[offset]) |
         static_cast<uint16_t>(bytes[offset + 1] << 8);
}

uint32_t ReadLittleEndian32(const std::vector<uint8_t>& bytes,
                            size_t offset) {
  return static_cast<uint32_t>(bytes[offset]) |
         (static_cast<uint32_t>(bytes[offset + 1]) << 8) |
         (static_cast<uint32_t>(bytes[offset + 2]) << 16) |
         (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

bool HasByteRange(size_t byte_length, uint64_t offset, uint64_t length) {
  return offset <= byte_length && length <= byte_length - offset;
}

bool RejectMalformedProfileContainer(FsvBasisuTranscodeResult& result,
                                     const FsvBasisuImageRequest& request,
                                     const char* field,
                                     const char* message) {
  AddDiagnostic(result, request, "invalidMetadata", message,
                "basisuNativePreflight", field);
  return false;
}

bool RejectUnsupportedProfile(FsvBasisuTranscodeResult& result,
                              const FsvBasisuImageRequest& request,
                              const char* field, const char* message) {
  AddDiagnostic(result, request, "unsupportedKtx2Profile", message,
                "basisuProfilePreflight", field);
  return false;
}

bool RejectUnsupportedUsage(FsvBasisuTranscodeResult& result,
                            const FsvBasisuImageRequest& request,
                            const char* message) {
  AddDiagnostic(result, request, "unsupportedKtx2Usage", message,
                "basisuUsagePreflight", "basisuUsageRole");
  return false;
}

bool BytesEqual(const std::vector<uint8_t>& bytes, size_t offset,
                size_t length, const uint8_t* expected,
                size_t expected_length) {
  return length == expected_length &&
         std::memcmp(bytes.data() + offset, expected, expected_length) == 0;
}

bool IsValidUtf8(const std::vector<uint8_t>& bytes, size_t offset,
                 size_t length) {
  size_t index = 0;
  while (index < length) {
    const uint8_t leading = bytes[offset + index];
    if (leading <= 0x7FU) {
      index += 1;
      continue;
    }

    size_t continuation_count = 0;
    uint8_t second_min = 0x80U;
    uint8_t second_max = 0xBFU;
    if (leading >= 0xC2U && leading <= 0xDFU) {
      continuation_count = 1;
    } else if (leading == 0xE0U) {
      continuation_count = 2;
      second_min = 0xA0U;
    } else if (leading >= 0xE1U && leading <= 0xECU) {
      continuation_count = 2;
    } else if (leading == 0xEDU) {
      continuation_count = 2;
      second_max = 0x9FU;
    } else if (leading >= 0xEEU && leading <= 0xEFU) {
      continuation_count = 2;
    } else if (leading == 0xF0U) {
      continuation_count = 3;
      second_min = 0x90U;
    } else if (leading >= 0xF1U && leading <= 0xF3U) {
      continuation_count = 3;
    } else if (leading == 0xF4U) {
      continuation_count = 3;
      second_max = 0x8FU;
    } else {
      return false;
    }
    if (continuation_count > length - index - 1U) {
      return false;
    }
    const uint8_t second = bytes[offset + index + 1U];
    if (second < second_min || second > second_max) {
      return false;
    }
    for (size_t continuation = 2; continuation <= continuation_count;
         continuation += 1) {
      const uint8_t value = bytes[offset + index + continuation];
      if (value < 0x80U || value > 0xBFU) {
        return false;
      }
    }
    index += continuation_count + 1U;
  }
  return true;
}

int CompareByteSlices(const std::vector<uint8_t>& bytes, size_t left_offset,
                      size_t left_length, size_t right_offset,
                      size_t right_length) {
  const size_t shared_length = std::min(left_length, right_length);
  for (size_t index = 0; index < shared_length; index += 1) {
    if (bytes[left_offset + index] < bytes[right_offset + index]) {
      return -1;
    }
    if (bytes[left_offset + index] > bytes[right_offset + index]) {
      return 1;
    }
  }
  if (left_length < right_length) {
    return -1;
  }
  if (left_length > right_length) {
    return 1;
  }
  return 0;
}

bool ValidateKhrTextureBasisuProfile(
    const FsvBasisuImageRequest& request,
    FsvBasisuTranscodeResult& result) {
  // The bounded dimension/layout preflight has already established an
  // 80-byte header and one complete Level Index entry. Validate every raw
  // DFD/KVD range before interpreting values so malformed input keeps the
  // invalidMetadata precedence it had before profile policy is applied.
  const std::vector<uint8_t>& bytes = request.bytes;
  const uint32_t dfd_offset = ReadLittleEndian32(bytes, 48);
  const uint32_t dfd_length = ReadLittleEndian32(bytes, 52);
  constexpr uint64_t kSingleLevelIndexEnd = 104;
  if (dfd_offset < kSingleLevelIndexEnd || (dfd_offset & 3U) != 0 ||
      dfd_length < 44 ||
      !HasByteRange(bytes.size(), dfd_offset, dfd_length)) {
    return RejectMalformedProfileContainer(
        result, request, "ktx2Dfd",
        "KTX2 Data Format Descriptor range is malformed.");
  }

  const uint32_t dfd_total_size = ReadLittleEndian32(bytes, dfd_offset);
  const uint16_t dfd_vendor_id = ReadLittleEndian16(bytes, dfd_offset + 4);
  const uint16_t dfd_descriptor_type =
      ReadLittleEndian16(bytes, dfd_offset + 6);
  const uint16_t dfd_version = ReadLittleEndian16(bytes, dfd_offset + 8);
  const uint16_t dfd_descriptor_size =
      ReadLittleEndian16(bytes, dfd_offset + 10);
  if (dfd_total_size != dfd_length || dfd_vendor_id != 0 ||
      dfd_descriptor_type != 0 || dfd_version != 2 ||
      dfd_descriptor_size < 40 ||
      (dfd_descriptor_size - 24U) % 16U != 0 ||
      static_cast<uint32_t>(dfd_descriptor_size) + 4U != dfd_length) {
    return RejectMalformedProfileContainer(
        result, request, "ktx2Dfd",
        "KTX2 Data Format Descriptor structure is malformed.");
  }
  const uint32_t sample_count = (dfd_descriptor_size - 24U) / 16U;

  const uint32_t kvd_offset = ReadLittleEndian32(bytes, 56);
  const uint32_t kvd_length = ReadLittleEndian32(bytes, 60);
  bool swizzle_present = false;
  bool swizzle_allowed = true;
  bool orientation_present = false;
  bool orientation_allowed = true;
  if (kvd_length == 0) {
    if (kvd_offset != 0) {
      return RejectMalformedProfileContainer(
          result, request, "ktx2KeyValueData",
          "KTX2 Key/Value Data offset is nonzero for an empty section.");
    }
  } else {
    const uint64_t dfd_end =
        static_cast<uint64_t>(dfd_offset) + dfd_length;
    if ((kvd_offset & 3U) != 0 || kvd_offset != dfd_end ||
        !HasByteRange(bytes.size(), kvd_offset, kvd_length)) {
      return RejectMalformedProfileContainer(
          result, request, "ktx2KeyValueData",
          "KTX2 Key/Value Data range is malformed.");
    }

    constexpr uint8_t kSwizzleKey[] = "KTXswizzle";
    constexpr uint8_t kOrientationKey[] = "KTXorientation";
    constexpr uint8_t kAllowedSwizzle[] = {'r', 'g', 'b', 'a', 0};
    constexpr uint8_t kAllowedOrientation[] = {'r', 'd', 0};
    const uint64_t kvd_end =
        static_cast<uint64_t>(kvd_offset) + kvd_length;
    uint64_t cursor = kvd_offset;
    bool has_previous_key = false;
    size_t previous_key_offset = 0;
    size_t previous_key_length = 0;
    while (cursor < kvd_end) {
      if (!HasByteRange(bytes.size(), cursor, 4) || cursor + 4 > kvd_end) {
        return RejectMalformedProfileContainer(
            result, request, "ktx2KeyValueData",
            "KTX2 Key/Value Data entry header is truncated.");
      }
      const uint32_t entry_length =
          ReadLittleEndian32(bytes, static_cast<size_t>(cursor));
      const uint64_t payload_offset = cursor + 4U;
      if (entry_length < 2 || payload_offset > kvd_end ||
          entry_length > kvd_end - payload_offset ||
          !HasByteRange(bytes.size(), payload_offset, entry_length)) {
        return RejectMalformedProfileContainer(
            result, request, "ktx2KeyValueData",
            "KTX2 Key/Value Data entry range is malformed.");
      }

      size_t key_length = 0;
      while (key_length < entry_length &&
             bytes[static_cast<size_t>(payload_offset) + key_length] != 0) {
        key_length += 1;
      }
      if (key_length == 0 || key_length == entry_length) {
        return RejectMalformedProfileContainer(
            result, request, "ktx2KeyValueData",
            "KTX2 Key/Value Data entry has an invalid key terminator.");
      }
      const size_t value_offset =
          static_cast<size_t>(payload_offset) + key_length + 1U;
      const size_t value_length = entry_length - key_length - 1U;
      const size_t key_offset = static_cast<size_t>(payload_offset);
      if (!IsValidUtf8(bytes, key_offset, key_length)) {
        return RejectMalformedProfileContainer(
            result, request, "ktx2KeyValueData",
            "KTX2 Key/Value Data key is not valid UTF-8.");
      }
      if (key_length >= 3 && bytes[key_offset] == 0xEFU &&
          bytes[key_offset + 1U] == 0xBBU &&
          bytes[key_offset + 2U] == 0xBFU) {
        return RejectMalformedProfileContainer(
            result, request, "ktx2KeyValueData",
            "KTX2 Key/Value Data key must not begin with a UTF-8 BOM.");
      }
      // UTF-8 preserves Unicode code-point order under unsigned bytewise
      // comparison, so strict slice order is sufficient after validation.
      if (has_previous_key &&
          CompareByteSlices(bytes, previous_key_offset, previous_key_length,
                            key_offset, key_length) >= 0) {
        return RejectMalformedProfileContainer(
            result, request, "ktx2KeyValueData",
            "KTX2 Key/Value Data keys are duplicated or not strictly ordered.");
      }
      has_previous_key = true;
      previous_key_offset = key_offset;
      previous_key_length = key_length;
      if (BytesEqual(bytes, key_offset, key_length, kSwizzleKey,
                     sizeof(kSwizzleKey) - 1U)) {
        if (swizzle_present) {
          return RejectMalformedProfileContainer(
              result, request, "ktx2KeyValueData",
              "KTX2 Key/Value Data repeats KTXswizzle.");
        }
        swizzle_present = true;
        swizzle_allowed = BytesEqual(
            bytes, value_offset, value_length, kAllowedSwizzle,
            sizeof(kAllowedSwizzle));
      } else if (BytesEqual(bytes, key_offset, key_length, kOrientationKey,
                            sizeof(kOrientationKey) - 1U)) {
        if (orientation_present) {
          return RejectMalformedProfileContainer(
              result, request, "ktx2KeyValueData",
              "KTX2 Key/Value Data repeats KTXorientation.");
        }
        orientation_present = true;
        orientation_allowed = BytesEqual(
            bytes, value_offset, value_length, kAllowedOrientation,
            sizeof(kAllowedOrientation));
      }

      const uint64_t padding = (4U - (entry_length & 3U)) & 3U;
      const uint64_t next = payload_offset + entry_length + padding;
      if (next > kvd_end) {
        return RejectMalformedProfileContainer(
            result, request, "ktx2KeyValueData",
            "KTX2 Key/Value Data entry padding is truncated.");
      }
      for (uint64_t padding_offset = payload_offset + entry_length;
           padding_offset < next; padding_offset += 1) {
        if (bytes[static_cast<size_t>(padding_offset)] != 0) {
          return RejectMalformedProfileContainer(
              result, request, "ktx2KeyValueData",
              "KTX2 Key/Value Data valuePadding contains a nonzero byte.");
        }
      }
      cursor = next;
    }
    if (cursor != kvd_end) {
      return RejectMalformedProfileContainer(
          result, request, "ktx2KeyValueData",
          "KTX2 Key/Value Data length does not end on an entry boundary.");
    }
  }

  const uint32_t dfd_bits = ReadLittleEndian32(bytes, dfd_offset + 12);
  const uint32_t color_model = dfd_bits & 0xFFU;
  const uint32_t color_primaries = (dfd_bits >> 8) & 0xFFU;
  const uint32_t transfer_function = (dfd_bits >> 16) & 0xFFU;
  const uint32_t dfd_flags = (dfd_bits >> 24) & 0xFFU;
  const bool is_etc1s = color_model == basist::KTX2_KDF_DF_MODEL_ETC1S;
  const bool is_uastc =
      color_model == basist::KTX2_KDF_DF_MODEL_UASTC_LDR_4X4;
  if (!is_etc1s && !is_uastc) {
    return RejectUnsupportedProfile(
        result, request, "ktx2DfdColorModel",
        "KHR_texture_basisu requires an ETC1S or UASTC LDR 4x4 color model.");
  }

  const uint32_t supercompression = ReadLittleEndian32(bytes, 44);
  if ((is_etc1s && supercompression != basist::KTX2_SS_BASISLZ) ||
      (is_uastc && supercompression != basist::KTX2_SS_NONE &&
       supercompression != basist::KTX2_SS_ZSTANDARD)) {
    return RejectUnsupportedProfile(
        result, request, "ktx2SupercompressionScheme",
        "KTX2 supercompression is not allowed for the selected BasisU color model.");
  }

  const uint32_t width = ReadLittleEndian32(bytes, 20);
  const uint32_t height = ReadLittleEndian32(bytes, 24);
  if ((width & 3U) != 0 || (height & 3U) != 0) {
    return RejectUnsupportedProfile(
        result, request, "ktx2Dimensions",
        "KHR_texture_basisu requires width and height to be multiples of four.");
  }

  const uint32_t vk_format = ReadLittleEndian32(bytes, 12);
  const uint32_t type_size = ReadLittleEndian32(bytes, 16);
  if (vk_format != basist::KTX2_VK_FORMAT_UNDEFINED || type_size != 1) {
    return RejectUnsupportedProfile(
        result, request, "ktx2HeaderFormat",
        "KHR_texture_basisu requires vkFormat undefined and typeSize one.");
  }

  const uint32_t channel0 = bytes[dfd_offset + 31U] & 0x0FU;
  bool channels_allowed = false;
  bool channels_require_linear_transfer = false;
  if (is_etc1s) {
    if (sample_count == 1) {
      channels_allowed =
          channel0 == basist::KTX2_DF_CHANNEL_ETC1S_RGB ||
          channel0 == basist::KTX2_DF_CHANNEL_ETC1S_RRR;
      channels_require_linear_transfer =
          channel0 == basist::KTX2_DF_CHANNEL_ETC1S_RRR;
    } else if (sample_count == 2) {
      const uint32_t channel1 = bytes[dfd_offset + 47U] & 0x0FU;
      channels_allowed =
          (channel0 == basist::KTX2_DF_CHANNEL_ETC1S_RGB &&
           channel1 == basist::KTX2_DF_CHANNEL_ETC1S_AAA) ||
          (channel0 == basist::KTX2_DF_CHANNEL_ETC1S_RRR &&
           channel1 == basist::KTX2_DF_CHANNEL_ETC1S_GGG);
      channels_require_linear_transfer =
          channel0 == basist::KTX2_DF_CHANNEL_ETC1S_RRR &&
          channel1 == basist::KTX2_DF_CHANNEL_ETC1S_GGG;
    }
  } else if (sample_count == 1) {
    // The pinned API assigns both UASTC DATA and RGB numeric channel ID 0.
    // ID 0 is accepted only as the spec's RGB shape; it is not evidence that
    // a source-layout RG fixture used the required UASTC_RG ID 6.
    channels_allowed =
        channel0 == basist::KTX2_DF_CHANNEL_UASTC_RGB ||
        channel0 == basist::KTX2_DF_CHANNEL_UASTC_RGBA ||
        channel0 == basist::KTX2_DF_CHANNEL_UASTC_RRR ||
        channel0 == basist::KTX2_DF_CHANNEL_UASTC_RG;
    channels_require_linear_transfer =
        channel0 == basist::KTX2_DF_CHANNEL_UASTC_RRR ||
        channel0 == basist::KTX2_DF_CHANNEL_UASTC_RG;
  }
  if (!channels_allowed) {
    return RejectUnsupportedProfile(
        result, request, "ktx2DfdChannels",
        "KTX2 DFD channels are not allowed by KHR_texture_basisu.");
  }

  const bool srgb_color =
      color_primaries == basist::KTX2_DF_PRIMARIES_BT709 &&
      transfer_function == basist::KTX2_KHR_DF_TRANSFER_SRGB;
  const bool linear_color =
      color_primaries == basist::KTX2_DF_PRIMARIES_UNSPECIFIED &&
      transfer_function == basist::KTX2_KHR_DF_TRANSFER_LINEAR;
  if (!linear_color && (!srgb_color || channels_require_linear_transfer)) {
    return RejectUnsupportedProfile(
        result, request, "ktx2DfdColorSpace",
        "KTX2 DFD color primaries and transfer function are not an allowed KHR_texture_basisu pair.");
  }
  if (swizzle_present && !swizzle_allowed) {
    return RejectUnsupportedProfile(
        result, request, "ktx2KTXswizzle",
        "KHR_texture_basisu only allows KTXswizzle to be omitted or rgba.");
  }
  if (orientation_present && !orientation_allowed) {
    return RejectUnsupportedProfile(
        result, request, "ktx2KTXorientation",
        "KHR_texture_basisu only allows KTXorientation to be omitted or rd.");
  }
  constexpr uint32_t kDfdAlphaPremultiplied = 1U;
  if ((dfd_flags & kDfdAlphaPremultiplied) != 0) {
    return RejectUnsupportedProfile(
        result, request, "ktx2PremultipliedAlpha",
        "Premultiplied alpha is not allowed by the selected glTF material profile.");
  }
  return true;
}

bool ValidateKhrTextureBasisuChannelLayout(
    const FsvBasisuImageRequest& request,
    FsvBasisuTranscodeResult& result) {
  if (request.channel_layout == FsvBasisuChannelLayout::kStructuralOnly) {
    return true;
  }

  const uint32_t dfd_offset = ReadLittleEndian32(request.bytes, 48);
  const uint32_t dfd_length = ReadLittleEndian32(request.bytes, 52);
  const uint32_t sample_count = (dfd_length - 24U) / 16U;
  const uint32_t dfd_bits =
      ReadLittleEndian32(request.bytes, dfd_offset + 12U);
  const uint32_t color_model = dfd_bits & 0xFFU;
  const uint32_t channel0 = request.bytes[dfd_offset + 31U] & 0x0FU;
  FsvBasisuChannelLayout actual_layout =
      FsvBasisuChannelLayout::kStructuralOnly;
  if (color_model == basist::KTX2_KDF_DF_MODEL_ETC1S) {
    if (sample_count == 1U) {
      actual_layout = channel0 == basist::KTX2_DF_CHANNEL_ETC1S_RRR
                          ? FsvBasisuChannelLayout::kR
                          : FsvBasisuChannelLayout::kRgb;
    } else {
      actual_layout = channel0 == basist::KTX2_DF_CHANNEL_ETC1S_RRR
                          ? FsvBasisuChannelLayout::kRg
                          : FsvBasisuChannelLayout::kRgba;
    }
  } else if (channel0 == basist::KTX2_DF_CHANNEL_UASTC_RGBA) {
    actual_layout = FsvBasisuChannelLayout::kRgba;
  } else if (channel0 == basist::KTX2_DF_CHANNEL_UASTC_RRR) {
    actual_layout = FsvBasisuChannelLayout::kR;
  } else if (channel0 == basist::KTX2_DF_CHANNEL_UASTC_RG) {
    actual_layout = FsvBasisuChannelLayout::kRg;
  } else {
    // The pinned API assigns UASTC DATA and RGB the same numeric ID. The
    // selected profile treats that ID as RGB but does not claim DATA-shaped
    // source-layout evidence.
    actual_layout = FsvBasisuChannelLayout::kRgb;
  }

  if (request.channel_layout != actual_layout) {
    return RejectUnsupportedProfile(
        result, request, "ktx2DfdChannels",
        "KTX2 DFD channel category does not match the sampled glTF material channels.");
  }
  return true;
}

bool ValidateKhrTextureBasisuUsage(
    const FsvBasisuImageRequest& request,
    FsvBasisuTranscodeResult& result) {
  if (request.usage_role == FsvBasisuUsageRole::kAmbiguous) {
    return RejectUnsupportedUsage(
        result, request,
        "A BasisU image shared by color and non-color material slots has an ambiguous usage role.");
  }
  if (request.usage_role == FsvBasisuUsageRole::kStructuralOnly) {
    return true;
  }

  const uint32_t dfd_offset = ReadLittleEndian32(request.bytes, 48);
  const uint32_t dfd_bits =
      ReadLittleEndian32(request.bytes, dfd_offset + 12U);
  const uint32_t color_primaries = (dfd_bits >> 8) & 0xFFU;
  const uint32_t transfer_function = (dfd_bits >> 16) & 0xFFU;
  const bool srgb_color =
      color_primaries == basist::KTX2_DF_PRIMARIES_BT709 &&
      transfer_function == basist::KTX2_KHR_DF_TRANSFER_SRGB;
  const bool linear_color =
      color_primaries == basist::KTX2_DF_PRIMARIES_UNSPECIFIED &&
      transfer_function == basist::KTX2_KHR_DF_TRANSFER_LINEAR;
  const bool usage_matches =
      (request.usage_role == FsvBasisuUsageRole::kColor && srgb_color) ||
      (request.usage_role == FsvBasisuUsageRole::kNonColor && linear_color);
  if (!usage_matches) {
    return RejectUnsupportedProfile(
        result, request, "ktx2DfdColorSpace",
        "KTX2 DFD color metadata does not match the glTF material texture usage role.");
  }
  return true;
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

}  // namespace

bool FsvBasisuTranscoderLinked() {
  return true;
}

bool FsvBasisuImageTranscodeAvailable() {
  return true;
}

FsvBasisuTranscodeResult FsvBasisuTranscodeImages(
    const std::vector<FsvBasisuImageRequest>& requests,
    const FsvBasisuDecodeBudgetMetadata& budget,
    const FsvBasisuDecodeBudgetState& state) {
  FsvBasisuTranscodeResult result;
  FsvBasisuPreflightResult preflight =
      FsvBasisuPreflightRequests(requests, budget, state);
  if (!preflight.ok) {
    result.diagnostics = std::move(preflight.diagnostics);
    return result;
  }
  for (const FsvBasisuImageRequest& request : requests) {
    if (!ValidateKhrTextureBasisuProfile(request, result)) {
      return result;
    }
    if (!ValidateKhrTextureBasisuChannelLayout(request, result)) {
      return result;
    }
    if (!ValidateKhrTextureBasisuUsage(request, result)) {
      return result;
    }
  }
  result.decoded_images.reserve(requests.size());
  for (size_t request_index = 0; request_index < requests.size();
       request_index += 1) {
    const FsvBasisuImageRequest& request = requests[request_index];
    const FsvBasisuImageLayout& layout = preflight.layouts[request_index];

    try {
      EnsureBasisuInitialized();

      basist::ktx2_transcoder transcoder;
      if (!transcoder.init(request.bytes.data(),
                           static_cast<uint32_t>(request.bytes.size()))) {
        AddDiagnostic(result, request, "decodeFailed",
                      "BasisU transcoder failed to parse the KTX2 payload.",
                      "basisuNativeDecode", "ktx2Payload");
        return result;
      }
      if (transcoder.get_faces() != 1 || transcoder.get_layers() > 1) {
        AddDiagnostic(result, request, "unsupportedKtx2Layout",
                      "BasisU transcoder only supports 2D KTX2 images for "
                      "glTF texture rewrite.",
                      "basisuDecodedSchema", "ktx2Layout");
        return result;
      }
      if (!transcoder.start_transcoding()) {
        AddDiagnostic(result, request, "decodeFailed",
                      "BasisU transcoder failed to start KTX2 transcoding.",
                      "basisuNativeDecode", "startTranscoding");
        return result;
      }

      basist::ktx2_image_level_info level_info;
      if (!transcoder.get_image_level_info(level_info, 0, 0, 0)) {
        AddDiagnostic(result, request, "decodeFailed",
                      "BasisU transcoder failed to read KTX2 level info.",
                      "basisuDecodedSchema", "levelInfo");
        return result;
      }
      if (level_info.m_orig_width != layout.width ||
          level_info.m_orig_height != layout.height) {
        AddDiagnostic(
            result, request, "malformedOutput",
            "BasisU level-0 dimensions do not match the trusted KTX2 header.",
            "basisuDecodedSchema", "level0Dimensions");
        return result;
      }

      std::vector<uint32_t> pixels(
          static_cast<size_t>(layout.pixel_count));
      if (!transcoder.transcode_image_level(
              0, 0, 0, pixels.data(), static_cast<uint32_t>(pixels.size()),
              basist::transcoder_texture_format::cTFRGBA32)) {
        AddDiagnostic(result, request, "decodeFailed",
                      "BasisU transcoder failed to decode KTX2 level 0.",
                      "basisuNativeDecode", "level0Pixels");
        return result;
      }

      std::vector<uint8_t> png = EncodePngRgba(
          reinterpret_cast<const uint8_t*>(pixels.data()),
          level_info.m_orig_width, level_info.m_orig_height);
      if (png.size() != layout.png_bytes) {
        AddDiagnostic(
            result, request, "malformedOutput",
            "BasisU encoded PNG length does not match the preflight prediction.",
            "basisuDecodedSchema", "pngBytes");
        return result;
      }

      result.decoded_images.push_back(FsvBasisuDecodedImage{
          request.image_index,
          "image/png",
          layout.width,
          layout.height,
          std::move(png),
      });
    } catch (const std::exception& error) {
      AddDiagnostic(result, request, "decodeFailed",
                    std::string("BasisU transcoder failed: ") + error.what(),
                    "basisuNativeDecode", "nativeException");
      return result;
    } catch (...) {
      AddDiagnostic(result, request, "decodeFailed",
                    "BasisU transcoder failed with an unknown native error.",
                    "basisuNativeDecode", "nativeException");
      return result;
    }
  }
  return result;
}
