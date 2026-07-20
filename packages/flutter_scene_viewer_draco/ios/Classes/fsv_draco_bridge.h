#ifndef FSV_DRACO_BRIDGE_H_
#define FSV_DRACO_BRIDGE_H_

#include <cstdint>
#include <map>
#include <string>
#include <vector>

#include "fsv_draco_budget.h"
#include "fsv_draco_control.h"

struct FsvDracoDecodedPrimitive {
  explicit FsvDracoDecodedPrimitive(
      fsv_draco::FsvDecodeControl* control = nullptr)
      : attributes(
            std::less<>(),
            FsvDracoAllocator<std::pair<const FsvDracoString,
                                        FsvDracoByteVector>>(control)),
        indices(FsvDracoAllocator<uint8_t>(control)),
        control_(control) {}
  FsvDracoDecodedPrimitive(const FsvDracoDecodedPrimitive& other,
                           fsv_draco::FsvDecodeControl* control)
      : FsvDracoDecodedPrimitive(control) {
    mesh_index = other.mesh_index;
    primitive_index = other.primitive_index;
    for (const auto& entry : other.attributes) {
      attributes.emplace(
          FsvDracoString(entry.first.data(), entry.first.size(),
                         FsvDracoAllocator<char>(control)),
          FsvDracoByteVector(entry.second.begin(), entry.second.end(),
                             FsvDracoAllocator<uint8_t>(control)));
    }
    has_indices = other.has_indices;
    indices.assign(other.indices.begin(), other.indices.end());
  }
  FsvDracoDecodedPrimitive(FsvDracoDecodedPrimitive&& other,
                           fsv_draco::FsvDecodeControl* control)
      : FsvDracoDecodedPrimitive(other, control) {
    other.attributes.clear();
    other.indices.clear();
  }
  FsvDracoDecodedPrimitive(FsvDracoDecodedPrimitive&&) noexcept = default;
  FsvDracoDecodedPrimitive& operator=(FsvDracoDecodedPrimitive&& other) {
    if (this != &other) {
      if (control_ == other.control_) {
        mesh_index = other.mesh_index;
        primitive_index = other.primitive_index;
        attributes = std::move(other.attributes);
        has_indices = other.has_indices;
        indices = std::move(other.indices);
      } else {
        FsvDracoDecodedPrimitive replacement(std::move(other), control_);
        mesh_index = replacement.mesh_index;
        primitive_index = replacement.primitive_index;
        attributes.swap(replacement.attributes);
        has_indices = replacement.has_indices;
        indices.swap(replacement.indices);
      }
    }
    return *this;
  }

  int mesh_index = -1;
  int primitive_index = -1;
  FsvDracoMap<FsvDracoString, FsvDracoByteVector> attributes;
  bool has_indices = false;
  FsvDracoByteVector indices;

  fsv_draco::FsvDecodeControl* control() const { return control_; }

 private:
  fsv_draco::FsvDecodeControl* control_ = nullptr;
};

enum class FsvDracoTerminalOutcomeKind {
  kNone,
  kCallerCancelled,
  kDeadline,
  kBudgetExceeded,
  kAllocationFailed,
};

struct FsvDracoTerminalOutcome {
  FsvDracoTerminalOutcomeKind kind = FsvDracoTerminalOutcomeKind::kNone;
  int mesh_index = -1;
  int primitive_index = -1;
};

struct FsvDracoDecodeResult {
  explicit FsvDracoDecodeResult(
      fsv_draco::FsvDecodeControl* control = nullptr)
      : decoded_primitives(
            FsvDracoAllocator<FsvDracoDecodedPrimitive>(control)),
        diagnostics(FsvDracoAllocator<FsvDracoDiagnostic>(control)),
        control_(control) {}
  FsvDracoDecodeResult(const FsvDracoDecodeResult& other,
                       fsv_draco::FsvDecodeControl* control)
      : FsvDracoDecodeResult(control) {
    for (const auto& primitive : other.decoded_primitives) {
      decoded_primitives.emplace_back(primitive, control);
    }
    for (const auto& diagnostic : other.diagnostics) {
      diagnostics.emplace_back(diagnostic, control);
    }
    terminal_outcome = other.terminal_outcome;
  }
  FsvDracoDecodeResult(FsvDracoDecodeResult&& other,
                       fsv_draco::FsvDecodeControl* control)
      : FsvDracoDecodeResult(other, control) {
    other.decoded_primitives.clear();
    other.diagnostics.clear();
    other.terminal_outcome = FsvDracoTerminalOutcome();
  }
  FsvDracoDecodeResult(FsvDracoDecodeResult&&) noexcept = default;
  FsvDracoDecodeResult& operator=(FsvDracoDecodeResult&& other) {
    if (this != &other) {
      if (control_ == other.control_) {
        decoded_primitives = std::move(other.decoded_primitives);
        diagnostics = std::move(other.diagnostics);
        terminal_outcome = other.terminal_outcome;
        other.terminal_outcome = FsvDracoTerminalOutcome();
      } else {
        FsvDracoDecodeResult replacement(std::move(other), control_);
        decoded_primitives.swap(replacement.decoded_primitives);
        diagnostics.swap(replacement.diagnostics);
        terminal_outcome = replacement.terminal_outcome;
      }
    }
    return *this;
  }

  fsv_draco::FsvDecodeControl* control() const { return control_; }

  FsvDracoVector<FsvDracoDecodedPrimitive> decoded_primitives;
  FsvDracoVector<FsvDracoDiagnostic> diagnostics;
  FsvDracoTerminalOutcome terminal_outcome;

 private:
  fsv_draco::FsvDecodeControl* control_ = nullptr;
};

enum class FsvDracoDecodeTestingBoundaryStop {
  kNone,
  kCallerCancelled,
  kDeadline,
};

struct FsvDracoDecodeTestingCounters {
  uint64_t output_vector_allocations = 0;
  uint64_t codec_allocation_attempts = 0;
  FsvDracoDecodeTestingBoundaryStop stop_before_codec_dispatch =
      FsvDracoDecodeTestingBoundaryStop::kNone;
};

void FsvDracoRecordTerminalOutcome(
    FsvDracoDecodeResult* result,
    fsv_draco::FsvDecodeControl* control,
    int mesh_index = -1,
    int primitive_index = -1) noexcept;

bool FsvDracoDecoderLinked();
bool FsvDracoPrimitiveDecodeAvailable();
FsvDracoDecodeResult FsvDracoDecodePrimitives(
    const FsvDracoPrimitiveRequests& requests,
    const FsvDracoDecodeBudgetMetadata& budget,
    const FsvDracoDecodeBudgetState& state,
    FsvDracoDecodeTestingCounters* testing_counters = nullptr,
    fsv_draco::FsvDecodeControl* control = nullptr);

FsvDracoDecodeResult FsvDracoDecodeOwnedPrimitives(
    const FsvDracoPrimitiveRequests& requests,
    const FsvDracoDecodeBudgetMetadata& budget,
    const FsvDracoDecodeBudgetState& state,
    FsvDracoDecodeTestingCounters* testing_counters = nullptr,
    fsv_draco::FsvDecodeControl* control = nullptr);

#endif  // FSV_DRACO_BRIDGE_H_
