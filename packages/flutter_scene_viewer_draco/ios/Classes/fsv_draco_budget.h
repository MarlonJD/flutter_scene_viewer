#ifndef FSV_DRACO_BUDGET_H_
#define FSV_DRACO_BUDGET_H_

#include <cstdint>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "fsv_draco_owned.h"

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
  explicit FsvDracoAccessorSchema(
      fsv_draco::FsvDecodeControl* control = nullptr)
      : type(FsvDracoAllocator<char>(control)), control_(control) {}
  FsvDracoAccessorSchema(const FsvDracoAccessorSchema&) = delete;
  FsvDracoAccessorSchema(const FsvDracoAccessorSchema& other,
                         fsv_draco::FsvDecodeControl* control)
      : accessor_index(other.accessor_index),
        component_type(other.component_type),
        type(other.type.data(), other.type.size(),
             FsvDracoAllocator<char>(control)),
        count(other.count),
        normalized(other.normalized),
        control_(control) {}
  FsvDracoAccessorSchema(FsvDracoAccessorSchema&& other,
                         fsv_draco::FsvDecodeControl* control)
      : FsvDracoAccessorSchema(other, control) {
    other.type.clear();
  }
  FsvDracoAccessorSchema(FsvDracoAccessorSchema&&) noexcept = default;
  FsvDracoAccessorSchema& operator=(FsvDracoAccessorSchema&& other) {
    if (this != &other) {
      accessor_index = other.accessor_index;
      component_type = other.component_type;
      if (control_ == other.control_) {
        type = std::move(other.type);
      } else {
        type.assign(other.type.data(), other.type.size());
        other.type.clear();
      }
      count = other.count;
      normalized = other.normalized;
    }
    return *this;
  }
  FsvDracoAccessorSchema& operator=(const FsvDracoAccessorSchema& other) {
    if (this != &other) {
      accessor_index = other.accessor_index;
      component_type = other.component_type;
      type.assign(other.type.data(), other.type.size());
      count = other.count;
      normalized = other.normalized;
    }
    return *this;
  }

  int64_t accessor_index = -1;
  FsvDracoBudgetNumber component_type;
  FsvDracoString type;
  int64_t count = -1;
  bool normalized = false;

  fsv_draco::FsvDecodeControl* control() const { return control_; }

 private:
  fsv_draco::FsvDecodeControl* control_ = nullptr;
};

struct FsvDracoDecodedMeshMetadata {
  explicit FsvDracoDecodedMeshMetadata(
      fsv_draco::FsvDecodeControl* control = nullptr)
      : attribute_unique_ids(FsvDracoAllocator<uint32_t>(control)),
        control_(control) {}

  int64_t point_count = -1;
  int64_t face_count = -1;
  FsvDracoSet<uint32_t> attribute_unique_ids;

 private:
  fsv_draco::FsvDecodeControl* control_ = nullptr;
};

