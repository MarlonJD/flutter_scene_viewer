#ifndef FSV_BASISU_BRIDGE_H_
#define FSV_BASISU_BRIDGE_H_

#include <cstdint>
#include <string>
#include <vector>

struct FsvBasisuImageRequest {
  int texture_index = -1;
  int image_index = -1;
  std::string mime_type;
  std::vector<uint8_t> bytes;
};

struct FsvBasisuDecodedImage {
  int image_index = -1;
  std::string mime_type;
  std::vector<uint8_t> bytes;
};

struct FsvBasisuDiagnostic {
  std::string status;
  std::string message;
  int texture_index = -1;
  int image_index = -1;
};

struct FsvBasisuTranscodeResult {
  std::vector<FsvBasisuDecodedImage> decoded_images;
  std::vector<FsvBasisuDiagnostic> diagnostics;
};

bool FsvBasisuTranscoderLinked();
bool FsvBasisuImageTranscodeAvailable();
FsvBasisuTranscodeResult FsvBasisuTranscodeImages(
    const std::vector<FsvBasisuImageRequest>& requests);

#endif  // FSV_BASISU_BRIDGE_H_
