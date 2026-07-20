// Copyright 2026 flutter_scene_viewer authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <cstdint>
#include <fstream>
#include <memory>
#include <string>
#include <vector>

#include "draco/compression/config/compression_shared.h"
#include "draco/compression/encode.h"
#include "draco/core/encoder_buffer.h"
#include "draco/mesh/mesh.h"
#include "draco/metadata/geometry_metadata.h"

namespace {

std::string LongName(const char prefix) {
  return std::string(120, prefix);
}

std::vector<uint8_t> Blob() {
  std::vector<uint8_t> blob(4096);
  for (size_t i = 0; i < blob.size(); ++i) {
    blob[i] = static_cast<uint8_t>((i * 37 + 11) & 0xff);
  }
  return blob;
}

}  // namespace

int main(int argc, char **argv) {
  if (argc != 2) {
    return 1;
  }

  draco::Mesh mesh;
  mesh.set_num_points(3);
  mesh.AddFace({draco::PointIndex(0), draco::PointIndex(1),
                draco::PointIndex(2)});

  draco::GeometryAttribute position_descriptor;
  position_descriptor.Init(draco::GeometryAttribute::POSITION, nullptr, 3,
                           draco::DT_FLOAT32, false, sizeof(float) * 3, 0);
  auto position = std::unique_ptr<draco::PointAttribute>(
      new draco::PointAttribute(position_descriptor));
  position->SetIdentityMapping();
  if (!position->Reset(3)) {
    return 2;
  }
  constexpr float kPositions[3][3] = {
      {-1.0f, -1.0f, 0.0f},
      {1.0f, -1.0f, 0.0f},
      {0.0f, 1.0f, 0.0f},
  };
  for (int i = 0; i < 3; ++i) {
    position->SetAttributeValue(draco::AttributeValueIndex(i), kPositions[i]);
  }
  mesh.AddAttribute(std::move(position));

  auto geometry = std::unique_ptr<draco::GeometryMetadata>(
      new draco::GeometryMetadata());
  geometry->AddEntryString(LongName('g'), std::string(180, 'G'));
  geometry->AddEntryBinary("non_trivial_blob", Blob());

  auto attribute = std::unique_ptr<draco::AttributeMetadata>(
      new draco::AttributeMetadata());
  attribute->AddEntryString(LongName('a'), std::string(170, 'A'));
  mesh.AddMetadata(std::move(geometry));
  mesh.AddAttributeMetadata(0, std::move(attribute));

  auto nested = std::unique_ptr<draco::Metadata>(new draco::Metadata());
  nested->AddEntryString(LongName('n'), std::string(160, 'N'));
  auto leaf = std::unique_ptr<draco::Metadata>(new draco::Metadata());
  leaf->AddEntryInt("leaf_value", 1701);
  if (!nested->AddSubMetadata(LongName('l'), std::move(leaf)) ||
      !mesh.metadata()->AddSubMetadata(LongName('s'), std::move(nested))) {
    return 3;
  }

  draco::Encoder encoder;
  encoder.SetEncodingMethod(draco::MESH_SEQUENTIAL_ENCODING);
  encoder.SetSpeedOptions(5, 5);
  encoder.options().SetGlobalBool("compress_connectivity", true);
  draco::EncoderBuffer encoded;
  const draco::Status status = encoder.EncodeMeshToBuffer(mesh, &encoded);
  if (!status.ok()) {
    return 4;
  }

  std::ofstream output(argv[1], std::ios::binary);
  output.write(encoded.data(), static_cast<std::streamsize>(encoded.size()));
  return output.good() ? 0 : 5;
}