struct FsvDracoPrimitiveRequest {
  explicit FsvDracoPrimitiveRequest(
      fsv_draco::FsvDecodeControl* control = nullptr)
      : compressed_bytes(FsvDracoAllocator<uint8_t>(control)),
        attributes(std::less<>(), FsvDracoAllocator<
                                    std::pair<const FsvDracoString, int64_t>>(
                                    control)),
        attribute_accessors(
            std::less<>(),
            FsvDracoAllocator<std::pair<const FsvDracoString,
                                        FsvDracoAccessorSchema>>(control)),
        indices_accessor(control),
        control_(control) {}
  FsvDracoPrimitiveRequest(const FsvDracoPrimitiveRequest&) = delete;
  FsvDracoPrimitiveRequest(const FsvDracoPrimitiveRequest& other,
                           fsv_draco::FsvDecodeControl* control)
      : FsvDracoPrimitiveRequest(control) {
    mesh_index = other.mesh_index;
    primitive_index = other.primitive_index;
    compressed_bytes.assign(other.compressed_bytes.begin(),
                            other.compressed_bytes.end());
    for (const auto& entry : other.attributes) {
      attributes.emplace(
          FsvDracoString(entry.first.data(), entry.first.size(),
                         FsvDracoAllocator<char>(control)),
          entry.second);
    }
    for (const auto& entry : other.attribute_accessors) {
      attribute_accessors.emplace(
          FsvDracoString(entry.first.data(), entry.first.size(),
                         FsvDracoAllocator<char>(control)),
          FsvDracoAccessorSchema(entry.second, control));
    }
    vertex_accessor_index = other.vertex_accessor_index;
    has_indices_accessor = other.has_indices_accessor;
    indices_accessor = FsvDracoAccessorSchema(other.indices_accessor, control);
  }
  FsvDracoPrimitiveRequest(FsvDracoPrimitiveRequest&& other,
                           fsv_draco::FsvDecodeControl* control)
      : FsvDracoPrimitiveRequest(other, control) {
    other.compressed_bytes.clear();
    other.attributes.clear();
    other.attribute_accessors.clear();
  }
  FsvDracoPrimitiveRequest(FsvDracoPrimitiveRequest&&) noexcept = default;
  FsvDracoPrimitiveRequest& operator=(FsvDracoPrimitiveRequest&& other) {
    if (this != &other) {
      if (control_ == other.control_) {
        mesh_index = other.mesh_index;
        primitive_index = other.primitive_index;
        compressed_bytes = std::move(other.compressed_bytes);
        attributes = std::move(other.attributes);
        attribute_accessors = std::move(other.attribute_accessors);
        vertex_accessor_index = other.vertex_accessor_index;
        has_indices_accessor = other.has_indices_accessor;
        indices_accessor = std::move(other.indices_accessor);
      } else {
        FsvDracoPrimitiveRequest replacement(std::move(other), control_);
        mesh_index = replacement.mesh_index;
        primitive_index = replacement.primitive_index;
        compressed_bytes.swap(replacement.compressed_bytes);
        attributes.swap(replacement.attributes);
        attribute_accessors.swap(replacement.attribute_accessors);
        vertex_accessor_index = replacement.vertex_accessor_index;
        has_indices_accessor = replacement.has_indices_accessor;
        indices_accessor = std::move(replacement.indices_accessor);
      }
    }
    return *this;
  }

  fsv_draco::FsvDecodeControl* control() const { return control_; }

  int mesh_index = -1;
  int primitive_index = -1;
  FsvDracoByteVector compressed_bytes;
  FsvDracoMap<FsvDracoString, int64_t> attributes;
  FsvDracoMap<FsvDracoString, FsvDracoAccessorSchema> attribute_accessors;
  int64_t vertex_accessor_index = -1;
  bool has_indices_accessor = false;
  FsvDracoAccessorSchema indices_accessor;

 private:
  fsv_draco::FsvDecodeControl* control_ = nullptr;
};

struct FsvDracoDiagnostic {
  explicit FsvDracoDiagnostic(
      fsv_draco::FsvDecodeControl* control = nullptr)
      : status(FsvDracoAllocator<char>(control)),
        message(FsvDracoAllocator<char>(control)),
        attribute(FsvDracoAllocator<char>(control)),
        stage(FsvDracoAllocator<char>(control)),
        field(FsvDracoAllocator<char>(control)),
        control_(control) {}
  FsvDracoDiagnostic(const FsvDracoDiagnostic&) = delete;
  FsvDracoDiagnostic(const FsvDracoDiagnostic& other,
                     fsv_draco::FsvDecodeControl* control)
      : FsvDracoDiagnostic(control) {
    status.assign(other.status.data(), other.status.size());
    message.assign(other.message.data(), other.message.size());
    mesh_index = other.mesh_index;
    primitive_index = other.primitive_index;
    attribute.assign(other.attribute.data(), other.attribute.size());
    stage.assign(other.stage.data(), other.stage.size());
    field.assign(other.field.data(), other.field.size());
    has_limit = other.has_limit;
    limit = other.limit;
    has_actual = other.has_actual;
    actual = other.actual;
  }
  FsvDracoDiagnostic(FsvDracoDiagnostic&& other,
                     fsv_draco::FsvDecodeControl* control)
      : FsvDracoDiagnostic(other, control) {
    other.status.clear();
    other.message.clear();
    other.attribute.clear();
    other.stage.clear();
    other.field.clear();
  }
  FsvDracoDiagnostic(FsvDracoDiagnostic&&) noexcept = default;
  FsvDracoDiagnostic& operator=(FsvDracoDiagnostic&& other) {
    if (this != &other) {
      if (control_ == other.control_) {
        status = std::move(other.status);
        message = std::move(other.message);
        mesh_index = other.mesh_index;
        primitive_index = other.primitive_index;
        attribute = std::move(other.attribute);
        stage = std::move(other.stage);
        field = std::move(other.field);
        has_limit = other.has_limit;
        limit = other.limit;
        has_actual = other.has_actual;
        actual = other.actual;
      } else {
        FsvDracoDiagnostic replacement(std::move(other), control_);
        status.swap(replacement.status);
        message.swap(replacement.message);
        mesh_index = replacement.mesh_index;
        primitive_index = replacement.primitive_index;
        attribute.swap(replacement.attribute);
        stage.swap(replacement.stage);
        field.swap(replacement.field);
        has_limit = replacement.has_limit;
        limit = replacement.limit;
        has_actual = replacement.has_actual;
        actual = replacement.actual;
      }
    }
    return *this;
  }

