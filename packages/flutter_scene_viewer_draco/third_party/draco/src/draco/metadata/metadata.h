// Copyright 2017 The Draco Authors.
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
#ifndef DRACO_METADATA_METADATA_H_
#define DRACO_METADATA_METADATA_H_

#include <cstring>
#include <map>
#include <memory>
#include <string>
#include <string_view>
#include <utility>
#include <vector>

#include "draco/core/fsv_decode_allocator.h"
#include "draco/core/hash_utils.h"

namespace draco {

class MetadataDecoder;

// FSV LOCAL MODIFICATION (Apache-2.0 section 4(b)): metadata entry payloads
// retain the destination request allocator explicitly. Ordinary copies and
// moves detach onto the host allocator so they cannot retain a dead request.
class EntryValue {
 public:
  EntryValue(const EntryValue &value);
  EntryValue(const EntryValue &value, FsvDecodeControl *control);
  EntryValue(EntryValue &&value);
  EntryValue(EntryValue &&value, FsvDecodeControl *control);

  template <typename DataTypeT>
  explicit EntryValue(const DataTypeT &data, FsvDecodeControl *control = nullptr)
      : control_(control),
        controlled_data_(FsvDecodeAllocator<uint8_t>(control)) {
    const size_t data_type_size = sizeof(DataTypeT);
    Resize(data_type_size);
    if (data_type_size != 0) {
      memcpy(MutableData(), &data, data_type_size);
    }
  }

  template <typename DataTypeT>
  explicit EntryValue(const std::vector<DataTypeT> &data,
                      FsvDecodeControl *control = nullptr)
      : control_(control),
        controlled_data_(FsvDecodeAllocator<uint8_t>(control)) {
    const size_t total_size = sizeof(DataTypeT) * data.size();
    Resize(total_size);
    if (total_size != 0) {
      memcpy(MutableData(), data.data(), total_size);
    }
  }

  explicit EntryValue(const std::string &value,
                      FsvDecodeControl *control = nullptr);
  explicit EntryValue(FsvVector<uint8_t> &&data);

  template <typename DataTypeT>
  bool GetValue(DataTypeT *value) const {
    const size_t data_type_size = sizeof(DataTypeT);
    if (data_type_size != size()) {
      return false;
    }
    memcpy(value, bytes(), data_type_size);
    return true;
  }

  template <typename DataTypeT>
  bool GetValue(std::vector<DataTypeT> *value) const {
    if (size() == 0) {
      return false;
    }
    const size_t data_type_size = sizeof(DataTypeT);
    if (size() % data_type_size != 0) {
      return false;
    }
    value->resize(size() / data_type_size);
    memcpy(value->data(), bytes(), size());
    return true;
  }

  const std::vector<uint8_t> &data() const;

 private:
  size_t size() const {
    return control_ == nullptr ? host_data_.size() : controlled_data_.size();
  }
  const uint8_t *bytes() const {
    return control_ == nullptr ? host_data_.data() : controlled_data_.data();
  }
  uint8_t *MutableData() {
    return control_ == nullptr ? host_data_.data() : controlled_data_.data();
  }
  void Resize(size_t size) {
    if (control_ == nullptr) {
      host_data_.resize(size);
    } else {
      controlled_data_.resize(size);
    }
  }

  FsvDecodeControl *control_ = nullptr;
  std::vector<uint8_t> host_data_;
  FsvVector<uint8_t> controlled_data_;
  mutable std::vector<uint8_t> public_data_cache_;

  friend class Metadata;
  friend struct EntryValueHasher;
};

struct EntryValueHasher {
  size_t operator()(const EntryValue &ev) const {
    size_t hash = ev.size();
    for (size_t i = 0; i < ev.size(); ++i) {
      hash = HashCombine(ev.bytes()[i], hash);
    }
    return hash;
  }
};

class Metadata : public FsvDecodeAllocated {
 public:
  using EntryMap = std::map<std::string, EntryValue>;
  using SubMetadataMap = std::map<std::string, std::unique_ptr<Metadata>>;

  Metadata();
  explicit Metadata(FsvDecodeControl *control);
  Metadata(const Metadata &metadata);
  Metadata(const Metadata &metadata, FsvDecodeControl *control);
  Metadata(Metadata &&metadata);
  Metadata(Metadata &&metadata, FsvDecodeControl *control);
  ~Metadata() = default;

  FsvDecodeControl *fsv_decode_control() const { return control_; }

