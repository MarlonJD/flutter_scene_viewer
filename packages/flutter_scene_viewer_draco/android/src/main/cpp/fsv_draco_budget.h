#ifndef FSV_DRACO_BUDGET_H_
#define FSV_DRACO_BUDGET_H_

#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <vector>

constexpr int64_t kFsvDracoMaxSafeInteger = INT64_C(9007199254740991);

struct FsvDracoBudgetNumber {
  bool present = false;
  bool is_integer = false;
  int64_t value = 0;

  static FsvDracoBudgetNumber Integer(int64_t value) {
    FsvDracoBudgetNumber number;
    number.present = true;
    number.is_integer = true;
    number.value = value;
    return number;
  }

  static FsvDracoBudgetNumber Invalid() {
    FsvDracoBudgetNumber number;
    number.present = true;
    return number;
  }
};

struct FsvDracoDecodeBudgetMetadata {
  FsvDracoBudgetNumber max_total_decoded_bytes;
  FsvDracoBudgetNumber max_accessors;
  FsvDracoBudgetNumber max_vertices;
  FsvDracoBudgetNumber max_indices;
  FsvDracoBudgetNumber max_native_output_bytes;
};

struct FsvDracoDecodeBudgetState {
  FsvDracoBudgetNumber total_decoded_bytes;
  FsvDracoBudgetNumber accessors;
  FsvDracoBudgetNumber vertices;
  FsvDracoBudgetNumber indices;
  FsvDracoBudgetNumber native_output_bytes;
};

struct FsvDracoAccessorSchema {
  int64_t accessor_index = -1;
  FsvDracoBudgetNumber component_type;
  std::string type;
  int64_t count = -1;
  bool normalized = false;
};

struct FsvDracoDecodedMeshMetadata {
  int64_t point_count = -1;
  int64_t face_count = -1;
  std::set<uint32_t> attribute_unique_ids;
};

struct FsvDracoPrimitiveRequest {
  int mesh_index = -1;
  int primitive_index = -1;
  std::vector<uint8_t> compressed_bytes;
  std::map<std::string, int64_t> attributes;
  std::map<std::string, FsvDracoAccessorSchema> attribute_accessors;
  int64_t vertex_accessor_index = -1;
  bool has_indices_accessor = false;
  FsvDracoAccessorSchema indices_accessor;
};

struct FsvDracoDiagnostic {
  std::string status;
  std::string message;
  int mesh_index = -1;
  int primitive_index = -1;
  std::string attribute;
  std::string stage;
  std::string field;
  bool has_limit = false;
  uint64_t limit = 0;
  bool has_actual = false;
  uint64_t actual = 0;
};

struct FsvDracoPreflightResult {
  bool ok = false;
  uint64_t total_decoded_bytes = 0;
  uint64_t native_output_bytes = 0;
  uint64_t accessors = 0;
  uint64_t vertices = 0;
  uint64_t indices = 0;
  std::vector<FsvDracoDiagnostic> diagnostics;
};

struct FsvDracoPostDecodeValidationResult {
  bool ok = false;
  std::vector<FsvDracoDiagnostic> diagnostics;
};

FsvDracoPreflightResult FsvDracoPreflightRequests(
    const std::vector<FsvDracoPrimitiveRequest>& requests,
    const FsvDracoDecodeBudgetMetadata& budget,
    const FsvDracoDecodeBudgetState& state);

FsvDracoPostDecodeValidationResult FsvDracoValidateDecodedSchemas(
    const std::vector<FsvDracoPrimitiveRequest>& requests,
    const std::vector<FsvDracoDecodedMeshMetadata>& decoded_meshes);

#endif  // FSV_DRACO_BUDGET_H_