  FsvDracoString status;
  FsvDracoString message;
  int mesh_index = -1;
  int primitive_index = -1;
  FsvDracoString attribute;
  FsvDracoString stage;
  FsvDracoString field;
  bool has_limit = false;
  uint64_t limit = 0;
  bool has_actual = false;
  uint64_t actual = 0;

 private:
  fsv_draco::FsvDecodeControl* control_ = nullptr;
};

struct FsvDracoPreflightResult {
  explicit FsvDracoPreflightResult(
      fsv_draco::FsvDecodeControl* control = nullptr)
      : diagnostics(FsvDracoAllocator<FsvDracoDiagnostic>(control)),
        control_(control) {}
  FsvDracoPreflightResult(FsvDracoPreflightResult&&) noexcept = default;
  FsvDracoPreflightResult& operator=(FsvDracoPreflightResult&&) noexcept =
      default;

  fsv_draco::FsvDecodeControl* control() const { return control_; }

  bool ok = false;
  uint64_t total_decoded_bytes = 0;
  uint64_t native_output_bytes = 0;
  uint64_t accessors = 0;
  uint64_t vertices = 0;
  uint64_t indices = 0;
  FsvDracoVector<FsvDracoDiagnostic> diagnostics;

 private:
  fsv_draco::FsvDecodeControl* control_ = nullptr;
};

struct FsvDracoPostDecodeValidationResult {
  explicit FsvDracoPostDecodeValidationResult(
      fsv_draco::FsvDecodeControl* control = nullptr)
      : diagnostics(FsvDracoAllocator<FsvDracoDiagnostic>(control)),
        control_(control) {}
  FsvDracoPostDecodeValidationResult(
      FsvDracoPostDecodeValidationResult&&) noexcept = default;
  FsvDracoPostDecodeValidationResult& operator=(
      FsvDracoPostDecodeValidationResult&&) noexcept = default;

  bool ok = false;
  FsvDracoVector<FsvDracoDiagnostic> diagnostics;

  fsv_draco::FsvDecodeControl* control() const { return control_; }

 private:
  fsv_draco::FsvDecodeControl* control_ = nullptr;
};

using FsvDracoPrimitiveRequests = FsvDracoVector<FsvDracoPrimitiveRequest>;
using FsvDracoDecodedMeshMetadataVector =
    FsvDracoVector<FsvDracoDecodedMeshMetadata>;

FsvDracoPreflightResult FsvDracoPreflightRequests(
    const FsvDracoPrimitiveRequests& requests,
    const FsvDracoDecodeBudgetMetadata& budget,
    const FsvDracoDecodeBudgetState& state,
    fsv_draco::FsvDecodeControl* control = nullptr);

FsvDracoPostDecodeValidationResult FsvDracoValidateDecodedSchemas(
    const FsvDracoPrimitiveRequests& requests,
    const FsvDracoDecodedMeshMetadataVector& decoded_meshes,
    fsv_draco::FsvDecodeControl* control = nullptr);

#endif  // FSV_DRACO_BUDGET_H_