  void AddEntryInt(const std::string &name, int32_t value);
  bool GetEntryInt(const std::string &name, int32_t *value) const;
  void AddEntryIntArray(const std::string &name,
                        const std::vector<int32_t> &value);
  bool GetEntryIntArray(const std::string &name,
                        std::vector<int32_t> *value) const;
  void AddEntryDouble(const std::string &name, double value);
  bool GetEntryDouble(const std::string &name, double *value) const;
  void AddEntryDoubleArray(const std::string &name,
                           const std::vector<double> &value);
  bool GetEntryDoubleArray(const std::string &name,
                           std::vector<double> *value) const;
  void AddEntryString(const std::string &name, const std::string &value);
  bool GetEntryString(const std::string &name, std::string *value) const;
  void AddEntryBinary(const std::string &name,
                      const std::vector<uint8_t> &value);
  bool GetEntryBinary(const std::string &name,
                      std::vector<uint8_t> *value) const;

  bool AddSubMetadata(const std::string &name,
                      std::unique_ptr<Metadata> sub_metadata);
  const Metadata *GetSubMetadata(const std::string &name) const;
  Metadata *sub_metadata(const std::string &name);
  void RemoveEntry(const std::string &name);

  int num_entries() const;
  const EntryMap &entries() const;
  const SubMetadataMap &sub_metadatas() const;

 private:
  using ControlledEntryMap = FsvMap<FsvString, EntryValue>;
  using ControlledSubMetadataMap =
      FsvMap<FsvString, std::unique_ptr<Metadata>>;

  template <typename DataTypeT>
  void AddEntry(const std::string &entry_name, const DataTypeT &entry_value) {
    RemoveEntry(entry_name);
    if (control_ == nullptr) {
      entries_.emplace(entry_name, EntryValue(entry_value));
      return;
    }
    FsvString name(entry_name.begin(), entry_name.end(),
                   FsvDecodeAllocator<char>(control_));
    controlled_entries_.emplace(std::piecewise_construct,
                                std::forward_as_tuple(std::move(name)),
                                std::forward_as_tuple(entry_value, control_));
  }

  template <typename DataTypeT>
  bool GetEntry(const std::string &entry_name, DataTypeT *entry_value) const {
    if (control_ == nullptr) {
      const auto itr = entries_.find(entry_name);
      return itr != entries_.end() && itr->second.GetValue(entry_value);
    }
    const auto itr = FindControlledEntry(entry_name);
    return itr != controlled_entries_.end() &&
           itr->second.GetValue(entry_value);
  }

  ControlledEntryMap::iterator FindControlledEntry(const std::string &name);
  ControlledEntryMap::const_iterator FindControlledEntry(
      const std::string &name) const;
  ControlledSubMetadataMap::iterator FindControlledSubMetadata(
      const std::string &name);
  ControlledSubMetadataMap::const_iterator FindControlledSubMetadata(
      const std::string &name) const;
  bool AddSubMetadata(FsvString name,
                      std::unique_ptr<Metadata> sub_metadata);
  void AddEntryBinary(FsvString name, FsvVector<uint8_t> value);

  FsvDecodeControl *control_;
  EntryMap entries_;
  SubMetadataMap sub_metadatas_;
  ControlledEntryMap controlled_entries_;
  ControlledSubMetadataMap controlled_sub_metadatas_;
  mutable EntryMap public_entries_cache_;
  mutable SubMetadataMap public_sub_metadatas_cache_;

  friend class MetadataDecoder;
  friend struct MetadataHasher;
};

struct MetadataHasher {
  size_t operator()(const Metadata &metadata) const {
    const size_t entry_count = metadata.control_ == nullptr
                                   ? metadata.entries_.size()
                                   : metadata.controlled_entries_.size();
    const size_t sub_metadata_count =
        metadata.control_ == nullptr ? metadata.sub_metadatas_.size()
                                     : metadata.controlled_sub_metadatas_.size();
    size_t hash = HashCombine(entry_count, sub_metadata_count);
    EntryValueHasher entry_value_hasher;
    MetadataHasher metadata_hasher;
    if (metadata.control_ == nullptr) {
      for (const auto &entry : metadata.entries_) {
        hash = HashCombine(entry.first, hash);
        hash = HashCombine(entry_value_hasher(entry.second), hash);
      }
      for (const auto &sub_metadata : metadata.sub_metadatas_) {
        hash = HashCombine(sub_metadata.first, hash);
        hash = HashCombine(metadata_hasher(*sub_metadata.second), hash);
      }
    } else {
      for (const auto &entry : metadata.controlled_entries_) {
        hash = HashCombine(
            std::string_view(entry.first.data(), entry.first.size()), hash);
        hash = HashCombine(entry_value_hasher(entry.second), hash);
      }
      for (const auto &sub_metadata : metadata.controlled_sub_metadatas_) {
        hash = HashCombine(std::string_view(sub_metadata.first.data(),
                                            sub_metadata.first.size()),
                           hash);
        hash = HashCombine(metadata_hasher(*sub_metadata.second), hash);
      }
    }
    return hash;
  }
};

}  // namespace draco

#endif  // DRACO_METADATA_METADATA_H_
