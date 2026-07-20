#include "fsv_draco_request_registry.h"

namespace fsv_draco {

std::shared_ptr<FsvDecodeRequestRegistry::Entry>
FsvDecodeRequestRegistry::Register(const std::string& request_id,
                                   uint64_t working_byte_limit) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (detached_ || active_.find(request_id) != active_.end()) {
    return nullptr;
  }
  auto entry = std::make_shared<Entry>(working_byte_limit);
  active_[request_id] = entry;
  return entry;
}

FsvCancelStatus FsvDecodeRequestRegistry::Cancel(
    const std::string& request_id) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto active = active_.find(request_id);
  if (active == active_.end()) {
    return finished_.find(request_id) != finished_.end()
               ? FsvCancelStatus::kAlreadyFinished
               : FsvCancelStatus::kUnknownRequest;
  }
  auto& entry = active->second;
  if (entry->state == Entry::State::kActive) {
    entry->state = Entry::State::kCancelled;
    entry->control->Cancel();
  }
  return entry->state == Entry::State::kFinished
             ? FsvCancelStatus::kAlreadyFinished
             : FsvCancelStatus::kCancelled;
}

bool FsvDecodeRequestRegistry::ShouldStart(
    const std::shared_ptr<Entry>& entry) const {
  std::lock_guard<std::mutex> lock(mutex_);
  return !detached_ && entry != nullptr &&
         entry->state == Entry::State::kActive;
}

FsvFinishDisposition FsvDecodeRequestRegistry::Finish(
    const std::string& request_id,
    const std::shared_ptr<Entry>& entry) {
  std::lock_guard<std::mutex> lock(mutex_);
  auto active = active_.find(request_id);
  if (active == active_.end() || active->second != entry) {
    return detached_ ? FsvFinishDisposition::kDetached
                     : FsvFinishDisposition::kCancelled;
  }
  FsvFinishDisposition disposition;
  if (detached_ || entry->state == Entry::State::kDetached) {
    disposition = FsvFinishDisposition::kDetached;
  } else if (entry->state == Entry::State::kCancelled) {
    disposition = FsvFinishDisposition::kCancelled;
  } else {
    disposition = FsvFinishDisposition::kSuccess;
  }
  entry->state = Entry::State::kFinished;
  entry->control.reset();
  active_.erase(active);
  if (!detached_) {
    finished_.insert(request_id);
    if (finished_.size() > kMaxFinishedRequests) {
      finished_.erase(finished_.begin());
    }
  }
  return disposition;
}

bool FsvDecodeRequestRegistry::ClaimDelivery(
    const std::shared_ptr<Entry>& entry) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (detached_ || entry == nullptr || entry->delivered) {
    return false;
  }
  entry->delivered = true;
  return true;
}

void FsvDecodeRequestRegistry::BeginDetach() {
  std::lock_guard<std::mutex> lock(mutex_);
  if (detached_) {
    return;
  }
  detached_ = true;
  for (auto& item : active_) {
    auto& entry = item.second;
    if (entry->state == Entry::State::kActive ||
        entry->state == Entry::State::kCancelled) {
      entry->state = Entry::State::kDetached;
      entry->control->Cancel();
    }
  }
}

void FsvDecodeRequestRegistry::DrainAfterWorkers() {
  std::lock_guard<std::mutex> lock(mutex_);
  for (auto& item : active_) {
    item.second->control.reset();
  }
  active_.clear();
  finished_.clear();
}

size_t FsvDecodeRequestRegistry::active_count() const {
  std::lock_guard<std::mutex> lock(mutex_);
  return active_.size();
}

}  // namespace fsv_draco
