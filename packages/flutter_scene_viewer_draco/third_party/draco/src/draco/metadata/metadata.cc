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
#include "draco/metadata/metadata.h"

#include <algorithm>
#include <utility>

namespace draco {
namespace {

bool Matches(const FsvString &left, const std::string &right) {
  return left.size() == right.size() &&
         std::equal(left.begin(), left.end(), right.begin());
}

}  // namespace

EntryValue::EntryValue(const EntryValue &value) : EntryValue(value, nullptr) {}

EntryValue::EntryValue(const EntryValue &value, FsvDecodeControl *control)
    : control_(control),
      controlled_data_(FsvDecodeAllocator<uint8_t>(control)) {
  Resize(value.size());
  if (value.size() != 0) {
    memcpy(MutableData(), value.bytes(), value.size());
  }
}

EntryValue::EntryValue(EntryValue &&value)
    : EntryValue(std::move(value), nullptr) {}

EntryValue::EntryValue(EntryValue &&value, FsvDecodeControl *control)
    : EntryValue(static_cast<const EntryValue &>(value), control) {}

EntryValue::EntryValue(const std::string &value, FsvDecodeControl *control)
    : control_(control),
      controlled_data_(FsvDecodeAllocator<uint8_t>(control)) {
  Resize(value.size());
  if (!value.empty()) {
    memcpy(MutableData(), value.data(), value.size());
  }
}

EntryValue::EntryValue(FsvVector<uint8_t> &&data)
    : control_(data.get_allocator().control()),
      controlled_data_(FsvDecodeAllocator<uint8_t>(control_)) {
  if (control_ == nullptr) {
    host_data_.assign(data.begin(), data.end());
  } else {
    controlled_data_ = std::move(data);
  }
}

const std::vector<uint8_t> &EntryValue::data() const {
  if (control_ == nullptr) {
    return host_data_;
  }
  public_data_cache_.assign(controlled_data_.begin(), controlled_data_.end());
  return public_data_cache_;
}

template <>
bool EntryValue::GetValue(std::string *value) const {
  if (size() == 0) {
    return false;
  }
  value->assign(reinterpret_cast<const char *>(bytes()), size());
  return true;
}

Metadata::Metadata() : Metadata(nullptr) {}

Metadata::Metadata(FsvDecodeControl *control)
    : control_(control),
      controlled_entries_(
          std::less<FsvString>(),
          FsvDecodeAllocator<std::pair<const FsvString, EntryValue>>(control)),
      controlled_sub_metadatas_(
          std::less<FsvString>(),
          FsvDecodeAllocator<
              std::pair<const FsvString, std::unique_ptr<Metadata>>>(control)) {
}

Metadata::Metadata(const Metadata &metadata) : Metadata(metadata, nullptr) {}

Metadata::Metadata(const Metadata &metadata, FsvDecodeControl *control)
    : Metadata(control) {
  if (metadata.control_ == nullptr) {
    for (const auto &entry : metadata.entries_) {
      AddEntryBinary(entry.first, entry.second.data());
    }
    for (const auto &sub_metadata_entry : metadata.sub_metadatas_) {
      std::unique_ptr<Metadata> sub_metadata(
          new (control_) Metadata(*sub_metadata_entry.second, control_));
      AddSubMetadata(sub_metadata_entry.first, std::move(sub_metadata));
    }
  } else {
    for (const auto &entry : metadata.controlled_entries_) {
      FsvString name(entry.first.begin(), entry.first.end(),
                     FsvDecodeAllocator<char>(control_));
      FsvVector<uint8_t> value(entry.second.bytes(),
                               entry.second.bytes() + entry.second.size(),
                               FsvDecodeAllocator<uint8_t>(control_));
      AddEntryBinary(std::move(name), std::move(value));
    }
    for (const auto &sub_metadata_entry :
         metadata.controlled_sub_metadatas_) {
      FsvString name(sub_metadata_entry.first.begin(),
                     sub_metadata_entry.first.end(),
                     FsvDecodeAllocator<char>(control_));
      std::unique_ptr<Metadata> sub_metadata(
          new (control_) Metadata(*sub_metadata_entry.second, control_));
      AddSubMetadata(std::move(name), std::move(sub_metadata));
    }
  }
}

Metadata::Metadata(Metadata &&metadata)
    : Metadata(static_cast<const Metadata &>(metadata), nullptr) {}

Metadata::Metadata(Metadata &&metadata, FsvDecodeControl *control)
    : Metadata(static_cast<const Metadata &>(metadata), control) {}

Metadata::ControlledEntryMap::iterator Metadata::FindControlledEntry(
    const std::string &name) {
  return std::find_if(controlled_entries_.begin(), controlled_entries_.end(),
                      [&name](const ControlledEntryMap::value_type &entry) {
                        return Matches(entry.first, name);
                      });
}

Metadata::ControlledEntryMap::const_iterator Metadata::FindControlledEntry(
    const std::string &name) const {
  return std::find_if(controlled_entries_.begin(), controlled_entries_.end(),
                      [&name](const ControlledEntryMap::value_type &entry) {
                        return Matches(entry.first, name);
                      });
}

Metadata::ControlledSubMetadataMap::iterator
Metadata::FindControlledSubMetadata(const std::string &name) {
  return std::find_if(
      controlled_sub_metadatas_.begin(), controlled_sub_metadatas_.end(),
      [&name](const ControlledSubMetadataMap::value_type &entry) {
        return Matches(entry.first, name);
      });
}

Metadata::ControlledSubMetadataMap::const_iterator
Metadata::FindControlledSubMetadata(const std::string &name) const {
  return std::find_if(
      controlled_sub_metadatas_.begin(), controlled_sub_metadatas_.end(),
      [&name](const ControlledSubMetadataMap::value_type &entry) {
        return Matches(entry.first, name);
      });
}

void Metadata::AddEntryInt(const std::string &name, int32_t value) {
  AddEntry(name, value);
}
bool Metadata::GetEntryInt(const std::string &name, int32_t *value) const {
  return GetEntry(name, value);
}
void Metadata::AddEntryIntArray(const std::string &name,
                                const std::vector<int32_t> &value) {
  AddEntry(name, value);
}
bool Metadata::GetEntryIntArray(const std::string &name,
                                std::vector<int32_t> *value) const {
  return GetEntry(name, value);
}
void Metadata::AddEntryDouble(const std::string &name, double value) {
  AddEntry(name, value);
}
bool Metadata::GetEntryDouble(const std::string &name, double *value) const {
  return GetEntry(name, value);
}
void Metadata::AddEntryDoubleArray(const std::string &name,
                                   const std::vector<double> &value) {
  AddEntry(name, value);
}
bool Metadata::GetEntryDoubleArray(const std::string &name,
                                   std::vector<double> *value) const {
  return GetEntry(name, value);
}
void Metadata::AddEntryString(const std::string &name,
                              const std::string &value) {
  AddEntry(name, value);
}
bool Metadata::GetEntryString(const std::string &name,
                              std::string *value) const {
  return GetEntry(name, value);
}
void Metadata::AddEntryBinary(const std::string &name,
                              const std::vector<uint8_t> &value) {
  AddEntry(name, value);
}
void Metadata::AddEntryBinary(FsvString name, FsvVector<uint8_t> value) {
  if (control_ == nullptr) {
    const std::string host_name(name.begin(), name.end());
    entries_.erase(host_name);
    entries_.emplace(host_name, EntryValue(std::move(value)));
    return;
  }
  const auto existing = controlled_entries_.find(name);
  if (existing != controlled_entries_.end()) {
    controlled_entries_.erase(existing);
  }
  controlled_entries_.emplace(std::piecewise_construct,
                              std::forward_as_tuple(std::move(name)),
                              std::forward_as_tuple(std::move(value)));
}
bool Metadata::GetEntryBinary(const std::string &name,
                              std::vector<uint8_t> *value) const {
  return GetEntry(name, value);
}

bool Metadata::AddSubMetadata(const std::string &name,
                              std::unique_ptr<Metadata> sub_metadata) {
  if (control_ == nullptr) {
    if (!sub_metadata || sub_metadatas_.find(name) != sub_metadatas_.end()) {
      return false;
    }
    if (sub_metadata->fsv_decode_control() != nullptr) {
      sub_metadata.reset(new Metadata(*sub_metadata));
    }
    sub_metadatas_.emplace(name, std::move(sub_metadata));
    return true;
  }
  FsvString controlled_name(name.begin(), name.end(),
                            FsvDecodeAllocator<char>(control_));
  return AddSubMetadata(std::move(controlled_name), std::move(sub_metadata));
}

bool Metadata::AddSubMetadata(FsvString name,
                              std::unique_ptr<Metadata> sub_metadata) {
  if (!sub_metadata) {
    return false;
  }
  if (control_ == nullptr) {
    return AddSubMetadata(std::string(name.begin(), name.end()),
                          std::move(sub_metadata));
  }
  if (controlled_sub_metadatas_.find(name) !=
      controlled_sub_metadatas_.end()) {
    return false;
  }
  if (sub_metadata->fsv_decode_control() != control_) {
    sub_metadata.reset(new (control_) Metadata(*sub_metadata, control_));
  }
  controlled_sub_metadatas_.emplace(
      std::piecewise_construct, std::forward_as_tuple(std::move(name)),
      std::forward_as_tuple(std::move(sub_metadata)));
  return true;
}

const Metadata *Metadata::GetSubMetadata(const std::string &name) const {
  if (control_ == nullptr) {
    const auto sub_ptr = sub_metadatas_.find(name);
    return sub_ptr == sub_metadatas_.end() ? nullptr : sub_ptr->second.get();
  }
  const auto sub_ptr = FindControlledSubMetadata(name);
  return sub_ptr == controlled_sub_metadatas_.end() ? nullptr
                                                    : sub_ptr->second.get();
}

Metadata *Metadata::sub_metadata(const std::string &name) {
  if (control_ == nullptr) {
    const auto sub_ptr = sub_metadatas_.find(name);
    return sub_ptr == sub_metadatas_.end() ? nullptr : sub_ptr->second.get();
  }
  const auto sub_ptr = FindControlledSubMetadata(name);
  return sub_ptr == controlled_sub_metadatas_.end() ? nullptr
                                                    : sub_ptr->second.get();
}

void Metadata::RemoveEntry(const std::string &name) {
  if (control_ == nullptr) {
    entries_.erase(name);
    return;
  }
  const auto entry_ptr = FindControlledEntry(name);
  if (entry_ptr != controlled_entries_.end()) {
    controlled_entries_.erase(entry_ptr);
  }
}

int Metadata::num_entries() const {
  return static_cast<int>(control_ == nullptr ? entries_.size()
                                               : controlled_entries_.size());
}

const Metadata::EntryMap &Metadata::entries() const {
  if (control_ == nullptr) {
    return entries_;
  }
  public_entries_cache_.clear();
  for (const auto &entry : controlled_entries_) {
    public_entries_cache_.emplace(
        std::string(entry.first.begin(), entry.first.end()),
        EntryValue(entry.second));
  }
  return public_entries_cache_;
}

const Metadata::SubMetadataMap &Metadata::sub_metadatas() const {
  if (control_ == nullptr) {
    return sub_metadatas_;
  }
  public_sub_metadatas_cache_.clear();
  for (const auto &entry : controlled_sub_metadatas_) {
    public_sub_metadatas_cache_.emplace(
        std::string(entry.first.begin(), entry.first.end()),
        std::unique_ptr<Metadata>(new Metadata(*entry.second)));
  }
  return public_sub_metadatas_cache_;
}

}  // namespace draco
