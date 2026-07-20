#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

#include "fsv_basisu_bridge.h"

uint64_t ReadLittleEndian64(const std::vector<uint8_t>& bytes,
                            size_t offset) {
  uint64_t value = 0;
  for (size_t index = 0; index < 8; index += 1) {
    value |= static_cast<uint64_t>(bytes[offset + index]) << (index * 8);
  }
  return value;
}

int main(int argc, char** argv) {
  if (argc != 3) {
    return 64;
  }
  std::ifstream input(argv[1], std::ios::binary);
  std::vector<uint8_t> bytes((std::istreambuf_iterator<char>(input)),
                             std::istreambuf_iterator<char>());
  if (bytes.empty()) {
    return 65;
  }

  FsvBasisuImageRequest request;
  request.texture_index = 0;
  request.image_index = 0;
  request.usage_role = FsvBasisuUsageRole::kColor;
  request.channel_layout = FsvBasisuChannelLayout::kRgba;
  request.mime_type = "image/ktx2";
  request.bytes = bytes;

  FsvBasisuDecodeBudgetMetadata budget;
  budget.max_total_decoded_bytes = FsvBasisuBudgetNumber::Integer(1024);
  budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(256);
  budget.max_native_output_bytes = FsvBasisuBudgetNumber::Integer(1024);
  budget.max_native_working_bytes =
      FsvBasisuBudgetNumber::Integer(1024 + ReadLittleEndian64(bytes, 96));
  FsvBasisuDecodeBudgetState state;
  state.total_decoded_bytes = FsvBasisuBudgetNumber::Integer(0);
  state.texture_pixels = FsvBasisuBudgetNumber::Integer(0);
  state.native_output_bytes = FsvBasisuBudgetNumber::Integer(0);

  const FsvBasisuTranscodeResult result =
      FsvBasisuTranscodeImages({request}, budget, state);
  if (!result.diagnostics.empty()) {
    const FsvBasisuDiagnostic& diagnostic = result.diagnostics.front();
    std::cerr << diagnostic.status << ": " << diagnostic.message << "\n";
    return 2;
  }
  if (result.decoded_images.size() != 1) {
    return 3;
  }
  const FsvBasisuDecodedImage& image = result.decoded_images.front();
  if (image.image_index != 0 || image.content_role != "color" ||
      image.levels.size() != 1 || image.levels[0].level != 0 ||
      image.levels[0].width != 16 || image.levels[0].height != 16 ||
      image.levels[0].rgba_bytes.size() != 1024) {
    return 4;
  }
  const FsvBasisuDecodedMipLevel& level = image.levels.front();

  std::ofstream output(argv[2], std::ios::binary | std::ios::trunc);
  if (!output) {
    return 66;
  }
  output.write(reinterpret_cast<const char*>(level.rgba_bytes.data()),
               static_cast<std::streamsize>(level.rgba_bytes.size()));
  if (!output) {
    return 67;
  }
  std::cout << "rgba=" << level.rgba_bytes.size()
            << " width=" << level.width << " height=" << level.height << "\n";
  return 0;
}
