#include "fsv_draco_budget.h"

#include <algorithm>
#include <limits>
#include <set>
#include <string_view>
#include <utility>

namespace {
void Assign(FsvDracoString* destination, std::string_view source) {
  destination->assign(source.data(), source.size());
}

FsvDracoDiagnostic InvalidMetadata(std::string_view field,
                                   std::string_view message,
                                   int mesh_index = -1,
                                   int primitive_index = -1,
                                   std::string_view attribute = {},
                                   fsv_draco::FsvDecodeControl* control = nullptr) {
  FsvDracoDiagnostic diagnostic(control);
  Assign(&diagnostic.status, "invalidMetadata");
  Assign(&diagnostic.message, message);
  diagnostic.mesh_index = mesh_index;
  diagnostic.primitive_index = primitive_index;
  Assign(&diagnostic.attribute, attribute);
  Assign(&diagnostic.stage, "dracoNativePreflight");
  Assign(&diagnostic.field, field);
  return diagnostic;
}

bool ReadNumber(const FsvDracoBudgetNumber& number,
                const char* field,
                uint64_t* value,
                FsvDracoDiagnostic* diagnostic,
                fsv_draco::FsvDecodeControl* control) {
  if (!number.present || !number.is_integer || number.value < 0 ||
      number.value > kFsvDracoMaxSafeInteger) {
    *diagnostic = InvalidMetadata(
        field,
        "Native Draco decode metadata must be a non-negative web-safe integer.",
        -1, -1, {}, control);
    if (number.present && number.is_integer && number.value >= 0) {
      diagnostic->has_actual = true;
      diagnostic->actual = static_cast<uint64_t>(number.value);
    }
    diagnostic->has_limit = true;
    diagnostic->limit = static_cast<uint64_t>(kFsvDracoMaxSafeInteger);
    return false;
  }
  *value = static_cast<uint64_t>(number.value);
  return true;
}

bool CheckedAdd(uint64_t current,
                uint64_t increment,
                uint64_t limit,
                const char* field,
                uint64_t* result,
                FsvDracoDiagnostic* diagnostic) {
  if (current > limit || increment > limit - current) {
    Assign(&diagnostic->status, "budgetExceeded");
    Assign(&diagnostic->message,
           "Declared native Draco output exceeds the configured decode budget.");
    Assign(&diagnostic->stage, "dracoNativePreflight");
    Assign(&diagnostic->field, field);
    diagnostic->has_limit = true;
    diagnostic->limit = limit;
    diagnostic->has_actual = true;
    diagnostic->actual = current > limit ? current : current + increment;
    return false;
  }
  *result = current + increment;
  return true;
}

int ComponentBytes(int64_t component_type, bool indices) {
  if (indices) {
    switch (component_type) {
      case 5121:
        return 1;
      case 5123:
        return 2;
      case 5125:
        return 4;
      default:
        return 0;
    }
  }
  switch (component_type) {
    case 5120:
    case 5121:
      return 1;
    case 5122:
    case 5123:
      return 2;
    case 5125:
    case 5126:
      return 4;
    default:
      return 0;
  }
}

int ComponentCount(std::string_view type, bool indices) {
  if (type == "SCALAR") {
    return 1;
  }
  if (indices) {
    return 0;
  }
  if (type == "VEC2") {
    return 2;
  }
  if (type == "VEC3") {
    return 3;
  }
  if (type == "VEC4") {
    return 4;
  }
  return 0;
}

bool ValidateAccessor(const FsvDracoAccessorSchema& schema,
                      bool indices,
                      const FsvDracoPrimitiveRequest& request,
                      std::string_view attribute,
                      uint64_t* byte_length,
                      FsvDracoDiagnostic* diagnostic,
                      fsv_draco::FsvDecodeControl* control) {
  if (schema.accessor_index < 0 ||
      schema.accessor_index > kFsvDracoMaxSafeInteger) {
    *diagnostic = InvalidMetadata("accessorIndex",
                                  "Draco accessor index is invalid.",
                                  request.mesh_index,
                                  request.primitive_index,
                                  attribute, control);
    return false;
  }
  if (!schema.component_type.present || !schema.component_type.is_integer ||
      schema.component_type.value < 0 ||
      schema.component_type.value > kFsvDracoMaxSafeInteger) {
    *diagnostic = InvalidMetadata("accessor.componentType",
                                  "Draco accessor component type is invalid.",
                                  request.mesh_index,
                                  request.primitive_index,
                                  attribute, control);
    diagnostic->has_limit = true;
    diagnostic->limit = static_cast<uint64_t>(kFsvDracoMaxSafeInteger);
    if (schema.component_type.present && schema.component_type.is_integer &&
        schema.component_type.value >= 0) {
      diagnostic->has_actual = true;
      diagnostic->actual =
          static_cast<uint64_t>(schema.component_type.value);
    }
    return false;
  }
  const int component_bytes =
      ComponentBytes(schema.component_type.value, indices);
  if (component_bytes == 0) {
    *diagnostic = InvalidMetadata("accessor.componentType",
                                  "Draco accessor component type is invalid.",
                                  request.mesh_index,
                                  request.primitive_index,
                                  attribute, control);
    return false;
  }
  const int component_count = ComponentCount(schema.type, indices);
  if (component_count == 0) {
    *diagnostic = InvalidMetadata("accessor.type",
                                  "Draco accessor type is invalid.",
                                  request.mesh_index,
                                  request.primitive_index,
                                  attribute, control);
    return false;
  }
  if (schema.count <= 0 || schema.count > kFsvDracoMaxSafeInteger) {
    *diagnostic = InvalidMetadata("accessor.count",
                                  "Draco accessor count is invalid.",
                                  request.mesh_index,
                                  request.primitive_index,
                                  attribute, control);
    if (schema.count >= 0) {
      diagnostic->has_actual = true;
      diagnostic->actual = static_cast<uint64_t>(schema.count);
    }
    diagnostic->has_limit = true;
    diagnostic->limit = static_cast<uint64_t>(kFsvDracoMaxSafeInteger);
    return false;
  }
  const uint64_t count = static_cast<uint64_t>(schema.count);
  const uint64_t bytes_per_element =
      static_cast<uint64_t>(component_bytes * component_count);
  if (count > static_cast<uint64_t>(kFsvDracoMaxSafeInteger) /
                  bytes_per_element) {
    *diagnostic = InvalidMetadata(
        "accessor.count",
        "Draco accessor output byte length exceeds the web-safe range.",
        request.mesh_index,
        request.primitive_index,
        attribute, control);
    diagnostic->has_limit = true;
    diagnostic->limit =
        static_cast<uint64_t>(kFsvDracoMaxSafeInteger) / bytes_per_element;
    diagnostic->has_actual = true;
    diagnostic->actual = count;
    return false;
  }
  *byte_length = count * bytes_per_element;
  return true;
}

bool SameSchema(const FsvDracoAccessorSchema& left,
                const FsvDracoAccessorSchema& right) {
  return left.component_type.present == right.component_type.present &&
         left.component_type.is_integer == right.component_type.is_integer &&
         left.component_type.value == right.component_type.value &&
         left.type == right.type && left.count == right.count &&
         left.normalized == right.normalized;
}

FsvDracoDiagnostic DecodedSchemaDiagnostic(
    const FsvDracoPrimitiveRequest& request,
    std::string_view field,
    std::string_view message,
    std::string_view attribute = {},
    fsv_draco::FsvDecodeControl* control = nullptr) {
  FsvDracoDiagnostic diagnostic(control);
  Assign(&diagnostic.status, "malformedOutput");
  Assign(&diagnostic.message, message);
  diagnostic.mesh_index = request.mesh_index;
  diagnostic.primitive_index = request.primitive_index;
  Assign(&diagnostic.attribute, attribute);
  Assign(&diagnostic.stage, "dracoDecodedSchema");
  Assign(&diagnostic.field, field);
  return diagnostic;
}
}  // namespace

