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

#include "draco/compression/config/compression_shared.h"
#include "draco/compression/encode.h"
#include "draco/core/encoder_buffer.h"
#include "draco/mesh/mesh.h"

int main(int argc, char **argv) {
  if (argc != 2) {
    return 1;
  }

  draco::Mesh mesh;
  mesh.set_num_points(4);
  mesh.AddFace({draco::PointIndex(0), draco::PointIndex(1),
                draco::PointIndex(2)});
  mesh.AddFace({draco::PointIndex(0), draco::PointIndex(2),
                draco::PointIndex(3)});

  draco::GeometryAttribute position_descriptor;
  position_descriptor.Init(draco::GeometryAttribute::POSITION, nullptr, 3,
                           draco::DT_FLOAT32, false, sizeof(float) * 3, 0);
  auto position = std::unique_ptr<draco::PointAttribute>(
      new draco::PointAttribute(position_descriptor));
  position->SetIdentityMapping();
  if (!position->Reset(4)) {
    return 2;
  }
  constexpr float kPositions[4][3] = {
      {-1.0f, -1.0f, 0.0f},
      {1.0f, -1.0f, 0.0f},
      {1.0f, 1.0f, 0.0f},
      {-1.0f, 1.0f, 0.0f},
  };
  for (int i = 0; i < 4; ++i) {
    position->SetAttributeValue(draco::AttributeValueIndex(i), kPositions[i]);
  }
  mesh.AddAttribute(std::move(position));

  draco::GeometryAttribute feature_descriptor;
  feature_descriptor.Init(draco::GeometryAttribute::GENERIC, nullptr, 1,
                          draco::DT_UINT16, false, sizeof(uint16_t), 0);
  auto feature = std::unique_ptr<draco::PointAttribute>(
      new draco::PointAttribute(feature_descriptor));
  feature->SetIdentityMapping();
  if (!feature->Reset(4)) {
    return 3;
  }
  constexpr uint16_t kFeatureIds[4] = {7, 11, 13, 17};
  for (int i = 0; i < 4; ++i) {
    feature->SetAttributeValue(draco::AttributeValueIndex(i),
                               &kFeatureIds[i]);
  }
  mesh.AddAttribute(std::move(feature));

  draco::GeometryAttribute raw_descriptor;
  raw_descriptor.Init(draco::GeometryAttribute::GENERIC, nullptr, 1,
                      draco::DT_FLOAT32, false, sizeof(float), 0);
  auto raw = std::unique_ptr<draco::PointAttribute>(
      new draco::PointAttribute(raw_descriptor));
  raw->SetIdentityMapping();
  if (!raw->Reset(4)) {
    return 4;
  }
  constexpr float kRawValues[4] = {0.25f, 0.5f, 0.75f, 1.0f};
  for (int i = 0; i < 4; ++i) {
    raw->SetAttributeValue(draco::AttributeValueIndex(i), &kRawValues[i]);
  }
  mesh.AddAttribute(std::move(raw));

  draco::Encoder encoder;
  encoder.SetEncodingMethod(draco::MESH_SEQUENTIAL_ENCODING);
  encoder.SetSpeedOptions(5, 5);
  encoder.SetAttributeQuantization(draco::GeometryAttribute::POSITION, 12);
  encoder.options().SetGlobalBool("compress_connectivity", true);
  draco::EncoderBuffer encoded;
  const draco::Status status = encoder.EncodeMeshToBuffer(mesh, &encoded);
  if (!status.ok()) {
    return 5;
  }

  std::ofstream output(argv[1], std::ios::binary);
  output.write(encoded.data(), static_cast<std::streamsize>(encoded.size()));
  return output.good() ? 0 : 6;
}
