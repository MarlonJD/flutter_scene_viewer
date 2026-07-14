#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <vector>

#include "fsv_basisu_bridge.h"

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
  budget.max_total_decoded_bytes = FsvBasisuBudgetNumber::Integer(1108);
  budget.max_texture_pixels = FsvBasisuBudgetNumber::Integer(256);
  budget.max_native_output_bytes = FsvBasisuBudgetNumber::Integer(1108);
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
  if (image.image_index != 0 || image.mime_type != "image/png" ||
      image.width != 16 || image.height != 16 || image.bytes.size() != 1108) {
    return 4;
  }

  std::ofstream output(argv[2], std::ios::binary | std::ios::trunc);
  if (!output) {
    return 66;
  }
  output.write(reinterpret_cast<const char*>(image.bytes.data()),
               static_cast<std::streamsize>(image.bytes.size()));
  if (!output) {
    return 67;
  }
  std::cout << "png=" << image.bytes.size() << " width=" << image.width
            << " height=" << image.height << "\n";
  return 0;
}