FsvDracoPreflightResult FsvDracoPreflightRequests(
    const FsvDracoPrimitiveRequests& requests,
    const FsvDracoDecodeBudgetMetadata& budget,
    const FsvDracoDecodeBudgetState& state,
    fsv_draco::FsvDecodeControl* control) {
  FsvDracoPreflightResult result(control);
  uint64_t max_total_decoded_bytes = 0;
  uint64_t max_accessors = 0;
  uint64_t max_vertices = 0;
  uint64_t max_indices = 0;
  uint64_t max_native_output_bytes = 0;
  uint64_t current_total_decoded_bytes = 0;
  uint64_t current_accessors = 0;
  uint64_t current_vertices = 0;
  uint64_t current_indices = 0;
  uint64_t current_native_output_bytes = 0;
  FsvDracoDiagnostic diagnostic(control);
#define FSV_READ(number, field, target)                                      \
  if (!ReadNumber(number, field, &target, &diagnostic, control)) {           \
    result.diagnostics.push_back(std::move(diagnostic));                     \
    return result;                                                           \
  }
  FSV_READ(budget.max_total_decoded_bytes, "maxTotalDecodedBytes",
           max_total_decoded_bytes)
  FSV_READ(budget.max_accessors, "maxAccessors", max_accessors)
  FSV_READ(budget.max_vertices, "maxVertices", max_vertices)
  FSV_READ(budget.max_indices, "maxIndices", max_indices)
  FSV_READ(budget.max_native_output_bytes, "maxNativeOutputBytes",
           max_native_output_bytes)
  FSV_READ(state.total_decoded_bytes, "totalDecodedBytes",
           current_total_decoded_bytes)
  FSV_READ(state.accessors, "accessors", current_accessors)
  FSV_READ(state.vertices, "vertices", current_vertices)
  FSV_READ(state.indices, "indices", current_indices)
  FSV_READ(state.native_output_bytes, "nativeOutputBytes",
           current_native_output_bytes)
#undef FSV_READ

  uint64_t ignored = 0;
  if (!CheckedAdd(current_total_decoded_bytes, 0, max_total_decoded_bytes,
                  "totalDecodedBytes", &ignored, &diagnostic) ||
      !CheckedAdd(current_accessors, 0, max_accessors, "accessors", &ignored,
                  &diagnostic) ||
      !CheckedAdd(current_vertices, 0, max_vertices, "vertices", &ignored,
                  &diagnostic) ||
      !CheckedAdd(current_indices, 0, max_indices, "indices", &ignored,
                  &diagnostic) ||
      !CheckedAdd(current_native_output_bytes, 0, max_native_output_bytes,
                  "nativeOutputBytes", &ignored, &diagnostic)) {
    result.diagnostics.push_back(std::move(diagnostic));
    return result;
  }
  if (current_native_output_bytes > current_total_decoded_bytes) {
    result.diagnostics.push_back(InvalidMetadata(
        "nativeOutputBytes",
        "Native output accounting exceeds total decoded-byte accounting.",
        -1, -1, {}, control));
    return result;
  }

  FsvDracoSet<std::pair<int, int>> primitive_targets{
      std::less<>(), FsvDracoAllocator<std::pair<int, int>>(control)};
  FsvDracoMap<int64_t, FsvDracoAccessorSchema> output_accessors{
      std::less<>(),
      FsvDracoAllocator<std::pair<const int64_t, FsvDracoAccessorSchema>>(
          control)};
  FsvDracoMap<int64_t, uint64_t> vertex_counts{
      std::less<>(),
      FsvDracoAllocator<std::pair<const int64_t, uint64_t>>(control)};
  FsvDracoMap<int64_t, uint64_t> index_counts{
      std::less<>(),
      FsvDracoAllocator<std::pair<const int64_t, uint64_t>>(control)};
  uint64_t output_bytes = 0;
  for (const FsvDracoPrimitiveRequest& request : requests) {
    if (!primitive_targets
             .insert({request.mesh_index, request.primitive_index})
             .second) {
      result.diagnostics.push_back(InvalidMetadata(
          "dracoPrimitives",
          "Native Draco primitive targets must be unique.",
          request.mesh_index,
          request.primitive_index, {}, control));
      return result;
    }
    if (request.attributes.empty() || request.attribute_accessors.empty()) {
      result.diagnostics.push_back(InvalidMetadata(
          "primitive.attributes",
          "Native Draco primitive accessor metadata is incomplete.",
          request.mesh_index,
          request.primitive_index, {}, control));
      return result;
    }

    int64_t authored_count = -1;
    for (const auto& entry : request.attribute_accessors) {
      uint64_t byte_length = 0;
      if (!ValidateAccessor(entry.second, false, request, entry.first,
                            &byte_length, &diagnostic, control)) {
        result.diagnostics.push_back(std::move(diagnostic));
        return result;
      }
      if (authored_count < 0) {
        authored_count = entry.second.count;
      } else if (entry.second.count != authored_count) {
        result.diagnostics.push_back(InvalidMetadata(
            "vertexCount",
            "Authored Draco primitive attributes have inconsistent counts.",
            request.mesh_index,
            request.primitive_index,
            entry.first, control));
        return result;
      }
    }
    const auto vertex_schema = std::find_if(
        request.attribute_accessors.begin(),
        request.attribute_accessors.end(),
        [&request](const auto& entry) {
          return entry.second.accessor_index == request.vertex_accessor_index;
        });
    if (request.vertex_accessor_index < 0 ||
        vertex_schema == request.attribute_accessors.end()) {
      result.diagnostics.push_back(InvalidMetadata(
          "vertexAccessorIndex",
          "Native Draco vertex reservation accessor is invalid.",
          request.mesh_index,
          request.primitive_index, {}, control));
      return result;
    }
    const auto prior_vertex = vertex_counts.find(request.vertex_accessor_index);
    if (prior_vertex != vertex_counts.end() &&
        prior_vertex->second != static_cast<uint64_t>(authored_count)) {
      result.diagnostics.push_back(InvalidMetadata(
          "vertexAccessorIndex",
          "A reused Draco vertex accessor has conflicting counts.",
          request.mesh_index,
          request.primitive_index, {}, control));
      return result;
    }
    vertex_counts.insert_or_assign(request.vertex_accessor_index,
                                   static_cast<uint64_t>(authored_count));

    for (const auto& attribute : request.attributes) {
      if (attribute.second < 0 ||
          static_cast<uint64_t>(attribute.second) >
              std::numeric_limits<uint32_t>::max()) {
        result.diagnostics.push_back(InvalidMetadata(
            "dracoAttributeId",
            "Compressed Draco attribute id is outside the uint32 range.",
            request.mesh_index,
            request.primitive_index,
            attribute.first, control));
        return result;
      }
      const auto schema = request.attribute_accessors.find(attribute.first);
      if (schema == request.attribute_accessors.end()) {
        FsvDracoString field("primitive.attributes.",
                             FsvDracoAllocator<char>(control));
        field.append(attribute.first.data(), attribute.first.size());
        result.diagnostics.push_back(InvalidMetadata(
            field,
            "Compressed Draco attribute has no accessor schema.",
            request.mesh_index,
            request.primitive_index,
            attribute.first, control));
        return result;
      }
      uint64_t byte_length = 0;
      if (!ValidateAccessor(schema->second, false, request, attribute.first,
                            &byte_length, &diagnostic, control)) {
        result.diagnostics.push_back(std::move(diagnostic));
        return result;
      }
      const auto prior = output_accessors.find(schema->second.accessor_index);
      if (prior != output_accessors.end() &&
          !SameSchema(prior->second, schema->second)) {
        result.diagnostics.push_back(InvalidMetadata(
            "accessorIndex",
            "A reused Draco accessor has conflicting schemas.",
            request.mesh_index,
            request.primitive_index,
            attribute.first, control));
        return result;
      }
      if (prior == output_accessors.end()) {
        output_accessors.emplace(
            schema->second.accessor_index,
            FsvDracoAccessorSchema(schema->second, control));
      }
      if (output_bytes > static_cast<uint64_t>(kFsvDracoMaxSafeInteger) -
                             byte_length) {
        result.diagnostics.push_back(InvalidMetadata(
            "nativeOutputBytes",
            "Aggregate Draco output exceeds the web-safe integer range.",
            request.mesh_index,
            request.primitive_index,
            attribute.first, control));
        return result;
      }
      output_bytes += byte_length;
    }

    if (request.has_indices_accessor) {
      uint64_t byte_length = 0;
      if (!ValidateAccessor(request.indices_accessor, true, request,
                            {}, &byte_length, &diagnostic, control)) {
        result.diagnostics.push_back(std::move(diagnostic));
        return result;
      }
      const auto prior =
          output_accessors.find(request.indices_accessor.accessor_index);
      if (prior != output_accessors.end() &&
          !SameSchema(prior->second, request.indices_accessor)) {
        result.diagnostics.push_back(InvalidMetadata(
            "accessorIndex",
            "A reused Draco index accessor has a conflicting schema.",
            request.mesh_index,
          request.primitive_index, {}, control));
        return result;
      }
      if (prior == output_accessors.end()) {
        output_accessors.emplace(
            request.indices_accessor.accessor_index,
            FsvDracoAccessorSchema(request.indices_accessor, control));
      }
      index_counts.insert_or_assign(
          request.indices_accessor.accessor_index,
          static_cast<uint64_t>(request.indices_accessor.count));
      if (output_bytes > static_cast<uint64_t>(kFsvDracoMaxSafeInteger) -
                             byte_length) {
        result.diagnostics.push_back(InvalidMetadata(
            "nativeOutputBytes",
            "Aggregate Draco output exceeds the web-safe integer range.",
            request.mesh_index,
            request.primitive_index, {}, control));
        return result;
      }
      output_bytes += byte_length;
    }
  }

  uint64_t vertex_increment = 0;
  for (const auto& entry : vertex_counts) {
    if (vertex_increment > static_cast<uint64_t>(kFsvDracoMaxSafeInteger) -
                               entry.second) {
      result.diagnostics.push_back(InvalidMetadata(
          "vertices", "Aggregate Draco vertex count is not web-safe.",
          -1, -1, {}, control));
      return result;
    }
    vertex_increment += entry.second;
  }
  uint64_t index_increment = 0;
  for (const auto& entry : index_counts) {
    if (index_increment > static_cast<uint64_t>(kFsvDracoMaxSafeInteger) -
                              entry.second) {
      result.diagnostics.push_back(InvalidMetadata(
          "indices", "Aggregate Draco index count is not web-safe.",
          -1, -1, {}, control));
      return result;
    }
    index_increment += entry.second;
  }

  if (!CheckedAdd(current_total_decoded_bytes, output_bytes,
                  max_total_decoded_bytes, "totalDecodedBytes",
                  &result.total_decoded_bytes, &diagnostic) ||
      !CheckedAdd(current_native_output_bytes, output_bytes,
                  max_native_output_bytes, "nativeOutputBytes",
                  &result.native_output_bytes, &diagnostic) ||
      !CheckedAdd(current_accessors, output_accessors.size(), max_accessors,
                  "accessors", &result.accessors, &diagnostic) ||
      !CheckedAdd(current_vertices, vertex_increment, max_vertices, "vertices",
                  &result.vertices, &diagnostic) ||
      !CheckedAdd(current_indices, index_increment, max_indices, "indices",
                  &result.indices, &diagnostic)) {
    result.diagnostics.push_back(std::move(diagnostic));
    return result;
  }
  result.ok = true;
  return result;
}

