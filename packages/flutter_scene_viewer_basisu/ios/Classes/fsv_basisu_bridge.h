#ifndef FSV_BASISU_BRIDGE_H_
#define FSV_BASISU_BRIDGE_H_

#include <string>
#include <vector>

#include "fsv_basisu_budget.h"

struct FsvBasisuDecodedImage {
  int image_index = -1;
  std::string mime_type;
  uint32_t width = 0;
  uint32_t height = 0;
  std::vector<uint8_t> bytes;
};

struct FsvBasisuTranscodeResult {
  std::vector<FsvBasisuDecodedImage> decoded_images;
  std::vector<FsvBasisuDiagnostic> diagnostics;
};

bool FsvBasisuTranscoderLinked();
bool FsvBasisuImageTranscodeAvailable();
FsvBasisuTranscodeResult FsvBasisuTranscodeImages(
    const std::vector<FsvBasisuImageRequest>& requests,
    const FsvBasisuDecodeBudgetMetadata& budget,
    const FsvBasisuDecodeBudgetState& state);

#endif  // FSV_BASISU_BRIDGE_H_
