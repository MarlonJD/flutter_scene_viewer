#ifndef FSV_DRACO_BRIDGE_H_
#define FSV_DRACO_BRIDGE_H_

#include <cstdint>
#include <map>
#include <string>
#include <vector>

struct FsvDracoAccessorSchema {
  int accessor_index = -1;
  int component_type = 0;
  std::string type;
  int count = 0;
  bool normalized = false;
};

struct FsvDracoPrimitiveRequest {
  int mesh_index = -1;
  int primitive_index = -1;
  std::vector<uint8_t> compressed_bytes;
  std::map<std::string, int> attributes;
  std::map<std::string, FsvDracoAccessorSchema> attribute_accessors;
  bool has_indices_accessor = false;
  FsvDracoAccessorSchema indices_accessor;
};

struct FsvDracoDecodedPrimitive {
  int mesh_index = -1;
  int primitive_index = -1;
  std::map<std::string, std::vector<uint8_t>> attributes;
  bool has_indices = false;
  std::vector<uint8_t> indices;
};

struct FsvDracoDiagnostic {
  std::string status;
  std::string message;
  int mesh_index = -1;
  int primitive_index = -1;
  std::string attribute;
};

struct FsvDracoDecodeResult {
  std::vector<FsvDracoDecodedPrimitive> decoded_primitives;
  std::vector<FsvDracoDiagnostic> diagnostics;
};

bool FsvDracoDecoderLinked();
bool FsvDracoPrimitiveDecodeAvailable();
FsvDracoDecodeResult FsvDracoDecodePrimitives(
    const std::vector<FsvDracoPrimitiveRequest>& requests);

#endif  // FSV_DRACO_BRIDGE_H_