FsvDracoPostDecodeValidationResult FsvDracoValidateDecodedSchemas(
    const FsvDracoPrimitiveRequests& requests,
    const FsvDracoDecodedMeshMetadataVector& decoded_meshes,
    fsv_draco::FsvDecodeControl* control) {
  FsvDracoPostDecodeValidationResult result(control);
  if (requests.size() != decoded_meshes.size()) {
    FsvDracoDiagnostic diagnostic(control);
    Assign(&diagnostic.status, "malformedOutput");
    Assign(&diagnostic.message,
           "Google Draco returned an unexpected decoded mesh count.");
    Assign(&diagnostic.stage, "dracoDecodedSchema");
    Assign(&diagnostic.field, "decodedMeshes");
    diagnostic.has_limit = true;
    diagnostic.limit = requests.size();
    diagnostic.has_actual = true;
    diagnostic.actual = decoded_meshes.size();
    result.diagnostics.push_back(std::move(diagnostic));
    return result;
  }

  for (size_t index = 0; index < requests.size(); index += 1) {
    const FsvDracoPrimitiveRequest& request = requests[index];
    const FsvDracoDecodedMeshMetadata& decoded = decoded_meshes[index];
    if (decoded.point_count < 0 || decoded.face_count < 0) {
      result.diagnostics.push_back(DecodedSchemaDiagnostic(
          request,
          "decodedMesh.count",
          "Google Draco returned a negative point or face count.", {},
          control));
      return result;
    }
    for (const auto& entry : request.attribute_accessors) {
      if (entry.second.count != decoded.point_count) {
        FsvDracoDiagnostic diagnostic = DecodedSchemaDiagnostic(
            request,
            "accessor.count",
            "Google Draco point count does not match the glTF accessor schema.",
            entry.first, control);
        diagnostic.has_limit = true;
        diagnostic.limit = static_cast<uint64_t>(entry.second.count);
        diagnostic.has_actual = true;
        diagnostic.actual = static_cast<uint64_t>(decoded.point_count);
        result.diagnostics.push_back(std::move(diagnostic));
        return result;
      }
    }
    for (const auto& attribute : request.attributes) {
      if (attribute.second < 0 ||
          static_cast<uint64_t>(attribute.second) >
              std::numeric_limits<uint32_t>::max() ||
          decoded.attribute_unique_ids.count(
              static_cast<uint32_t>(attribute.second)) == 0) {
        FsvDracoDiagnostic diagnostic = DecodedSchemaDiagnostic(
            request,
            "dracoAttributeId",
            "Google Draco did not return a requested attribute unique id.",
            attribute.first, control);
        if (attribute.second >= 0) {
          diagnostic.has_limit = true;
          diagnostic.limit = static_cast<uint64_t>(attribute.second);
        }
        result.diagnostics.push_back(std::move(diagnostic));
        return result;
      }
    }
    if (request.has_indices_accessor) {
      if (decoded.face_count >
          static_cast<int64_t>(kFsvDracoMaxSafeInteger / 3)) {
        result.diagnostics.push_back(DecodedSchemaDiagnostic(
            request,
            "indices.count",
            "Google Draco face count exceeds the web-safe index range.", {},
            control));
        return result;
      }
      const int64_t decoded_index_count = decoded.face_count * 3;
      if (request.indices_accessor.count != decoded_index_count) {
        FsvDracoDiagnostic diagnostic = DecodedSchemaDiagnostic(
            request,
            "indices.count",
            "Google Draco face count does not match the glTF index accessor schema.",
            {}, control);
        diagnostic.has_limit = true;
        diagnostic.limit =
            static_cast<uint64_t>(request.indices_accessor.count);
        diagnostic.has_actual = true;
        diagnostic.actual = static_cast<uint64_t>(decoded_index_count);
        result.diagnostics.push_back(std::move(diagnostic));
        return result;
      }
    }
  }
  result.ok = true;
  return result;
}
