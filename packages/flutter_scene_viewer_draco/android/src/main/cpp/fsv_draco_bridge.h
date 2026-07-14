#ifndef FSV_DRACO_BRIDGE_H_
#define FSV_DRACO_BRIDGE_H_

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "fsv_draco_budget.h"

struct FsvDracoDecodedPrimitive {
  int mesh_index = -1;
  int primitive_index = -1;
  std::map<std::string, std::vector<uint8_t>> attributes;
  bool has_indices = false;
  std::vector<uint8_t> indices;
};

struct FsvDracoDecodeResult {
  std::vector<FsvDracoDecodedPrimitive> decoded_primitives;
  std::vector<FsvDracoDiagnostic> diagnostics;
};

struct FsvDracoDecodeTestingCounters {
  uint64_t output_vector_allocations = 0;
};

bool FsvDracoDecoderLinked();
bool FsvDracoPrimitiveDecodeAvailable();
FsvDracoDecodeResult FsvDracoDecodePrimitives(
    const std::vector<FsvDracoPrimitiveRequest>& requests,
    const FsvDracoDecodeBudgetMetadata& budget,
    const FsvDracoDecodeBudgetState& state,
    FsvDracoDecodeTestingCounters* testing_counters = nullptr);

#endif  // FSV_DRACO_BRIDGE_H_
